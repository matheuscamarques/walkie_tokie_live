defmodule WalkieTokie.MasterConnector do
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
    master_node = Application.get_env(:walkie_tokie, :master_node)

    case Node.connect(master_node) do
      true ->
        Logger.info("Conectado ao master node: #{inspect(master_node)}")
        {:noreply, state}

      false ->
        Logger.warning(
          "Falha ao conectar ao master node: #{inspect(master_node)}. Tentando novamente em #{@reconnect_interval}ms."
        )

        Process.send_after(self(), :connect, @reconnect_interval)
        {:noreply, state}

      :ignored ->
        Logger.error(
          "Node.connect ignorado porque estamos no mesmo node? #{inspect(master_node)}"
        )

        {:noreply, state}
    end
  end
end
