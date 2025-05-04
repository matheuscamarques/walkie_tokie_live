defmodule WalkieTokie.ConnectSenders do
  @moduledoc """
  GenServer responsible for connecting to all nodes in the cluster.
  It will check every 10 seconds if there are new nodes in the cluster
  and start a sender for each new node, unless the current node or target node is a server.
  It will also log the connection status.
  """
  alias WalkieTokie.ReceiverDynamicSupervisor
  alias WalkieTokie.SenderDynamicSupervisor
  use GenServer
  require Logger

  @topic "cluster_events"

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, nil, name: __MODULE__)
  end

  @impl true
  def init(_) do
    Logger.info("[ConnectSenders] Start ConnectSenders")
    :net_kernel.monitor_nodes(true)
    {:ok, MapSet.new()}
  end

  @impl true
  def handle_info({:nodedown, node}, state) do
    Logger.info("[ConnectSenders] Node DOWN: #{inspect(node)}")

    if is_server_node?(node) do
      Logger.info("[ConnectSenders] Ignoring server node: #{inspect(node)}")
      {:noreply, state}
    else
      SenderDynamicSupervisor.stop_sender(node_target: node)
      ReceiverDynamicSupervisor.stop_receiver(node_target: node)

      Phoenix.PubSub.local_broadcast(WalkieTokie.PubSub, @topic, {:nodedown, node})
      {:noreply, MapSet.delete(state, node)}
    end
  end

  @impl true
  def handle_info({:nodeup, node}, state) do
    Logger.info("[ConnectSenders] Node UP: #{inspect(node)}")

    cond do
      is_server_node?(Node.self()) ->
        Logger.info("[ConnectSenders] This node is a server, not creating sender: #{inspect(Node.self())}")
        {:noreply, state}

      is_server_node?(node) ->
        Logger.info("[ConnectSenders] Ignoring server node: #{inspect(node)}")
        {:noreply, state}

      MapSet.member?(state, node) ->
        Logger.info("[ConnectSenders] Node already started: #{inspect(node)}")
        {:noreply, state}

      true ->
        Logger.info("[ConnectSenders] Starting sender for node: #{inspect(node)}")
        Phoenix.PubSub.broadcast(WalkieTokie.PubSub, @topic, {:nodeup, node})
        ReceiverDynamicSupervisor.start_receiver(node_target: node)
        SenderDynamicSupervisor.start_sender(node_target: node)
        {:noreply, MapSet.put(state, node)}
    end
  end

  defp is_server_node?(node) do
    String.contains?(Atom.to_string(node), "server")
  end
end
