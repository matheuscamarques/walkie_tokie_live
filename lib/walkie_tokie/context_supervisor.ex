defmodule WalkieTokie.ContextSupervisor do
  use Supervisor

  def start_link(_init_arg) do
    Supervisor.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  @impl true
  def init(:ok) do
    children = [
      # Receiver é um GenServer
      # WalkieTokie.Receiver,

      # SenderDynamicSupervisor é um DynamicSupervisor
      {Registry, keys: :unique, name: WalkieTokie.SenderRegistry},
      {Registry, keys: :unique, name: WalkieTokie.ReceiverRegistry},
      {WalkieTokie.SenderDynamicSupervisor, []},
      {WalkieTokie.ReceiverDynamicSupervisor, []}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
