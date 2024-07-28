defmodule Kaleo.EventLoader do
  use Loxe.Logger

  alias Kaleo.Event
  alias Kuddle.Node, as: N

  import Kaleo.KuddleUtil

  @type event_load_item :: {:ok, Event.t()} | {:error, term()}

  @spec load_events_from_paths([Path.t()]) ::
    {Path.t(), {:ok, [event_load_item()]} | {:error, term()}}
  def load_events_from_paths(event_paths) when is_list(event_paths) do
    Enum.map(event_paths, fn {event_path, opts} ->
      {event_path, load_events_from_path(event_path, opts)}
    end)
  end

  @spec load_events_from_path(Path.t(), Keyword.t()) :: {:ok, [event_load_item()]} | {:error, term()}
  def load_events_from_path(path, opts) do
    Loxe.Logger.info "loading event from path", path: path
    with \
      {:ok, blob} <- File.read(path),
      {:ok, document, []} <- Kuddle.decode(blob)
    do
      {:ok, load_events_from_kdl(document, opts)}
    else
      {:error, reason} = err ->
        Loxe.Logger.error "could not load event", reason: inspect(reason)
        err
    end
  end

  @spec load_events_from_kdl(Kuddle.document(), Keyword.t()) :: [event_load_item()]
  def load_events_from_kdl(document, _opts) when is_list(document) do
    Enum.reduce(document, [], fn
      %N{name: "event", children: nil}, acc ->
        Loxe.Logger.warning "event node found, but it has no children"
        acc

      %N{name: "event"} = n, acc ->
        [kdl_node_to_event(n) | acc]

      %N{name: name}, acc ->
        Loxe.Logger.warning "unexpected kdl node (expected \"event\")", name: name
        acc
    end)
  end

  def kdl_node_to_event(%N{children: children}) when is_list(children) do
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

        %N{name: "trigger"} = n, %Event{} = subject ->
          {:ok, trigger} = kdl_node_to_event_trigger(n)
          %{subject | trigger: trigger}
      end)

    {:ok, event}
  end

  def kdl_node_to_event_trigger(%N{children: children}) when is_list(children) do
    subject = %Event.Trigger{}
    subject =
      Enum.reduce(children, subject, fn
        %N{name: "every"} = n, %Event.Trigger{} = subject ->
          {:ok, every} = kdl_node_to_interval(n)
          %{subject | every: every}

        %N{name: "expires"} = n, %Event.Trigger{} = subject ->
          {:ok, expires} = kdl_node_to_event_trigger_expiration(n)
          %{subject | expires: expires}
      end)

    {:ok, subject}
  end

  def kdl_node_to_event_trigger_expiration(%N{children: children}) when is_list(children) do
    subject = %Event.Trigger.Expiration{}
    subject =
      Enum.reduce(children, subject, fn
        %N{name: "after"} = n, %Event.Trigger.Expiration{} = subject ->
          {:ok, interval} = kdl_node_to_interval(n)
          %{subject | after: interval}
      end)

    {:ok, subject}
  end
end
