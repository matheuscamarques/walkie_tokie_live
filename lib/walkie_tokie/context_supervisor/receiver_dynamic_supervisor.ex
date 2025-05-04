defmodule WalkieTokie.ReceiverDynamicSupervisor do
  @moduledoc """
  DynamicSupervisor responsible for starting receivers for each node in the cluster.
  It will start a receiver for each node in the cluster that is not already started.
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
  Starts a receiver for the given node target.
  If the receiver is already started, it will not start a new one.
  """
  @spec start_receiver(Keyword.t()) :: {:ok, pid()} | {:error, term()}
  def start_receiver(args) do
    node_target = Keyword.get(args, :node_parent)

    if not is_nil(node_target) do
      child_spec = %{
        id: node_target,
        start: {WalkieTokie.Receiver, :start_link, [args]},
        restart: :transient,
        type: :worker
      }

      case DynamicSupervisor.start_child(__MODULE__, child_spec) do
        {:ok, pid} -> {:ok, pid}
        {:error, {:already_started, pid}} -> {:ok, pid}
        error -> error
      end
    end
  end

  @doc """
  Stops the receiver for the given node target.
  If the receiver is not found, it will return an error.
  """
  @spec stop_receiver(Keyword.t()) :: :ok | {:error, term()}
  def stop_receiver(args) do
    node_target = Keyword.get(args, :node_target)

    case where_is_receiver(node_target) do
      {:ok, pid} ->
        Logger.info("[ReceiverDynamicSupervisor] Stopping receiver for node: #{inspect(node_target)}")
        GenServer.stop(pid, :normal)

      :error ->
        Logger.error(
          "[ReceiverDynamicSupervisor] Receiver not found for node: #{inspect(node_target)}"
        )

        {:error, :not_found}
    end
  end

  # Returns the PID of the receiver for the given node target.
  # If the receiver is not found, it will return an error.
  @spec where_is_receiver(atom()) :: {:ok, pid()} | :error
  defp where_is_receiver(node_target) do
    case Registry.lookup(WalkieTokie.ReceiverRegistry, node_target) do
      [{pid, _}] -> {:ok, pid}
      [] -> :error
    end
  end

  # defp list_receivers do
  #   Registry.select(WalkieTokie.ReceiverRegistry, [{{:"$1", :"$2", :_}, [], [{{:"$1", :"$2"}}]}])
  # end
end
