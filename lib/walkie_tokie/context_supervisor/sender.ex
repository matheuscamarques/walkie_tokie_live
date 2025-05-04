defmodule WalkieTokie.Sender do
  @moduledoc """
  This module is responsible for sending audio data to a remote node.
  It uses a state machine to manage the connection and transfer process.
  """
  require Logger
  use GenServer

  @pubsub WalkieTokie.PubSub
  @compiled_audio_topic "audio:stream:"

  def audio_topic do
    @compiled_audio_topic <> to_string(Node.self())
  end

  def start_link(init_args) do
    node_target = Keyword.fetch!(init_args, :node_target)

    GenServer.start_link(__MODULE__, init_args,
      name: {:via, Registry, {WalkieTokie.SenderRegistry, node_target}}
    )
  end

  # Type definitions

  @type connection_status :: :disconnected | :connected
  @type node_target :: atom()
  @type audio_device :: binary()
  @type accept_transfer :: binary()
  @type chunk_data :: binary()
  # Novo flag para indicar se está falando
  @type is_talking :: boolean()
  @type audio_port :: Port | nil
  @type receiver_pid :: pid()

  @type dict_index ::
  :connection_status
  | :node_target
  | :audio_device
  | :accept_transfer
  | :chunk_data
  | :is_talking
  | :audio_port
  | :receiver_pid

  @type dict_state :: {
    {:connection_status, connection_status},
    {:node_target, node_target},
    {:audio_device, audio_device},
    {:accept_transfer, accept_transfer},
    {:chunk_data, chunk_data},
    {:is_talking, is_talking},
    {:audio_port, audio_port},
    {:receiver_pid, receiver_pid}
  }

  def init(args) do
    node_target = Keyword.get(args, :node_target, :default_node)
    audio_device = Keyword.get(args, :audio_device, "default")

    Phoenix.PubSub.subscribe(@pubsub, audio_topic())

    {:ok, pid} = WalkieTokie.ReceiverDynamicSupervisor.where_is_receiver(node_target)

    state = {
      {:connection_status, :disconnected},
      {:node_target, node_target},
      {:audio_device, audio_device},
      {:accept_transfer, false},
      {:chunk_data, <<>>},
      # Inicializa o flag de falando como falso
      {:is_talking, false},
      # Adiciona um campo para o Port
      {:audio_port, nil},
      {:receiver_pid, pid}
    }

    Process.send_after(self(), :try_connection, 1000)
    {:ok, state}
  end

  def start_talking(pid) do
    GenServer.cast(pid, :start_talking)
  end

  def stop_talking(pid) do
    GenServer.cast(pid, :stop_talking)
  end

  def handle_cast(:start_talking, state) do
    send(self(), :start_talking)
    {:noreply, state}
  end

  def handle_cast(:stop_talking, state) do
    send(self(), :stop_talking)
    {:noreply, state}
  end

  @spec try_connection(dict_state(), true | false | :ignored) :: dict_state()
  def try_connection(state, true) do
    Process.send_after(self(), :try_transfer_request, 1000)
    state
  end

  def try_connection(state, _connection_status) do
    node_target = dict(state, :node_target)
    IO.puts("Failed to connect to node: #{inspect(node_target)}")
    Process.send_after(self(), :try_connection, 1000)
    state
  end

  def handle_info({:audio_chunk, chunk}, state) do
    if dict(state, :is_talking) do
      # node_target = dict(state, :node_target)

      Appsignal.set_gauge("data_upload", byte_size(chunk))
      Appsignal.set_gauge("node_data_upload", byte_size(chunk), %{node: inspect(Node.self())})

      remote_receiver_pid = dict(state, :receiver_pid)
      GenServer.cast(remote_receiver_pid, {:audio_chunk, Node.self(), chunk})
      # :rpc.cast(node_target, WalkieTokie.Receiver, :send_chunk, [remote_receiver_pid, Node.self(), chunk])
    end

    # Atualiza o estado
    {:noreply, set_dict(state, :is_talking, true)}
  end

  @spec handle_info(:try_connection, dict_state()) :: {:noreply, dict_state()}
  def handle_info(:try_connection, state) do
    node_target = dict(state, :node_target)

    connection_status = Node.connect(node_target)
    state = try_connection(state, connection_status)
    {:noreply, state}
  end

  @spec handle_info({:accept_transfer, boolean()}, dict_state()) :: {:noreply, dict_state()}
  def handle_info({:accept_transfer, _}, state) do
    # Lógica para lidar com a aceitação ou rejeição da transferência (opcional)
    {:noreply, state}
  end

  @spec handle_info(:start_talking, dict_state()) :: {:noreply, dict_state()}
  def handle_info(:start_talking, state) do
    updated_state = set_dict(state, :is_talking, true)
    # audio_device = dict(updated_state, :audio_device)
    # path = System.find_executable("arecord")

    # port =
    #   Port.open({:spawn_executable, path}, [
    #     :binary,
    #     :stream,
    #     args: [
    #       "-r", "9000",
    #       "-f", "S16_LE",
    #       "-t", "raw",
    #       "-D", "plughw:1,0",
    #       "-c", "1" # estéreo forçado
    #     ]
    #   ])
    # {:ok, pid} = Sender.start_link([node_target: :"peer1@web-engenharia"])
    # arecord -r 8000 -f S16_LE -c 2 -t raw -D plughw:1,0

    {:noreply, updated_state}
  end

  @spec handle_info(:stop_talking, dict_state()) :: {:noreply, dict_state()}
  def handle_info(:stop_talking, state) do
    updated_state = set_dict(state, :is_talking, false)
    # Fecha o Port quando para de falar
    if port = dict(updated_state, :audio_port) do
      Port.close(port)
    end

    state =
      state
      |> set_dict(:is_talking, false)
      |> set_dict(:audio_port, nil)
      |> set_dict(:chunk_data, <<>>)

    {:noreply, state}
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

  @spec handle_info(:try_transfer_request, dict_state()) :: {:noreply, dict_state()}
  def handle_info(:try_transfer_request, state) do
    IO.puts("Transfer request recebido.")
    {:noreply, state}
  end

  def handle_info(_msg, state) do
    {:noreply, state}
  end

  @spec dict(dict_state(), dict_index()) :: any()
  def dict(
        {
          {:connection_status, connection_status},
          {:node_target, node_target},
          {:audio_device, audio_device},
          {:accept_transfer, accept_transfer},
          {:chunk_data, chunk_data},
          {:is_talking, is_talking},
          {:audio_port, audio_port},
          {:receiver_pid, receiver_pid}
        },
        atom
      ) do
    case atom do
      :connection_status -> connection_status
      :node_target -> node_target
      :audio_device -> audio_device
      :accept_transfer -> accept_transfer
      :chunk_data -> chunk_data
      :is_talking -> is_talking
      :audio_port -> audio_port
      :receiver_pid -> receiver_pid
      _ -> nil
    end
  end

  @spec set_dict(dict_state(), dict_index(), any()) :: dict_state()
  def set_dict(
        {
          {:connection_status, connection_status},
          {:node_target, node_target},
          {:audio_device, audio_device},
          {:accept_transfer, accept_transfer},
          {:chunk_data, chunk_data},
          {:is_talking, is_talking},
          {:audio_port, audio_port},
          {:receiver_pid, receiver_pid}
        },
        key,
        new_value
      ) do
    case key do
      :connection_status ->
        {{:connection_status, new_value}, {:node_target, node_target},
         {:audio_device, audio_device}, {:accept_transfer, accept_transfer},
         {:chunk_data, chunk_data}, {:is_talking, is_talking}, {:audio_port, audio_port},
         {:receiver_pid, receiver_pid}}

      :node_target ->
        {{:connection_status, connection_status}, {:node_target, new_value},
         {:audio_device, audio_device}, {:accept_transfer, accept_transfer},
         {:chunk_data, chunk_data}, {:is_talking, is_talking}, {:audio_port, audio_port},
         {:receiver_pid, receiver_pid}}

      :audio_device ->
        {{:connection_status, connection_status}, {:node_target, node_target},
         {:audio_device, new_value}, {:accept_transfer, accept_transfer},
         {:chunk_data, chunk_data}, {:is_talking, is_talking}, {:audio_port, audio_port},
         {:receiver_pid, receiver_pid}}

      :accept_transfer ->
        {{:connection_status, connection_status}, {:node_target, node_target},
         {:audio_device, audio_device}, {:accept_transfer, new_value}, {:chunk_data, chunk_data},
         {:is_talking, is_talking}, {:audio_port, audio_port},
         {:receiver_pid, receiver_pid}}

      :chunk_data ->
        {{:connection_status, connection_status}, {:node_target, node_target},
         {:audio_device, audio_device}, {:accept_transfer, accept_transfer},
         {:chunk_data, new_value}, {:is_talking, is_talking}, {:audio_port, audio_port},
         {:receiver_pid, receiver_pid}}

      :is_talking ->
        {{:connection_status, connection_status}, {:node_target, node_target},
         {:audio_device, audio_device}, {:accept_transfer, accept_transfer},
         {:chunk_data, chunk_data}, {:is_talking, new_value}, {:audio_port, audio_port},
         {:receiver_pid, receiver_pid}}

      :audio_port ->
        {{:connection_status, connection_status}, {:node_target, node_target},
         {:audio_device, audio_device}, {:accept_transfer, accept_transfer},
         {:chunk_data, chunk_data}, {:is_talking, is_talking}, {:audio_port, new_value},
         {:receiver_pid, receiver_pid}}

      :receiver_pid ->
        {{:connection_status, connection_status}, {:node_target, node_target},
          {:audio_device, audio_device}, {:accept_transfer, accept_transfer},
          {:chunk_data, chunk_data}, {:is_talking, is_talking}, {:audio_port, audio_port},
          {:receiver_pid, new_value}}
      _ ->
        {
          {:connection_status, connection_status},
          {:node_target, node_target},
          {:audio_device, audio_device},
          {:accept_transfer, accept_transfer},
          {:chunk_data, chunk_data},
          {:is_talking, is_talking},
          {:audio_port, audio_port},
          {:receiver_pid, receiver_pid}
        }
    end
  end
end
