defmodule WalkieTokie.MasterConnector do
  @moduledoc """
  GenServer handling the connection to the master node.
  This module is responsible for connecting to the master node and
  reconnecting if the connection is lost.
  It will try to connect every 10 seconds until it succeeds.
  It will also log the connection status.
  """
  use GenServer
  require Logger

  @reconnect_interval :timer.seconds(10)

  # API
  def start_link(_) do
    GenServer.start_link(__MODULE__, nil, name: __MODULE__)
  end

  # Callbacks
  def init(_) do
    Process.send_after(self(), :connect, 0)
    {:ok, nil}
  end

  def handle_info(:connect, state) do
    master_nodes = get_master_nodes()

    Enum.each(master_nodes, fn master_node ->
      try_connect(master_node, state)
    end)

    {:noreply, state}
  end

  # Private helper functions
  # Retrieves the master nodes from the application environment
  defp get_master_nodes do
    Application.get_env(:walkie_tokie, :master_nodes)
  end

  # Attempts to connect to a given master node
  defp try_connect(master_node, state) do
    case Node.connect(master_node) do
      true ->
        Logger.info("Conectado ao master node: #{inspect(master_node)}")
        {:noreply, state}

      false ->
        Logger.warning(
          "Falha ao conectar ao master node: #{inspect(master_node)}. Tentando novamente em #{@reconnect_interval}ms."
        )

        schedule_reconnect()
        {:noreply, state}

      :ignored ->
        Logger.error(
          "Node.connect ignorado porque estamos no mesmo node? #{inspect(master_node)}"
        )

        {:noreply, state}
    end
  end

  # Schedules a reconnection attempt
  defp schedule_reconnect do
    Process.send_after(self(), :connect, @reconnect_interval)
  end
end
