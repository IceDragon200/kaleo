defmodule Kaleo.KuddleUtil do
  alias Kuddle.Node, as: N
  alias Kuddle.Value, as: V

  @spec kdl_node_to_string(N.t()) :: {:ok, String.t()} | {:error, term()}
  def kdl_node_to_string(%N{attributes: [%V{} = v]}) do
    case v.type do
      :string ->
        {:ok, v.value}
    end
  end

  @spec kdl_node_to_id(N.t()) :: {:ok, any()} | {:error, term()}
  def kdl_node_to_id(%N{attributes: [%V{} = v]}) do
    {:ok, v.value}
  end

  @spec kdl_node_to_integer(N.t()) :: {:ok, integer()} | {:error, term()}
  def kdl_node_to_integer(%N{attributes: [%V{} = v]}) do
    case v.type do
      :integer ->
        {:ok, v.value}
    end
  end

  @spec kdl_node_to_datetime(N.t()) :: {:ok, DateTime.t()} | {:error, term()}
  def kdl_node_to_datetime(%N{attributes: [%V{} = v]}) do
    case v.type do
      :string ->
        DateTime.from_iso8601(v.value)
    end
  end

  def kdl_node_to_datetime(%N{children: children}) when is_list(children) do
    parts = %{
      date: %{
        year: nil,
        month: nil,
        day: nil,
      },
      time: %{
        hour: nil,
        minute: nil,
        second: nil,
        microsecond: nil,
      },
      timezone: "UTC"
    }

    parts =
      Enum.reduce(children, parts, fn
        %N{name: "date"} = n, parts ->
          with {:ok, str} <- kdl_node_to_string(n),
               {:ok, {year, month, day}} <- Calendar.ISO.parse_date(str)
          do
            put_in(parts.date, %{
              year: year,
              month: month,
              day: day,
            })
          else
            {:error, _reason} = err ->
              throw err
          end

        %N{name: "time"} = n, parts ->
          with {:ok, str} <- kdl_node_to_string(n),
               {:ok, {hour, minute, second, microsecond}} <- Calendar.ISO.parse_time(str)
          do
            put_in(parts.time, %{
              hour: hour,
              minute: minute,
              second: second,
              microsecond: microsecond,
            })
          else
            {:error, _reason} = err ->
              throw err
          end

        %N{name: "timezone"} = n, parts ->
          with {:ok, str} <- kdl_node_to_string(n) do
            put_in(parts.timezone, str)
          else
            {:error, _reason} = err ->
              throw err
          end
      end)

    %{year: year, month: month, day: day} = parts.date
    %{hour: hour, minute: minute, second: second, microsecond: microsecond} = parts.time
    with {:ok, date} <- Date.new(year, month, day),
         {:ok, time} <- Time.new(hour, minute, second, microsecond) do
      DateTime.new(date, time)
    end
  catch {:error, _} = err ->
    err
  end

  def kdl_node_to_interval(%N{children: children}) when is_list(children) do
    {:ok, Enum.map(children, fn
      %N{name: "second"} = n ->
        case kdl_node_to_integer(n) do
          {:ok, value} ->
            {:second, value}

          {:error, _} = err ->
            throw err
        end

      %N{name: "minute"} = n ->
        case kdl_node_to_integer(n) do
          {:ok, value} ->
            {:minute, value}

          {:error, _} = err ->
            throw err
        end

      %N{name: "hour"} = n ->
        case kdl_node_to_integer(n) do
          {:ok, value} ->
            {:hour, value}

          {:error, _} = err ->
            throw err
        end

      %N{name: "day"} = n ->
        case kdl_node_to_integer(n) do
          {:ok, value} ->
            {:day, value}

          {:error, _} = err ->
            throw err
        end

      %N{name: "week"} = n ->
        case kdl_node_to_integer(n) do
          {:ok, value} ->
            {:week, value}

          {:error, _} = err ->
            throw err
        end
    end)}
  catch {:error, _} = err ->
    err
  end
end
