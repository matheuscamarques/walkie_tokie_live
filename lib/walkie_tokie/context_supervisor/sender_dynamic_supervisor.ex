defmodule WalkieTokie.SenderDynamicSupervisor do
  use DynamicSupervisor

  def start_link(_init_arg) do
    DynamicSupervisor.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  @impl true
  def init(:ok) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  def start_sender(args \\ []) do
    node_target = Keyword.get(args, :node_target, :default_node)
    child_spec = %{
      id: node_target,
      start: {WalkieTokie.Sender, :start_link, [args]},
      restart: :transient,
      type: :worker
    }

    DynamicSupervisor.start_child(__MODULE__, child_spec)
  end
end
