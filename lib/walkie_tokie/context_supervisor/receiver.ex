defmodule WalkieTokie.Receiver do
  alias Phoenix.PubSub
  require Logger
  use GenServer

  @play_path System.find_executable("play")
  @play_args [
    "-t", "raw",
    "-e", "signed",
    "-b", "16",
    "-c", "1",
    "-r", "16000",
    "-",
    "trim", "0"
  ]

  ## Public API

  @spec start_link(any()) :: :ignore | {:error, any()} | {:ok, pid()}
  def start_link(_opts) do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  def send_chunk(from_node_name, chunk) when is_binary(chunk) do
    GenServer.cast(__MODULE__, {:audio_chunk, from_node_name, chunk})
  end

  def stop do
    GenServer.cast(__MODULE__, :stop)
  end

  ## GenServer Callbacks

  @impl true
  def init(:ok) do
    port =
      Port.open({:spawn_executable, @play_path}, [
        :binary,
        :exit_status,
        args: @play_args
      ])

    IO.puts("[Receiver] Porta para aplay aberta.")
    {:ok, port}
  end

  @impl true
  def handle_cast({:audio_chunk, from_node_name, chunk}, port) do
    IO.inspect("reproduzindo chunk")

    PubSub.broadcast(
      WalkieTokie.PubSub,
      "node_speaking",
      {:node_speaking, from_node_name}
    )

    Port.command(port, chunk)
    {:noreply, port}
  end

  @impl true
  def handle_cast(:stop, port) do
    IO.puts("[Receiver] Fechando porta...")
    Port.close(port)
    {:stop, :normal, port}
  end
end
