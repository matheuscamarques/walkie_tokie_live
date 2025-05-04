defmodule WalkieTokie.SenderDynamicSupervisor do
  @moduledoc """
  DynamicSupervisor responsible for starting senders for each node in the cluster.
  It will start a sender for each node in the cluster that is not already started.
  It will also log the connection status.
  """
  use DynamicSupervisor
  require Logger

  def start_link(_init_arg) do
    DynamicSupervisor.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  @impl true
  def init(:ok) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  @doc """
  Starts a sender for the given node target.
  If the sender is already started, it will not start a new one.
  """
  @spec start_sender(Keyword.t()) :: :ok | {:error, term()}
  def start_sender(args) do
    node_target = Keyword.get(args, :node_target)

    if not is_nil(node_target) do
      child_spec = %{
        id: node_target,
        start: {WalkieTokie.Sender, :start_link, [args]},
        restart: :transient,
        type: :worker
      }

      case DynamicSupervisor.start_child(__MODULE__, child_spec) do
        {:ok, pid} ->
          Logger.info("[SenderDynamicSupervisor] Starting sender for node: #{inspect(node_target)}")
          {:ok, pid}
        {:error, {:already_started, pid}} ->
          Logger.info("[SenderDynamicSupervisor] Sender already started for node: #{inspect(node_target)}")
          {:ok, pid}
        error ->
          Logger.error("""
          [SenderDynamicSupervisor] Error starting sender for node: #{inspect(node_target)}
          Reason: #{inspect(error)}
          """)
          error
      end
    end
  end

  @doc """
  Stops the sender for the given node target.
  If the sender is not found, it will return an error.
  """
  @spec stop_sender(Keyword.t()) :: :ok | {:error, term()}
  def stop_sender(args) do
    node_target = Keyword.get(args, :node_target)

    case where_is_sender(node_target) do
      {:ok, pid} ->
        Logger.info("[SenderDynamicSupervisor] Stopping sender for node: #{inspect(node_target)}")
        GenServer.stop(pid, :normal)

      :error ->
        Logger.error(
          "[SenderDynamicSupervisor] Sender not found for node: #{inspect(node_target)}"
        )

        {:error, :not_found}
    end
  end

  # Returns the PID of the sender for the given node target.
  # If the sender is not found, it will return an error.
  @spec where_is_sender(atom()) :: {:ok, pid()} | :error
  defp where_is_sender(node_target) do
    case Registry.lookup(WalkieTokie.SenderRegistry, node_target) do
      [{pid, _}] -> {:ok, pid}
      [] -> :error
    end
  end

  # defp list_senders do
  #   Registry.select(WalkieTokie.SenderRegistry, [{{:"$1", :"$2", :_}, [], [{{:"$1", :"$2"}}]}])
  # end
end
