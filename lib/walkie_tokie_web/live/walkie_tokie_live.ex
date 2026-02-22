defmodule WalkieTokieWeb.WalkieTokieLive do
  use WalkieTokieWeb, :live_view
  alias WalkieTokie.MicrophoneDriver
  alias Phoenix.PubSub
  alias WalkieTokie.Transcription

  @inactivity_timeout 10_000

  def mount(_params, _session, socket) do
    if connected?(socket) do
      PubSub.subscribe(WalkieTokie.PubSub, "node_speaking")
      PubSub.subscribe(WalkieTokie.PubSub, "cluster_events")
      PubSub.subscribe(WalkieTokie.PubSub, "webrtc_signals")
      PubSub.subscribe(WalkieTokie.ChatPubSub, "node_messages")
      PubSub.subscribe(WalkieTokie.ChatPubSub, "node_transcriptions")
      Process.send_after(self(), :check_inactive_users, @inactivity_timeout)
    end

    current_time = now()

    users =
      Node.list()
      |> Enum.reduce([], fn node, acc ->
        node_name = Atom.to_string(node)

        case String.contains?(node_name, "server") do
          true ->
            acc

          false ->
            [
              %{
                id: node,
                name: node_name,
                online: true,
                inactive: false,
                is_speaking: false,
                camera_active: false,
                last_active_at: current_time
              }
              | acc
            ]
        end
      end)

    full_name = Atom.to_string(Node.self())
    [username, _ip] = String.split(full_name, "@")
    custom_name = "#{username}@web-engenharia"

    {:ok,
     socket
     |> assign(is_transmitting: false)
     |> assign(is_camera_active: false)
     |> assign(active_user: nil)
     |> assign(users: users)
     |> assign(
       user: %{
         id: Node.self(),
         name: custom_name,
         online: true,
         inactive: false,
         is_speaking: false,
         camera_active: false,
         last_active_at: current_time
       }
     )
     |> assign(messages: [])}
  end

  def handle_event("send_message", %{"message" => message}, socket) do
    if message != "" do
      new_message = %{user: socket.assigns.user, body: message, date: now()}
      PubSub.broadcast!(WalkieTokie.ChatPubSub, "node_messages", {:message, new_message})
      {:noreply, socket}
    else
      {:noreply, socket}
    end
  end

  def handle_event("start_transmission", _params, socket) do
    MicrophoneDriver.start_talking()
    Transcription.start_recording()
    {:noreply, assign(socket, :is_transmitting, true)}
  end

  def handle_event("stop_transmission", _params, socket) do
    MicrophoneDriver.stop_talking()
    Transcription.stop_and_transcribe()
    {:noreply, assign(socket, :is_transmitting, false)}
  end

  def handle_event("toggle_camera", %{"active" => active}, socket) do
    PubSub.broadcast!(WalkieTokie.PubSub, "cluster_events", {:camera_status, Node.self(), active})
    {:noreply, assign(socket, :is_camera_active, active)}
  end

  def handle_event("webrtc_signal", %{"target" => target, "type" => type, "data" => data}, socket) do
    target_node = String.to_existing_atom(target)

    PubSub.broadcast!(
      WalkieTokie.PubSub,
      "webrtc_signals",
      {:webrtc_signal, Node.self(), target_node, type, data}
    )

    {:noreply, socket}
  end

  def handle_info({:message, message}, socket) do
    if socket.assigns.user.name != message.user.name do
      push_event(socket, "push-notification", %{
        title: "Nova mensagem de #{message.user.name}",
        body: message.body
      })
    end

    new_message = Map.put(message, :type, "message")

    {:noreply,
     socket
     |> assign(messages: socket.assigns.messages ++ [new_message])}
  end

  def handle_info({:transcription, %{text: message}}, socket) do
    if message != "" do
      new_message = %{user: socket.assigns.user, body: message, date: now()}
      PubSub.broadcast!(WalkieTokie.ChatPubSub, "node_messages", {:message, new_message})
      {:noreply, socket}
    else
      {:noreply, socket}
    end
  end

  def handle_info({:node_speaking, from_node_name}, socket) do
    current_time = now()

    users =
      socket.assigns.users
      |> Enum.map(fn user ->
        if Atom.to_string(user.id) == Atom.to_string(from_node_name) do
          %{user | is_speaking: true, inactive: false, last_active_at: current_time}
        else
          %{user | is_speaking: false}
        end
      end)
      |> Enum.sort_by(& &1.is_speaking, :desc)

    Process.send_after(self(), {:stop_speaking, from_node_name}, 10000)

    {:noreply,
     socket
     |> assign(users: users)
     |> assign(active_user: from_node_name)}
  end

  def handle_info({:stop_speaking, node_id}, socket) do
    users =
      socket.assigns.users
      |> Enum.map(fn user ->
        if user.id == node_id do
          %{user | is_speaking: false}
        else
          user
        end
      end)
      |> Enum.sort_by(& &1.is_speaking, :desc)

    {:noreply, assign(socket, users: users)}
  end

  def handle_info(:check_inactive_users, socket) do
    now = now()

    users =
      Enum.map(socket.assigns.users, fn user ->
        if user.online &&
             time_diff_in_seconds(user.last_active_at, now) > @inactivity_timeout / 1000 do
          %{user | inactive: true, is_speaking: false}
        else
          user
        end
      end)

    Process.send_after(self(), :check_inactive_users, @inactivity_timeout)

    {:noreply, assign(socket, users: users)}
  end

  def handle_info(:random_transmission, socket) do
    if !socket.assigns.is_transmitting do
      online_users = Enum.filter(socket.assigns.users, & &1.online)

      if online_users != [] do
        random_user = Enum.random(online_users)
        socket = assign(socket, :active_user, random_user.id)

        Process.send_after(self(), {:reset_active_user, random_user.id}, Enum.random(1000..2000))
        {:noreply, socket}
      else
        {:noreply, socket}
      end
    else
      {:noreply, socket}
    end
  end

  def handle_info({:reset_active_user, user_id}, socket) do
    if socket.assigns.active_user == user_id do
      {:noreply, assign(socket, :active_user, nil)}
    else
      {:noreply, socket}
    end
  end

  def handle_info({:nodedown, node_name}, socket) do
    IO.inspect(node_name, label: "Node down UI")

    updated_users =
      socket.assigns.users
      |> Enum.map(fn user ->
        if user.id == node_name do
          %{user | online: false, is_speaking: false}
        else
          user
        end
      end)

    {:noreply, assign(socket, users: updated_users)}
  end

  def handle_info({:nodeup, node_name}, socket) do
    IO.inspect(node_name, label: "Node up UI")

    updated_users =
      socket.assigns.users
      |> Enum.map(fn user ->
        if user.id == node_name do
          %{user | online: true, is_speaking: false}
        else
          user
        end
      end)

    {:noreply, assign(socket, users: updated_users)}
  end

  def handle_info({:camera_status, from_node, active}, socket) do
    users =
      Enum.map(socket.assigns.users, fn user ->
        if user.id == from_node do
          %{user | camera_active: active}
        else
          user
        end
      end)

    socket =
      socket
      |> assign(users: users)
      |> push_event("camera_status_change", %{
        node: Atom.to_string(from_node),
        active: active
      })

    {:noreply, socket}
  end

  def handle_info({:webrtc_signal, from_node, target_node, type, data}, socket) do
    if target_node == Node.self() do
      socket =
        push_event(socket, "webrtc_signal", %{
          from: Atom.to_string(from_node),
          type: type,
          data: data
        })

      {:noreply, socket}
    else
      {:noreply, socket}
    end
  end

  # Utils
  defp now(), do: DateTime.utc_now()

  defp time_diff_in_seconds(datetime1, datetime2) do
    DateTime.diff(datetime2, datetime1, :second)
  end
end
