defmodule Kaleo.ItemProcessor do
  defmodule State do
    defstruct []
  end

  use GenServer

  alias Kaleo.Item

  def process_ready_event(ready_at, %Item{} = subject, timeout \\ 15_000) do
    GenServer.call(__MODULE__, {:process_ready_event, ready_at, subject}, timeout)
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
  def handle_call({:process_ready_event, ready_at, %Item{} = subject}, _from, %State{} = state) do
    IO.inspect {:process_ready_event, ready_at, subject}

    {_, 0} = System.cmd("notify-send", [subject.name, subject.notes])
    ref = make_ref()
    {:reply, {:ok, ref}, state}
  end
end
