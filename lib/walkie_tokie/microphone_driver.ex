defmodule WalkieTokie.MicrophoneDriver do
  require Logger
  use GenServer

  @pubsub WalkieTokie.PubSub
  @compiled_audio_topic "audio:stream:"

  def audio_topic do
    @compiled_audio_topic <> to_string(Node.self())
  end

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

  def start_link(init_args), do: GenServer.start_link(__MODULE__, init_args, name: __MODULE__)

  @type connection_status :: :disconnected | :connected
  @type audio_device :: binary()
  @type accept_transfer :: binary()
  @type chunk_data :: binary()
  # Novo flag para indicar se está falando
  @type is_talking :: boolean()
  @type audio_port :: Port.t() | nil
  def init(args) do
    IO.inspect(args)
    audio_device = Keyword.get(args, :audio_device, "default")

    state = {
      {:connection_status, :disconnected},
      {:audio_device, audio_device},
      {:accept_transfer, false},
      {:chunk_data, <<>>},
      # Inicializa o flag de falando como falso
      {:is_talking, false},
      # Adiciona um campo para o Port
      {:audio_port, nil}
    }

    Process.send_after(self(), :try_connection, 1000)
    {:ok, state}
  end

  def start_talking() do
    Logger.info("Microfone Driver: Starting to talk...")
    GenServer.cast(__MODULE__, :start_talking)
  end

  def stop_talking() do
    GenServer.cast(__MODULE__, :stop_talking)
  end

  def handle_cast(:start_talking, state) do
    Logger.info("CAST Microfone Driver: Starting to talk...")
    send(self(), :start_talking)
    {:noreply, state}
  end

  def handle_cast(:stop_talking, state) do
    send(self(), :stop_talking)
    {:noreply, state}
  end

  @spec handle_info(:try_connection, dict_state) :: {:noreply, dict_state}
  def handle_info(:try_connection, state) do
    # Lógica de conexão com outro nó removida.
    # Se alguma outra lógica era executada aqui, mantenha-a.
    {:noreply, state}
  end

  @spec handle_info({:accept_transfer, boolean()}, dict_state) :: {:noreply, dict_state}
  def handle_info({:accept_transfer, _}, state) do
    # Lógica para lidar com a aceitação ou rejeição da transferência (opcional)
    {:noreply, state}
  end

  @spec handle_info(:start_talking, dict_state) :: {:noreply, dict_state}
  def handle_info(:start_talking, state) do
    Logger.info("Iniciando gravação de áudio...")

    updated_state = set_dict(state, :is_talking, true)

    {path, args} =
      case System.get_env("OS") do
        "mac" ->
          {
            System.find_executable("sox"),
            [
              "-d",
              "-b",
              "16",
              "-r",
              "16000",
              "-c",
              "1",
              "-e",
              "signed-integer",
              "-t",
              "raw",
              "-"
            ]
          }

        _linux_or_other ->
          {
            System.find_executable("arecord"),
            [
              "-r",
              "16000",
              "-f",
              "S16_LE",
              "-t",
              "raw",
              "-D",
              "pulse",
              "-c",
              "1"
            ]
          }
      end

    # Sanity check: Se path for nil, falha com log
    if path == nil do
      Logger.error("Executável de captura de áudio não encontrado!")
      {:noreply, set_dict(updated_state, :audio_port, nil)}
    else
      port = Port.open({:spawn_executable, path}, [:binary, :stream, args: args])
      {:noreply, set_dict(updated_state, :audio_port, port)}
    end
  end

  @spec handle_info(:stop_talking, dict_state) :: {:noreply, dict_state}
  def handle_info(:stop_talking, state) do
    updated_state = set_dict(state, :is_talking, false)
    # Fecha o Port quando para de falar
    if port = dict(updated_state, :audio_port) do
      Port.close(port)
    end

    {:noreply, set_dict(updated_state, :audio_port, nil)}
  end

  def handle_info({port, {:data, raw_audio}}, state) do
    if dict(state, :is_talking) and port == dict(state, :audio_port) do
      Logger.info("Sending audio chunks:")
      Phoenix.PubSub.broadcast(@pubsub, audio_topic(), {:audio_chunk, raw_audio})
      {:noreply, state}
    else
      {:noreply, state}
    end
  end

  def handle_info(:send_audio_chunk, state) do
    if dict(state, :is_talking) do
      # Solicita mais dados do Port
      if port = dict(state, :audio_port) do
        send(self(), {:port_command, port, :read, []})
      end

      {:noreply, state}
    else
      {:noreply, state}
    end
  end

  def handle_info({:port_command, port, command, args}, state) do
    Port.command(port, command, args)
    {:noreply, state}
  end

  @spec handle_info(:try_transfer_request, dict_state) :: {:noreply, dict_state}
  def handle_info(:try_transfer_request, state) do
    IO.puts("Transfer request recebido.")
    {:noreply, state}
  end

  def handle_info(msg, state) do
    IO.inspect("Mensagem não tratada: #{msg}")
    {:noreply, state}
  end

  @type dict_index ::
          :connection_status
          | :audio_device
          | :accept_transfer
          | :chunk_data
          | :is_talking
          | :audio_port
  @type dict_state :: {
          {:connection_status, connection_status},
          {:audio_device, audio_device},
          {:accept_transfer, accept_transfer},
          {:chunk_data, chunk_data},
          {:is_talking, is_talking},
          {:audio_port, audio_port}
        }
  @spec dict(dict_state, dict_index) ::
          connection_status
          | audio_device
          | accept_transfer
          | chunk_data
          | is_talking
          | audio_port
  def dict(
        {{:connection_status, connection_status}, {:audio_device, audio_device},
         {:accept_transfer, accept_transfer}, {:chunk_data, chunk_data},
         {:is_talking, is_talking}, {:audio_port, audio_port}},
        atom
      ) do
    case atom do
      :connection_status -> connection_status
      :audio_device -> audio_device
      :accept_transfer -> accept_transfer
      :chunk_data -> chunk_data
      :is_talking -> is_talking
      :audio_port -> audio_port
    end
  end

  @spec set_dict(dict_state, :is_talking | :audio_port, any()) :: dict_state
  def set_dict(
        {{:connection_status, connection_status}, {:audio_device, audio_device},
         {:accept_transfer, accept_transfer}, {:chunk_data, chunk_data},
         {:is_talking, is_talking}, {:audio_port, audio_port}},
        key,
        new_value
      ) do
    case key do
      :is_talking ->
        {{:connection_status, connection_status}, {:audio_device, audio_device},
         {:accept_transfer, accept_transfer}, {:chunk_data, chunk_data}, {:is_talking, new_value},
         {:audio_port, audio_port}}

      :audio_port ->
        {{:connection_status, connection_status}, {:audio_device, audio_device},
         {:accept_transfer, accept_transfer}, {:chunk_data, chunk_data},
         {:is_talking, is_talking}, {:audio_port, new_value}}

      _ ->
        {{:connection_status, connection_status}, {:audio_device, audio_device},
         {:accept_transfer, accept_transfer}, {:chunk_data, chunk_data},
         {:is_talking, is_talking}, {:audio_port, audio_port}}
    end
  end

  def set_dict(state, _key, _new_value) do
    # Retorna o estado original se a chave não for :is_talking ou :audio_port
    state
  end
end
