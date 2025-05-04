defmodule WalkieTokie.Rpc do
  @moduledoc """
  Wrapper around :erpc to provide safer and more convenient remote procedure calls.
  """

  @default_timeout 5_000

  @doc """
  Makes a synchronous remote call to a given node.

  ## Examples

      iex> WalkieTokie.Rpc.call(:remote@host, fn -> MyMod.handle_chunk(data) end)
      {:ok, result}

  Returns `{:ok, result}` or `{:error, reason}`.
  """
  def call(node, fun, timeout \\ @default_timeout) ,do: :erpc.call(node, fun, timeout)

  def cast(node, fun) , do: :erpc.cast(node, fun)
end
