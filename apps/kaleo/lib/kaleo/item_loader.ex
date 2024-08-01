defmodule Kaleo.ItemLoader do
  use Loxe.Logger

  alias Kaleo.Item
  alias Kuddle.Node, as: N

  import Kaleo.KuddleUtil

  @type item_load_item :: {:ok, Item.t()} | {:error, term()}

  @spec load_items_from_paths([Path.t()]) ::
    {Path.t(), {:ok, [item_load_item()]} | {:error, term()}}
  def load_items_from_paths(item_paths) when is_list(item_paths) do
    Enum.map(item_paths, fn {item_path, opts} ->
      {item_path, load_items_from_path(item_path, opts)}
    end)
  end

  @spec load_items_from_path(Path.t(), Keyword.t()) :: {:ok, [item_load_item()]} | {:error, term()}
  def load_items_from_path(path, opts) do
    Loxe.Logger.info "loading item from path", path: path
    with \
      {:ok, blob} <- File.read(path),
      {:ok, document, []} <- Kuddle.decode(blob)
    do
      {:ok, load_items_from_kdl(document, opts)}
    else
      {:error, reason} = err ->
        Loxe.Logger.error "could not load item", reason: inspect(reason)
        err
    end
  end

  @spec load_items_from_kdl(Kuddle.document(), Keyword.t()) :: [item_load_item()]
  def load_items_from_kdl(document, _opts) when is_list(document) do
    Enum.reduce(document, [], fn
      %N{name: "item", children: nil}, acc ->
        Loxe.Logger.warning "item node found, but it has no children"
        acc

      %N{name: "item"} = n, acc ->
        [kdl_node_to_item(n) | acc]

      %N{name: name}, acc ->
        Loxe.Logger.warning "unexpected kdl node (expected \"item\")", name: name
        acc
    end)
  end

  def kdl_node_to_item(%N{children: children}) when is_list(children) do
    item =
      Enum.reduce(children, %Item{}, fn
        %N{name: "id"} = n, %Item{} = subject ->
          {:ok, id} = kdl_node_to_id(n)
          %{subject | id: id}

        %N{name: "name"} = n, %Item{} = subject ->
          {:ok, name} = kdl_node_to_string(n)
          %{subject | name: name}

        %N{name: "notes"} = n, %Item{} = subject ->
          {:ok, notes} = kdl_node_to_string(n)
          %{subject | notes: notes}

        %N{name: "starts_at"} = n, %Item{} = subject ->
          {:ok, starts_at} = kdl_node_to_datetime(n)
          %{subject | starts_at: starts_at}

        %N{name: "ends_at"} = n, %Item{} = subject ->
          {:ok, ends_at} = kdl_node_to_datetime(n)
          %{subject | ends_at: ends_at}

        %N{name: "trigger"} = n, %Item{} = subject ->
          {:ok, trigger} = kdl_node_to_item_trigger(n)
          %{subject | trigger: trigger}
      end)

    {:ok, item}
  end

  def kdl_node_to_item_trigger(%N{children: children}) when is_list(children) do
    subject = %Item.Trigger{}
    subject =
      Enum.reduce(children, subject, fn
        %N{name: "every"} = n, %Item.Trigger{} = subject ->
          {:ok, every} = kdl_node_to_interval(n)
          %{subject | every: every}

        %N{name: "expires"} = n, %Item.Trigger{} = subject ->
          {:ok, expires} = kdl_node_to_item_trigger_expiration(n)
          %{subject | expires: expires}
      end)

    {:ok, subject}
  end

  def kdl_node_to_item_trigger_expiration(%N{children: children}) when is_list(children) do
    subject = %Item.Trigger.Expiration{}
    subject =
      Enum.reduce(children, subject, fn
        %N{name: "after"} = n, %Item.Trigger.Expiration{} = subject ->
          {:ok, interval} = kdl_node_to_interval(n)
          %{subject | after: interval}
      end)

    {:ok, subject}
  end
end
