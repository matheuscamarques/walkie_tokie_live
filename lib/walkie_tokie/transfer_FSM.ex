defmodule WalkieTokie.Transfer_FSM do
  @moduledoc """
  Finite State Machine used for controlling audio transfer lifecycle.
  """

  @type transfer_state ::
          :try_connection
          | :try_transfer_request
          | :start_chunk_file
          | :start_transfer
          | :transfer_chunk
          | :completed
          | :start_exit
          | :exit

  @type transition_target :: {transfer_state()}
  @type transition :: {transfer_state(), transition_target()}
  @type finit_state_machine ::
          {transition(), transition(), transition(), transition(), transition(), transition(),
           transition(), transition()}

  @type state_machine ::
          finit_state_machine
          | {
              {:try_connection, {:try_transfer_request}},
              {:try_transfer_request, {:start_chunk_file}},
              {:start_chunk_file, {:start_transfer}},
              {:start_transfer, {:start_transfer}},
              {:transfer_chunk, {:completed}},
              {:completed, {:start_exit}},
              {:start_exit, {:exit}},
              {:exit, {}}
            }

  @virtual_state_machine {
    {:try_connection, {:try_transfer_request}},
    {:try_transfer_request, {:start_chunk_file}},
    {:start_chunk_file, {:start_transfer}},
    {:start_transfer, {:start_transfer}},
    {:transfer_chunk, {:completed}},
    {:completed, {:start_exit}},
    {:start_exit, {:exit}},
    {:exit, {}}
  }

  @spec get_next_state(transfer_state) :: transfer_state() | :exit | {:error, String.t()}
  def get_next_state(transfer_state) do
    case transfer_state do
      :try_connection -> elem(@virtual_state_machine, 0) |> next_state()
      :try_transfer_request -> elem(@virtual_state_machine, 1) |> next_state()
      :start_chunk_file -> elem(@virtual_state_machine, 2) |> next_state()
      :start_transfer -> elem(@virtual_state_machine, 3) |> next_state()
      :transfer_chunk -> elem(@virtual_state_machine, 4) |> next_state()
      :completed -> elem(@virtual_state_machine, 5) |> next_state()
      :start_exit -> elem(@virtual_state_machine, 6) |> next_state()
      :exit -> :exit
      invalid_state -> {:error, "Estado inválido: #{invalid_state}"}
    end
  end

  @spec next_state({transfer_state, {transfer_state}}) :: transfer_state
  defp next_state({_current_state, {next_state}}), do: next_state

  def map_state(state) do
    case state do
      :try_connection -> 0
      :try_transfer_request -> 1
      :start_chunk_file -> 2
      :start_transfer -> 3
      :transfer_chunk -> 4
      :completed -> 5
      :start_exit -> 6
      :exit -> 7
    end
  end
end
