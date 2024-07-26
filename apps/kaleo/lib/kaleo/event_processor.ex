defmodule Kaleo.EventProcessor do
  defmodule State do
    defstruct []
  end

  use GenServer

  alias Kaleo.Event

  def process_ready_event(ready_at, %Event{} = event, timeout \\ 15_000) do
    GenServer.call(__MODULE__, {:process_ready_event, ready_at, event}, timeout)
  end

  def start_link(_) do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  @impl true
  def init(:ok) do
    state = %State{}
    {:ok, state}
  end

  @impl true
  def handle_call({:process_ready_event, ready_at, %Event{} = event}, _from, %State{} = state) do
    IO.inspect {:process_ready_event, ready_at, event}

    {_, 0} = System.cmd("notify-send", [event.name, event.notes])
    ref = make_ref()
    {:reply, {:ok, ref}, state}
  end
end
