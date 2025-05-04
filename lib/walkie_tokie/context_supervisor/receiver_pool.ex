defmodule WalkieTokie.ContextSupervisor.ReceiverPool do

  def start_receiver(node_parent) do
    case WalkieTokie.ReceiverDynamicSupervisor.start_receiver(node_parent) do
      {:ok, pid} ->
        {:ok, pid}

      {:error, {:already_started, pid}} ->
        {:ok, pid}

      error ->
        error
    end
  end
end
