defmodule WalkieTokie.ConnectSenders do
  @moduledoc """
  GenServer responsible for connecting to all nodes in the cluster.
  It will check every 10 seconds if there are new nodes in the cluster
  and start a sender for each new node.
  It will also log the connection status.
  """
  alias WalkieTokie.SenderDynamicSupervisor
  use GenServer
  require Logger

  @check_interval :timer.seconds(10)

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, nil, name: __MODULE__)
  end

  @impl true
  def init(_) do
    Logger.info("[ConnectSenders] Start ConectSenders")
    Process.send_after(self(), :check_nodes, 0)
    {:ok, MapSet.new()}
  end

  @impl true
  def handle_info(:check_nodes, already_started) do
    current_nodes =
      Node.list()
      |> Enum.reject(fn node -> String.contains?(Atom.to_string(node), "server") end)

    new_nodes =
      Enum.reject(current_nodes, fn node -> MapSet.member?(already_started, node) end)

    Enum.each(new_nodes, fn node ->
      Logger.info("[ConnectSenders] Starting sender for node: #{inspect(node)}")
      SenderDynamicSupervisor.start_sender(node_target: node)
    end)

    Process.send_after(self(), :check_nodes, @check_interval)
    {:noreply, MapSet.union(already_started, MapSet.new(new_nodes))}
  end
end
