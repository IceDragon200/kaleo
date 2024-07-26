defmodule Kaleo.Scheduler do
  defmodule State do
    defstruct [
      config_path: nil,
      config: nil,
      items: nil,
      pending_schedule: nil,
      ready: nil,
      bucket_durations: [],
      buckets: %{},
      timers: %{},
      has_ready: false,
      has_pending_schedule: false,
    ]

    @type t :: %__MODULE__{
      config_path: Path.t(),
      config: Keyword.t(),
      items: :ets.table(),
      pending_schedule: :ets.table(),
      ready: :ets.table(),
      bucket_durations: [timeout()],
      buckets: %{
        timeout() => :ets.table(),
      },
      timers: %{
        timeout() => reference(),
      },
      has_ready: boolean(),
      has_pending_schedule: boolean(),
    }
  end

  use Loxe.Logger
  use GenServer

  alias Kaleo.Event

  import Kaleo.ConfigUtil
  import Kaleo.Core.Util

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
      pending_schedule: :ets.new(:pending_schedule, [:set, :private]),
      ready: :ets.new(:ready, [:set, :private]),
      bucket_durations: bucket_durations,
      buckets: Enum.reduce(bucket_durations, %{}, fn duration, acc ->
        Map.put(acc, duration, :ets.new(:bucket, [:set, :private]))
      end)
    }

    Loxe.Logger.info "initialized"

    Kaleo.ConfigHost.watch_config()

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
  def handle_continue(:after_tick, %State{} = state) do
    now = DateTime.utc_now()

    state =
      if state.has_ready do
        state = %{state | has_ready: false}
        process_ready_bucket(now, state)
      else
        state
      end

    state =
      if state.has_pending_schedule do
        state = %{state | has_pending_schedule: false}
        process_pending_schedule(now, state)
      else
        state
      end

    {:noreply, state}
  end

  @impl true
  def handle_info(config_changed_event() = event, %State{} = state) do
    path = config_changed_event(event, :path)
    config = config_changed_event(event, :config)
    state = on_config_changed(path, config, state)

    {:noreply, state, {:continue, :after_tick}}
  end

  @impl true
  def handle_info({:timer_tick, duration}, %State{} = state) do
    Loxe.Logger.debug "ticking", duration: duration
    now = DateTime.utc_now()
    state =
      case Map.fetch(state.buckets, duration) do
        {:ok, bucket} ->
          # restart the timer immediately so it starts counting down
          state = restart_timer(duration, :tick, state)
          # process the bucket now
          state = check_bucket_tick(now, duration, bucket, state)

          state

        :error ->
          timers = Map.delete(state.timers, duration)
          %{
            state
            | timers: timers
          }
      end

    {:noreply, state, {:continue, :after_tick}}
  end

  defp process_pending_schedule(%DateTime{} = now, %State{} = state) do
    try do
      true = :ets.safe_fixtable(state.pending_schedule, true)
      reduce_pending_schedule(
        now,
        state.pending_schedule,
        :ets.first(state.pending_schedule),
        state
      )
    after
      true = :ets.safe_fixtable(state.pending_schedule, false)
    end
  end

  defp reduce_pending_schedule(%DateTime{} = _now, _table, :"$end_of_table", %State{} = state) do
    state
  end

  defp reduce_pending_schedule(%DateTime{} = now, table, key, %State{} = state) do
    state =
      case :ets.take(table, key) do
        [] ->
          state

        [{item_id, {:item, nil, %Event{} = item}}] ->
          schedule_item(now, item_id, item, state)

        [{item_id, {:item_id, ready_at, item_id}}] ->
          schedule_item_id_with_ready_at(ready_at, now, item_id, state)
      end

    reduce_pending_schedule(now, table, :ets.next(table, key), state)
  end

  defp schedule_item_id_with_ready_at(ready_at, %DateTime{} = now, item_id, %State{} = state) do
    now_unix = DateTime.to_unix(now, :millisecond)
    ready_in = max(ready_at - now_unix, 0)
    bucket_id = choose_next_bucket(ready_in, state)

    true = :ets.insert(state.buckets[bucket_id], {item_id, {ready_at, item_id}})

    Loxe.Logger.debug "scheduled item",
      item_id: item_id,
      initial_bucket_id: bucket_id,
      ready_in: UnitFmt.format_time(ready_in, :millisecond),
      ready_at: DateTime.from_unix!(ready_at, :millisecond)

    state
  end

  defp add_item(%DateTime{} = now, item_id, %Event{} = item, %State{} = state) do
    true = :ets.insert(state.items, {item_id, item})

    ready_in = Event.time_until_next_trigger(item, now, :millisecond)
    now_unix = DateTime.to_unix(now, :millisecond)
    ready_at = now_unix + ready_in

    schedule_item_id_with_ready_at(ready_at, now, item_id, state)
  end

  @spec schedule_item(DateTime.t(), String.t(), Event.t(), State.t()) :: State.t()
  defp schedule_item(now, item_id, %Event{} = item, %State{} = state) do
    if Event.ended?(item, now) do
      Loxe.Logger.warning "scheduled item has already ended, skipping", item_id: item_id
      state
    else
      add_item(now, item_id, item, state)
    end
  end

  defp maybe_schedule_item(now, item_id, %Event{} = item, %State{} = state) do
    if Event.ended?(item, now) do
      Loxe.Logger.warning "item has already ended, skipping", item_id: item_id
      state
    else
      case item.every do
        [] ->
          Loxe.Logger.info "item is not recurring, not scheduling"

        [_ | _] ->
          add_item(now, item_id, item, state)
      end
    end
  end

  defp process_ready_bucket(now, %State{} = state) do
    try do
      true = :ets.safe_fixtable(state.ready, true)
      reduce_ready_bucket(now, state.ready, :ets.first(state.ready), state)
    after
      true = :ets.safe_fixtable(state.ready, false)
    end
  end

  defp reduce_ready_bucket(_now, _table, :"$end_of_table", %State{} = state) do
    state
  end

  defp reduce_ready_bucket(now, table, key, %State{} = state) do
    state =
      case :ets.take(table, key) do
        [] ->
          state

        [{^key, {ready_at, item_id}}] ->
          case :ets.lookup(state.items, item_id) do
            [] ->
              Loxe.Logger.warning "item not found", item_id: item_id
              state

            [{^item_id, %Event{} = item}] ->
              {:ok, _ref} = Kaleo.EventProcessor.process_ready_event(ready_at, item)
              maybe_schedule_item(now, item_id, item, state)
          end
      end

    reduce_ready_bucket(now, table, :ets.next(table, key), state)
  end

  defp check_bucket_tick(now, duration, bucket, %State{} = state) do
    try do
      true = :ets.safe_fixtable(bucket, true)
      reduce_bucket_for_tick(now, duration, bucket, :ets.first(bucket), state)
    after
      true = :ets.safe_fixtable(bucket, false)
    end
  end

  defp reduce_bucket_for_tick(_now, _duration, _bucket, :"$end_of_table", %State{} = state) do
    state
  end

  defp reduce_bucket_for_tick(now, bucket_duration, table, key, %State{} = state) do
    state =
      case :ets.take(table, key) do
        [] ->
          Loxe.Logger.warning "key missing from tick bucket", key: inspect(key)
          state

        [{^key, {trigger_at, item_id}}] ->
          now_unix = DateTime.to_unix(now, :millisecond)
          trigger_in = trigger_at - now_unix
          if trigger_in <= 0 do
            Loxe.Logger.info "an item is ready", item_id: item_id
            true = :ets.insert(state.ready, {item_id, {now, item_id}})
            %{state | has_ready: true}
          else
            bucket_id = choose_next_bucket(trigger_in, state)
            Loxe.Logger.debug "item is not ready, rescheduling",
              item_id: item_id,
              next_bucket_id: bucket_id,
              trigger_in: UnitFmt.format_time(trigger_in, :millisecond)

            true = :ets.insert(state.pending_schedule, {item_id, {:item_id, trigger_at, item_id}})
            state
          end
      end

    reduce_bucket_for_tick(now, bucket_duration, table, :ets.next(table, key), state)
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
    Loxe.Logger.debug "restarting timer",
      duration: duration,
      reason: reason

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

  defp on_config_changed(path, config, %State{} = state) do
    case Keyword.fetch(config, :events) do
      {:ok, events} ->
        reload_events(%{state | config_path: path, config: events})

      :error ->
        state
    end
  end

  defp reload_events(%State{} = state) do
    # Events is a section name
    # it should contain a :sources key which is a id-ed list of paths that should be checked
    # for files
    dirname = Path.dirname(state.config_path)

    Loxe.Logger.info "reloading events", config_dirname: dirname
    case Keyword.fetch(state.config, :sources) do
      {:ok, sources} ->
        event_paths =
          Enum.reduce(sources, [], fn {id, opts}, acc ->
            path_opts = [source_id: id]
            Enum.reduce(opts, acc, fn
              {:pattern, pattern}, acc ->
                pattern = handle_unresolved_path(pattern, dirname)
                Enum.reduce(Path.wildcard(pattern), acc, fn path, acc ->
                  [{path, path_opts} | acc]
                end)

              {:path, path}, acc ->
                # a single file
                [{path, path_opts} | acc]
            end)
          end)

        load_events_from_paths(event_paths, state)

      :error ->
        Loxe.Logger.warning "no event sources!"
        state
    end
  end

  defp load_events_from_paths(event_paths, %State{} = state) when is_list(event_paths) do
    Enum.reduce(event_paths, state, fn {event_path, opts}, %State{} = state ->
      load_event_from_path(event_path, opts, state)
    end)
  end

  defp load_event_from_path(path, opts, %State{} = state) do
    Loxe.Logger.info "loading event from path", path: path
    with \
      {:ok, blob} <- File.read(path),
      {:ok, document, []} <- Kuddle.decode(blob)
    do
      load_event_from_kdl(document, opts, state)
    else
      {:error, reason} ->
        Loxe.Logger.error "could not load event", reason: inspect(reason)
        state
    end
  end

  alias Kuddle.Node, as: N

  defp load_event_from_kdl(document, _opts, %State{} = state) when is_list(document) do
    Enum.reduce(document, state, fn
      %N{name: "event", children: nil}, %State{} = state ->
        Loxe.Logger.warning "event node found, but it has no children"
        state

      %N{name: "event"} = n, %State{} = state ->
        load_event_from_kdl_node(n, state)

      %N{name: name}, %State{} = state ->
        Loxe.Logger.warning "unexpected node", name: name
        state
    end)
  end

  defp load_event_from_kdl_node(%N{children: children}, %State{} = state) do
    import Kaleo.KuddleUtil

    event =
      Enum.reduce(children, %Event{}, fn
        %N{name: "id"} = n, %Event{} = subject ->
          {:ok, id} = kdl_node_to_id(n)
          %{subject | id: id}

        %N{name: "name"} = n, %Event{} = subject ->
          {:ok, name} = kdl_node_to_string(n)
          %{subject | name: name}

        %N{name: "notes"} = n, %Event{} = subject ->
          {:ok, notes} = kdl_node_to_string(n)
          %{subject | notes: notes}

        %N{name: "starts_at"} = n, %Event{} = subject ->
          {:ok, starts_at} = kdl_node_to_datetime(n)
          %{subject | starts_at: starts_at}

        %N{name: "ends_at"} = n, %Event{} = subject ->
          {:ok, ends_at} = kdl_node_to_datetime(n)
          %{subject | ends_at: ends_at}

        %N{name: "every"} = n, %Event{} = subject ->
          {:ok, every} = kdl_node_to_interval(n)
          %{subject | every: every}
      end)

    case event.id do
      nil ->
        Loxe.Logger.error "invalid event, cannot add as its missing its id"
        state

      id when is_binary(id) ->
        Loxe.Logger.info "pushing event for scheduling", event_id: id
        true = :ets.insert(state.pending_schedule, {id, {:item, nil, event}})
        %{state | has_pending_schedule: true}
    end
  end
end
