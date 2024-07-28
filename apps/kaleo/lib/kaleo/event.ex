defmodule Kaleo.Event do
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

  alias __MODULE__, as: Event

  @type t :: %Event{
    id: String.t(),
    name: String.t(),
    notes: String.t(),
    starts_at: DateTime.t() | nil,
    ends_at: DateTime.t() | nil,
    trigger: Trigger.t() | nil
  }

  @type time_unit :: :day | :hour | :minute | System.time_unit()

  @spec time_until_next_trigger(
    t(),
    DateTime.t(),
    time_unit()
  ) :: number()
  def time_until_next_trigger(%Event{} = subject, now, unit \\ :millisecond) do
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
          raise "event has no trigger"

        %Event.Trigger{every: nil} ->
          raise "event.trigger has no intervals"

        %Event.Trigger{every: [{interval_unit, value}]} ->
          interval =
            case interval_unit do
              :second -> :timer.seconds(value)
              :minute -> :timer.minutes(value)
              :hour -> :timer.hours(value)
              :day -> :timer.hours(24 * value)
              :week -> :timer.hours(7 * 24 * value)
            end

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
  def time_to_start(%Event{} = subject, now, unit \\ :millisecond) do
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
  def time_to_end(%Event{} = subject, now, unit \\ :millisecond) do
    case subject.ends_at do
      nil ->
        nil

      %DateTime{} = datetime ->
        DateTime.diff(datetime, now, unit)
    end
  end

  @spec started?(t(), DateTime.t()) :: boolean()
  def started?(%Event{} = subject, now) do
    case time_to_start(subject, now, :millisecond) do
      nil ->
        true

      val when is_integer(val) ->
        val <= 0
    end
  end

  @spec ended?(t(), DateTime.t()) :: boolean()
  def ended?(%Event{} = subject, now) do
    case time_to_end(subject, now, :millisecond) do
      nil ->
        false

      val when is_integer(val) ->
        val <= 0
    end
  end
end
