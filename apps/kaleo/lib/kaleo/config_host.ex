defmodule Kaleo.ConfigHost do
  defmodule State do
    defstruct [
      config_path: nil,
      last_stat: nil,
      config: [],
      config_watchers: nil,
    ]

    @type t :: %__MODULE__{
      config_path: Path.t(),
      last_stat: File.Stat.t(),
      config: any(),
      config_watchers: :ets.table(),
    }
  end

  use Loxe.Logger
  use GenServer

  alias Kaleo.Config

  import Kaleo.ConfigUtil

  def reload_config(timeout \\ 15_000) do
    GenServer.call(__MODULE__, :reload_config, timeout)
  end

  def watch_config do
    watch_config(self())
  end

  def watch_config(pid, timeout \\ 15_000) do
    GenServer.call(__MODULE__, {:watch_config, pid}, timeout)
  end

  def get_config(timeout \\ 15_000) do
    GenServer.call(__MODULE__, :get_config, timeout)
  end

  def start_link(_) do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  @impl true
  def init(:ok) do
    Loxe.Logger.metadata worker: :config_host

    config_path = Config.runtime_config_path()

    state = %State{
      config_path: config_path,
      config_watchers: :ets.new(:config_watchers, [:set, :private]),
    }

    state = set_check_config_timer(state)

    {:ok, state, {:continue, :load_config}}
  end

  @impl true
  def terminate(_reason, %State{} = state) do
    :ets.delete(state.config_watchers)
    :ok
  end

  @impl true
  def handle_continue(:load_config, %State{} = state) do
    state = %{state | config: []}

    if state.config_path do
      case File.stat(state.config_path) do
        {:ok, %File.Stat{} = stat} ->
          state = %{state | last_stat: stat}

          Loxe.Logger.info "loading config file", filename: state.config_path
          case Kuddle.Config.load_config_file(state.config_path) do
            {:ok, config} ->
              state = %{state | config: config}

              {:noreply, state, {:continue, :alert_config_changed}}
          end

        {:error, reason} ->
          state = %{state | last_stat: {:error, reason}}
          Loxe.Logger.error "config file unavailable",
            filename: state.config_path, reason: reason

          {:noreply, state, {:continue, :alert_config_changed}}
      end
    else
      {:noreply, state}
    end
  end

  @impl true
  def handle_continue(:alert_config_changed, %State{} = state) do
    state = alert_config_changed(state)

    {:noreply, state}
  end

  @impl true
  def handle_call(:get_config, _from, %State{} = state) do
    {:reply, state.config, state}
  end

  @impl true
  def handle_call(:reload_config, _from, %State{} = state) do
    {:reply, :ok, state, {:continue, :load_config}}
  end

  @impl true
  def handle_call({:watch_config, pid}, _from, %State{} = state) do
    case :ets.take(state.config_watchers, pid) do
      [] ->
        :ok

      [{^pid, ref}] ->
        Process.demonitor(ref)
    end

    ref = Process.monitor(pid)
    true = :ets.insert(state.config_watchers, {pid, ref})

    send(pid, config_changed_event(path: state.config_path, config: state.config))

    {:reply, self(), state}
  end

  @impl true
  def handle_info({:DOWN, _ref, :process, pid}, %State{} = state) do
    case :ets.take(state.config_watchers, pid) do
      [] ->
        :ok

      [{^pid, ref}] ->
        Process.demonitor(ref)
    end

    {:noreply, state}
  end

  @impl true
  def handle_info(:check_config, %State{} = state) do
    Loxe.Logger.debug "checking config"
    state = set_check_config_timer(state)

    case File.stat(state.config_path) do
      {:ok, %File.Stat{} = stat} ->
        case compare_file_stats(state.last_stat, stat) do
          :changed ->
            Loxe.Logger.info "config has changed"
            {:noreply, state, {:continue, :load_config}}

          :unchanged ->
            Loxe.Logger.debug "config is unchanged"
            {:noreply, state}
        end

      {:error, reason} ->
        Loxe.Logger.warning "config check failed", reason: reason
        {:noreply, state}
    end
  end

  defp alert_config_changed(%State{} = state) do
    key = :ets.first(state.config_watchers)

    do_alert_config_changed(key, state.config_watchers, state)
  end

  def do_alert_config_changed(:'$end_of_table', _config_watchers, %State{} = state) do
    state
  end

  def do_alert_config_changed(key, config_watchers, %State{} = state) do
    case :ets.lookup(config_watchers, key) do
      [] ->
        :ok

      [{^key, _ref}] ->
        send(key, config_changed_event(path: state.config_path, config: state.config))
    end

    do_alert_config_changed(:ets.next(config_watchers, key), config_watchers, %State{} = state)
  end

  defp compare_file_stats(nil, %File.Stat{} = _stat) do
    :changed
  end

  defp compare_file_stats(atom, %File.Stat{} = _stat) when is_atom(atom) do
    :changed
  end

  defp compare_file_stats(%File.Stat{} = stat_a, %File.Stat{} = stat_b) do
    if stat_a.mtime != stat_b.mtime do
      throw :changed
    end

    if stat_a.inode != stat_b.inode do
      throw :changed
    end

    :unchanged
  catch :changed = res ->
    res
  end

  defp set_check_config_timer(%State{} = state) do
    Process.send_after(self(), :check_config, :timer.minutes(1))
    state
  end
end
