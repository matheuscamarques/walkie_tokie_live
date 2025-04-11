defmodule WalkieTokieWeb.WalkieTokieLive do
  alias Phoenix.PubSub
  use WalkieTokieWeb, :live_view
  alias WalkieTokie.MicrophoneDriver

  @inactivity_timeout 10_000

  def mount(_params, _session, socket) do
    if connected?(socket) do
      PubSub.subscribe(WalkieTokie.PubSub, "node_speaking")
      Process.send_after(self(), :check_inactive_users, @inactivity_timeout)
    end

    current_time = now()

    users =
      Node.list()
      |> Enum.reject(fn node ->
        Atom.to_string(node) |> String.contains?("server")
      end)
      |> Enum.map(fn node ->
        %{
          id: node,
          name: Atom.to_string(node),
          online: true,
          is_speaking: false,
          last_active_at: current_time
        }
      end)

    {:ok,
     socket
     |> assign(is_transmitting: false)
     |> assign(active_user: nil)
     |> assign(users: users)}
  end

  def handle_event("start_transmission", _params, socket) do
    MicrophoneDriver.start_talking()
    {:noreply, assign(socket, :is_transmitting, true)}
  end

  def handle_event("stop_transmission", _params, socket) do
    MicrophoneDriver.stop_talking()
    {:noreply, assign(socket, :is_transmitting, false)}
  end

  def handle_info({:node_speaking, from_node_name}, socket) do
    IO.inspect("recebendo audio de #{from_node_name}")
    current_time = now()

    users =
      socket.assigns.users
      |> Enum.map(fn user ->
        if Atom.to_string(user.id) == Atom.to_string(from_node_name) do
          %{user | is_speaking: true, online: true, last_active_at: current_time}
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
        if user.online && time_diff_in_seconds(user.last_active_at, now) > (@inactivity_timeout / 1000) do
          %{user | online: false, is_speaking: false}
        else
          user
        end
      end)

    # Reagendar verificação
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

  # Utils
  defp now(), do: DateTime.utc_now()

  defp time_diff_in_seconds(datetime1, datetime2) do
    DateTime.diff(datetime2, datetime1, :second)
  end
end
