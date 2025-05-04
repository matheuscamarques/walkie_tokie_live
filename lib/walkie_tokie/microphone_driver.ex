defmodule WalkieTokie.MicrophoneDriver do
  @moduledoc """
  GenServer handling the microphone input and audio streaming.
  This module is responsible for capturing audio from the microphone
  and streaming it to the connected nodes.
  It will also handle the connection status and audio device.
  """
  require Logger
  use GenServer

  @pubsub WalkieTokie.PubSub
  @compiled_audio_topic "audio:stream:"

  def audio_topic do
    @compiled_audio_topic <> to_string(Node.self())
  end

  def start_link(init_args), do: GenServer.start_link(__MODULE__, init_args, name: __MODULE__)

  @type connection_status :: :disconnected | :connected
  @type audio_device :: binary()
  @type accept_transfer :: boolean()
  @type chunk_data :: binary()
  @type is_talking :: boolean()
  @type audio_port :: Port | nil
  @type stop_requested :: boolean()

  def init(args) do
    audio_device = Keyword.get(args, :audio_device, "default")

    state = {
      {:connection_status, :disconnected},
      {:audio_device, audio_device},
      {:accept_transfer, false},
      {:chunk_data, <<>>},
      {:is_talking, false},
      {:audio_port, nil},
      # Novo estado para rastrear a solicitação de parada
      {:stop_requested, false}
    }

    Process.send_after(self(), :try_connection, 1000)
    {:ok, state}
  end

  def start_talking(), do: GenServer.cast(__MODULE__, :start_talking)
  def stop_talking(), do: GenServer.cast(__MODULE__, :stop_talking)

  def handle_cast(:start_talking, state) do
    send(self(), :start_talking)
    # Reseta a flag de parada
    {:noreply, state |> set_dict(:stop_requested, false)}
  end

  def handle_cast(:stop_talking, state) do
    {:noreply, set_dict(state, :stop_requested, true)}
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
    updated_state = set_dict(state, :is_talking, true)

    {os, executable_name} =
      case :os.type() do
        {:win32, _} -> {"windows", "sox"}
        {:unix, :darwin} -> {"mac", "sox"}
        {:unix, _} -> {"linux", "sox"}
      end

    {path, args} =
      case os do
        "windows" ->
          {
            System.find_executable(executable_name),
            [
              "--buffer", "3200",
              "-t", "waveaudio",
              "-d",
              "-b", "16",
              "-r", "16000",
              "-c", "1",
              "-e", "signed-integer",
              "-t", "raw",
              "-"
            ]
          }

        "mac" ->
          {
            System.find_executable(executable_name),
            [
              "--buffer", "3200",
              "-d",
              "-b", "16",
              "-r", "16000",
              "-c", "1",
              "-e", "signed-integer",
              "-t", "raw"
            ]
          }

        _ ->
          {
            System.find_executable(executable_name),
            [
              "--buffer", "3200",
              "-d",
              "-b", "16",
              "-r", "16000",
              "-c", "1",
              "-e", "signed-integer",
              "-t", "raw",
              "-"
            ]
          }

      end


    # Sanity check: Se path for nil, falha com log
    if path == nil do
      Logger.error(
        "Executável de captura de áudio não encontrado! Por favor, instale o #{executable_name} para usar este aplicativo."
      )

      {:noreply, set_dict(updated_state, :audio_port, nil)}
    else
      port = Port.open({:spawn_executable, path}, [:binary, :stream, args: args])
      {:noreply, set_dict(updated_state, :audio_port, port)}
    end
  end

  def handle_info({port, {:data, raw_audio}}, state) do
    if port == dict(state, :audio_port) and dict(state, :is_talking) do
      Phoenix.PubSub.broadcast(@pubsub, audio_topic(), {:audio_chunk, raw_audio})

      # Se a parada foi solicitada, inicia o processo de finalização
      if dict(state, :stop_requested) do
        # Envia uma mensagem interna para iniciar o fechamento seguro
        send(self(), :finalize_stop_talking)
        # Marca como não falando mais
        {:noreply, state |> set_dict(:is_talking, false)}
      else
        {:noreply, state}
      end
    else
      {:noreply, state}
    end
  end

  def handle_info(:finalize_stop_talking, state) do
    if port = dict(state, :audio_port) do
      # Process.sleep(10000)
      Port.close(port)
    end

    {:noreply, set_dict(state, :audio_port, nil)}
  end

  def handle_info(:send_audio_chunk, state) do
    if dict(state, :is_talking) and not dict(state, :stop_requested) do
      # Solicita mais dados do Port
      if port = dict(state, :audio_port) do
        send(self(), {:port_command, port, :read, []})
      end
    end

    {:noreply, state}
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

  def handle_info(_msg, state) do
    {:noreply, state}
  end

  @type dict_index ::
          :connection_status
          | :audio_device
          | :accept_transfer
          | :chunk_data
          | :is_talking
          | :audio_port
          | :stop_requested
  @type dict_state :: {
          {:connection_status, connection_status},
          {:audio_device, audio_device},
          {:accept_transfer, accept_transfer},
          {:chunk_data, chunk_data},
          {:is_talking, is_talking},
          {:audio_port, audio_port},
          {:stop_requested, stop_requested}
        }
  @spec dict(dict_state, dict_index) ::
          connection_status
          | audio_device
          | accept_transfer
          | chunk_data
          | is_talking
          | audio_port
          | stop_requested
  def dict(
        {{:connection_status, connection_status}, {:audio_device, audio_device},
         {:accept_transfer, accept_transfer}, {:chunk_data, chunk_data},
         {:is_talking, is_talking}, {:audio_port, audio_port}, {:stop_requested, stop_requested}},
        atom
      ) do
    case atom do
      :connection_status -> connection_status
      :audio_device -> audio_device
      :accept_transfer -> accept_transfer
      :chunk_data -> chunk_data
      :is_talking -> is_talking
      :audio_port -> audio_port
      :stop_requested -> stop_requested
    end
  end

  @spec set_dict(dict_state, dict_index, any()) :: dict_state
  def set_dict(
        {{:connection_status, connection_status}, {:audio_device, audio_device},
         {:accept_transfer, accept_transfer}, {:chunk_data, chunk_data},
         {:is_talking, is_talking}, {:audio_port, audio_port}, {:stop_requested, stop_requested}},
        key,
        new_value
      ) do
    case key do
      :is_talking ->
        {{:connection_status, connection_status}, {:audio_device, audio_device},
         {:accept_transfer, accept_transfer}, {:chunk_data, chunk_data}, {:is_talking, new_value},
         {:audio_port, audio_port}, {:stop_requested, stop_requested}}

      :audio_port ->
        {{:connection_status, connection_status}, {:audio_device, audio_device},
         {:accept_transfer, accept_transfer}, {:chunk_data, chunk_data},
         {:is_talking, is_talking}, {:audio_port, new_value}, {:stop_requested, stop_requested}}

      :stop_requested ->
        {{:connection_status, connection_status}, {:audio_device, audio_device},
         {:accept_transfer, accept_transfer}, {:chunk_data, chunk_data},
         {:is_talking, is_talking}, {:audio_port, audio_port}, {:stop_requested, new_value}}

      _ ->
        {{:connection_status, connection_status}, {:audio_device, audio_device},
         {:accept_transfer, accept_transfer}, {:chunk_data, chunk_data},
         {:is_talking, is_talking}, {:audio_port, audio_port}, {:stop_requested, stop_requested}}
    end
  end
end
