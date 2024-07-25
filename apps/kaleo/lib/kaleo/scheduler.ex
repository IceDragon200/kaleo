defmodule Kaleo.Scheduler do
  defmodule State do
    defstruct [
      items: nil,
      bucket_durations: [],
      ready: nil,
      buckets: %{},
      timers: %{},
      has_ready: false,
    ]

    @type t :: %__MODULE__{
      items: :ets.table(),
      ready: :ets.table(),
      bucket_durations: [timeout()],
      buckets: %{
        timeout() => :ets.table(),
      },
      timers: %{
        timeout() => reference(),
      },
      has_ready: boolean(),
    }
  end

  use Loxe.Logger
  use GenServer

  def start_link(_) do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  @impl true
  def init(:ok) do
    Loxe.Logger.metadata worker: :kaleo_scheduler

    bucket_durations = [
      :timer.seconds(10),
      :timer.minutes(1),
      :timer.minutes(5),
      :timer.minutes(10),
      :timer.minutes(30),
      :timer.hours(1),
      :timer.hours(8),
      :timer.hours(24),
    ]

    bucket_durations = Enum.sort(bucket_durations)

    state = %State{
      items: :ets.new(:items, [:set, :private]),
      ready: :ets.new(:ready, [:set, :private]),
      bucket_durations: bucket_durations,
      buckets: Enum.reduce(bucket_durations, %{}, fn duration, acc ->
        Map.put(acc, duration, :ets.new(:bucket, [:set, :private]))
      end)
    }

    Loxe.Logger.info "initialized"

    {:ok, state, {:continue, :start_timers}}
  end

  @impl true
  def terminate(reason, %State{} = state) do
    Loxe.Logger.info "terminated scheduler", reason: inspect(reason)

    Enum.each(state.buckets, fn {_, tab} ->
      :ets.delete(tab)
    end)
  end

  @impl true
  def handle_continue(:start_timers, %State{} = state) do
    Loxe.Logger.info "initializing timers"
    state = start_timers(state)
    Loxe.Logger.info "initialized timers"
    {:noreply, state}
  end

  @impl true
  def handle_continue(:ready, %State{} = state) do
    state = process_ready_bucket(state)
    {:noreply, state}
  end

  @impl true
  def handle_info({:timer_tick, duration}, %State{} = state) do
    Loxe.Logger.debug "ticking", duration: duration
    case Map.fetch(state.buckets, duration) do
      {:ok, bucket} ->
        # restart the timer immediately so it starts counting down
        state = restart_timer(duration, :tick, state)
        # process the bucket now
        state = check_bucket_tick(duration, bucket, state)
        if state.has_ready do
          {:noreply, state, {:continue, :ready}}
        else
          {:noreply, state}
        end

      :error ->
        timers = Map.delete(state.timers, duration)
        state = %{
          state
          | timers: timers
        }
        {:noreply, state}
    end
  end

  defp process_ready_bucket(%State{} = state) do
    try do
      true = :ets.safe_fixtable(state.ready, true)
      reduce_ready_bucket(state.ready, :ets.first(state.ready), state)
    after
      true = :ets.safe_fixtable(state.ready, false)
    end
  end

  defp reduce_ready_bucket(_table, :":$end_of_table", %State{} = state) do
    state
  end

  defp reduce_ready_bucket(table, key, %State{} = state) do
    case :ets.take(table, key) do
      [] ->
        :ok

      [{^key, item_id}] ->
        case :ets.lookup(state.items, item_id) do
          [] ->
            :ok

          [{^item_id, item}] ->
            IO.inspect item
            :ok
        end
    end

    reduce_ready_bucket(table, :ets.next(table, key), state)
  end

  defp check_bucket_tick(duration, bucket, %State{} = state) do
    try do
      true = :ets.safe_fixtable(bucket, true)
      reduce_bucket_for_tick(duration, bucket, :ets.first(bucket), state)
    after
      true = :ets.safe_fixtable(bucket, false)
    end
  end

  defp reduce_bucket_for_tick(_duration, _bucket, :"$end_of_table", %State{} = state) do
    state
  end

  defp reduce_bucket_for_tick(duration, table, key, %State{} = state) do
    state =
      case :ets.take(table, key) do
        [] ->
          state

        [{^key, {trigger_in, item_id}}] ->
          trigger_in = trigger_in - duration
          if trigger_in <= 0 do
            true = :ets.insert(state.ready, {item_id, true})
            %{state | has_ready: true}
          else
            new_duration = choose_next_bucket(trigger_in, state)

            true = :ets.insert(state.buckets[new_duration], {key, {trigger_in, item_id}})
            state
          end
      end

    reduce_bucket_for_tick(duration, table, :ets.next(table, key), state)
  end

  @spec choose_next_bucket(timeout(), State.t()) :: timeout()
  defp choose_next_bucket(remaining_time, %State{} = state) do
    Enum.reduce_while(state.bucket_durations, nil, fn
      duration, nil ->
        {:cont, duration}

      duration, prev ->
        if remaining_time < duration do
          {:halt, prev}
        else
          {:cont, duration}
        end
    end)
  end

  defp start_timers(%State{} = state) do
    Enum.each(state.timers, fn {_, ref} ->
      Process.cancel_timer(ref)
    end)

    state =
      Enum.reduce(state.buckets, %{state | timers: %{}}, fn
        {duration, _}, %State{} = state when is_integer(duration) ->
          Loxe.Logger.debug "starting timer", duration: duration
          restart_timer(duration, :init, state)
      end)

    state
  end

  defp restart_timer(duration, reason, %State{} = state) when is_integer(duration) do
    Loxe.Logger.debug "restarting timer", duration: duration, reason: reason

    timers =
      case Map.pop(state.timers, duration) do
        {nil, timers} ->
          timers

        {ref, timers} ->
          Process.cancel_timer(ref)
          timers
      end

    timer_ref = Process.send_after(self(), {:timer_tick, duration}, duration)

    timers = Map.put(timers, duration, timer_ref)

    %{
      state
      | timers: timers
    }
  end
end
