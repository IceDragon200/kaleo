defmodule Kaleo.Item do
  defmodule Trigger do
    defmodule Expiration do
      defstruct [
        after: [],
      ]

      @type t :: %__MODULE__{
        after: [{atom(), integer()}]
      }
    end

    defstruct [
      expires: nil,
      every: [],
    ]

    @type t :: %__MODULE__{
      expires: Expiration.t() | nil,
      every: [{atom(), integer()}],
    }
  end

  defstruct [
    id: nil,
    name: nil,
    notes: nil,
    starts_at: nil,
    ends_at: nil,
    trigger: nil,
  ]

  alias __MODULE__, as: Item

  @type t :: %Item{
    id: String.t(),
    name: String.t(),
    notes: String.t(),
    starts_at: DateTime.t() | nil,
    ends_at: DateTime.t() | nil,
    trigger: Trigger.t() | nil
  }

  @type time_unit :: :day | :hour | :minute | System.time_unit()

  @spec interval_list_to_ms([integer()]) :: integer()
  def interval_list_to_ms(list) do
    Enum.reduce(list, 0, fn {interval_unit, value}, acc ->
      acc + case interval_unit do
        :second -> :timer.seconds(value)
        :minute -> :timer.minutes(value)
        :hour -> :timer.hours(value)
        :day -> :timer.hours(24 * value)
        :week -> :timer.hours(7 * 24 * value)
      end
    end)
  end

  @spec time_until_next_trigger(
    t(),
    DateTime.t(),
    time_unit()
  ) :: number()
  def time_until_next_trigger(%Item{} = subject, %DateTime{} = now, unit \\ :millisecond) do
    time_until_start =
      case time_to_start(subject, now, :millisecond) do
        nil ->
          0

        val when is_integer(val) ->
          max(val, 0)
      end

    if time_until_start > 0 do
      time_until_start
    else
      case subject.trigger do
        nil ->
          raise "item has no trigger"

        %Item.Trigger{every: nil} ->
          raise "item.trigger has no intervals"

        %Item.Trigger{every: every} when is_list(every) ->
          interval = interval_list_to_ms(every)

          time_since_start =
            case subject.starts_at do
              nil ->
                0

              %DateTime{} = dt ->
                DateTime.diff(now, dt, :millisecond)
            end

          time_until_next_tick =
            if interval > 0 do
              ticks = time_since_start / interval

              ticks = floor(ticks)
              next_ticks = ticks + 1

              time_of_next_tick = next_ticks * interval

              time_of_next_tick - time_since_start
            else
              raise "interval is zero, cannot calculate next tick"
            end

          if unit == :millisecond do
            time_until_next_tick
          else
            :erlang.convert_time_unit(floor(time_until_next_tick), :millisecond, unit)
          end
      end
    end
  end

  @spec time_to_start(
    t(),
    DateTime.t(),
    time_unit()
  ) :: integer() | nil
  def time_to_start(%Item{} = subject, %DateTime{} = now, unit \\ :millisecond) do
    case subject.starts_at do
      nil ->
        nil

      %DateTime{} = datetime ->
        DateTime.diff(datetime, now, unit)
    end
  end

  @spec time_to_end(
    t(),
    DateTime.t(),
    time_unit()
  ) :: integer() | nil
  def time_to_end(%Item{} = subject, %DateTime{} = now, unit \\ :millisecond) do
    case subject.ends_at do
      nil ->
        nil

      %DateTime{} = datetime ->
        DateTime.diff(datetime, now, unit)
    end
  end

  @spec started?(t(), DateTime.t()) :: boolean()
  def started?(%Item{} = subject, %DateTime{} = now) do
    case time_to_start(subject, now, :millisecond) do
      nil ->
        true

      val when is_integer(val) ->
        val <= 0
    end
  end

  @spec ended?(t(), DateTime.t()) :: boolean()
  def ended?(%Item{} = subject, %DateTime{} = now) do
    case time_to_end(subject, now, :millisecond) do
      nil ->
        false

      val when is_integer(val) ->
        val <= 0
    end
  end

  @spec trigger_expired?(t(), ready_at::DateTime.t(), now::DateTime.t()) :: boolean()
  def trigger_expired?(%Item{} = subject, %DateTime{} = ready_at, %DateTime{} = now) do
    case subject.trigger do
      nil ->
        false

      %Trigger{} = subject ->
        case subject.expires do
          nil ->
            false

          %Trigger.Expiration{} = subject ->
            after_ms = interval_list_to_ms(subject.after)

            DateTime.diff(now, ready_at, :millisecond) >= after_ms
        end
    end
  end
end
