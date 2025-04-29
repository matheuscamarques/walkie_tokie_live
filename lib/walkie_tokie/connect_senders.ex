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

  @topic "cluster_events"

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, nil, name: __MODULE__)
  end

  @impl true
  def init(_) do
    Logger.info("[ConnectSenders] Start ConectSenders")
    :net_kernel.monitor_nodes(true)
    {:ok, MapSet.new()}
  end

  @impl true
  def handle_info({:nodedown, node}, state) do
    Logger.info("[ConnectSenders] Node DOWN: #{inspect(node)}")
    Phoenix.PubSub.broadcast(WalkieTokie.PubSub, @topic, {:nodedown, node})
    {:noreply, MapSet.delete(state, node)}
  end

  @impl true
  def handle_info({:nodeup, node}, state) do
    Logger.info("[ConnectSenders] Node UP: #{inspect(node)}")

    if String.contains?(Atom.to_string(node), "server") do
      Logger.info("[ConnectSenders] Ignoring server node: #{inspect(node)}")
      {:noreply, state}
    else
      if MapSet.member?(state, node) do
        Logger.info("[ConnectSenders] Node already started: #{inspect(node)}")
        {:noreply, state}
      else
        Logger.info("[ConnectSenders] Starting sender for node: #{inspect(node)}")
        Phoenix.PubSub.broadcast(WalkieTokie.PubSub, @topic, {:nodeup, node})
        SenderDynamicSupervisor.start_sender(node_target: node)
        {:noreply, MapSet.put(state, node)}
      end
    end
  end
end
