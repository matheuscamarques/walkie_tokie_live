defmodule WalkieTokie.SenderDynamicSupervisor do
  @moduledoc """
  DynamicSupervisor responsible for starting senders for each node in the cluster.
  It will start a sender for each node in the cluster that is not already started.
  It will also log the connection status.
  """
  use DynamicSupervisor

  def start_link(_init_arg) do
    DynamicSupervisor.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  @impl true
  def init(:ok) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  def start_sender(args \\ []) do
    node_target = Keyword.get(args, :node_target)

    if not is_nil(node_target) do
      child_spec = %{
        id: node_target,
        start: {WalkieTokie.Sender, :start_link, [args]},
        restart: :transient,
        type: :worker
      }

      case DynamicSupervisor.start_child(__MODULE__, child_spec) do
        {:ok, _pid} -> :ok
        {:error, {:already_started, _pid}} -> :ok
        error -> error
      end
    end
  end
end
