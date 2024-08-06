defmodule Kaleo.ItemProcessorHost do
  defmodule State do
    defstruct [
      events: nil,
    ]

    @type t :: %__MODULE__{
      events: :ets.table(),
    }
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
    state = %State{
      events: :ets.new(:events, [:set, :private])
    }
    {:ok, state}
  end

  @impl true
  def handle_continue({:handle_event, ref}, %State{} = state) do
    case :ets.take(state.events, ref) do
      [] ->
        :ok

      [{^ref, {ready_at, %Item{} = subject}}] ->
        IO.inspect {:process_ready_event, ready_at, subject}
        {_, 0} = System.cmd("notify-send", [subject.name, subject.notes])
        :ok
    end

    {:noreply, state}
  end

  @impl true
  def handle_call({:process_ready_event, ready_at, %Item{} = subject}, _from, %State{} = state) do
    ref = make_ref()

    true = :ets.insert(state.events, {ref, {ready_at, subject}})

    {:reply, {:ok, ref}, state, {:continue, {:handle_event, ref}}}
  end
end
