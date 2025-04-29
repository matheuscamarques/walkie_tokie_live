defmodule WalkieTokie.KeyboardDetector do
  use GenServer
  require Logger

  @event_size 24 # bytes - size of each keyboard event

  # ==========================================================================
  # Public API
  # ==========================================================================

  @doc """
  Starts the `KeyboardDetector` GenServer. Optionally accepts configuration options.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Retrieves the current state of the keyboard monitor, specifically the CAPSLOCK state.
  """
  def get_state do
    GenServer.call(__MODULE__, :get_state)
  end

  # ==========================================================================
  # GenServer Callbacks
  # ==========================================================================

  @impl true
  @doc """
  Initializes the GenServer. It attempts to find the keyboard event path and starts a process to monitor it.
  """
  def init(_opts) do
    case find_keyboard_event_path() do
      {:ok, {name, event_path}} ->
        Logger.info("Found keyboard '#{name}' at #{event_path}. Starting monitor.")
        port_cmd = "cat #{event_path}"

        # Opens the port in stream mode (default), without :packet or :use_stdio.
        # :binary is critical to receive raw binary data.
        port_opts = [:binary, :exit_status, :hide, :stream]
        port = Port.open({:spawn, port_cmd}, port_opts)

        initial_state = %{
          event_path: event_path,
          keyboard_name: name,
          caps_lock_state: :released,
          port: port,
          buffer: <<>> # Buffer for partial data
        }
        {:ok, initial_state}

      {:error, reason} ->
        Logger.error("Failed to initialize KeyboardDetector: #{reason}")
        {:stop, reason}
    end
  end

  @impl true
  @doc """
  Handles the `:get_state` call to return the current CAPSLOCK state.
  """
  def handle_call(:get_state, _from, state) do
    {:reply, state.caps_lock_state, state}
  end

  @doc """
  Handles data received from the monitoring port. The data arrives in chunks, so it is buffered and processed.
  """
  @impl true
  def handle_info({port, {:data, new_data}}, %{port: port, buffer: old_buffer} = state) do
    # Combines the old buffer with the new data
    buffer = old_buffer <> new_data
    # Processes the buffer, extracting complete 24-byte events
    process_buffer(buffer, state)
  end

  @doc """
  Handles the closure of the monitoring port (process 'cat'). Logs the closure status.
  """
  @impl true
  def handle_info({port, {:exit_status, status}}, %{port: port} = state) do
    Logger.warn("Keyboard monitor port '#{state.keyboard_name}' closed with status: #{status}.")
    {:noreply, %{state | port: nil}}
  end

  @doc """
  Handles unknown messages. Logs any unhandled messages for debugging purposes.
  """
  @impl true
  def handle_info(message, state) do
    Logger.debug("Received unhandled message: #{inspect(message)}")
    {:noreply, state}
  end

  @doc """
  Callback for cleanup when the GenServer terminates. Closes the port if it is still open.
  """
  @impl true
  def terminate(reason, state) do
    Logger.info("KeyboardDetector shutting down (reason: #{inspect(reason)})")
    if port = state.port do
      Port.close(port)
      Logger.debug("Keyboard monitor port closed.")
    end
    :ok
  end

  # ==========================================================================
  # Private Helper Functions (Buffering and Parsing)
  # ==========================================================================

  @doc """
  Processes the buffer recursively, extracting events of size `@event_size` (24 bytes).
  Returns `{:noreply, new_state}` with the updated state.
  """
  defp process_buffer(buffer, state) when byte_size(buffer) >= @event_size do
    # Extracts a single event and the remaining buffer
    <<event_bin::binary-size(@event_size), rest_buffer::binary>> = buffer

    # Parses the extracted event
    new_state_intermediate =
      case parse_event(event_bin) do
        :pressed ->
          if state.caps_lock_state != :pressed do
            Logger.info("[CAPSLOCK] State changed to: pressed")
            %{state | caps_lock_state: :pressed}
          else
            state
          end
        :released ->
           if state.caps_lock_state != :released do
            Logger.info("[CAPSLOCK] State changed to: released")
            %{state | caps_lock_state: :released}
           else
             state
           end
        :ignore ->
          state # No state change
        {:error, reason} ->
          Logger.error("Error parsing keyboard event data: #{inspect(reason)}")
          state # No state change
      end

    # Continues processing the remaining buffer with the potentially updated state
    process_buffer(rest_buffer, %{new_state_intermediate | buffer: rest_buffer})
  end

  # If there is not enough data for a complete event, stores the buffer and waits for more data.
  defp process_buffer(buffer, state) do
    {:noreply, %{state | buffer: buffer}}
  end

  # Searches for a suitable keyboard event path.
  defp find_keyboard_event_path do
    dev_input_dir = "/dev/input/by-id/"
    unless File.exists?(dev_input_dir) do
      {:error, "Directory not found: #{dev_input_dir}"}
    else
      try do
        dev_input_dir
        |> File.ls!()
        |> Enum.filter(fn name ->
          lc_name = String.downcase(name)
          String.contains?(lc_name, "keyboard") and String.ends_with?(name, "-kbd")
        end)
        |> Enum.map(fn file_name ->
            link_path = Path.join(dev_input_dir, file_name)
            target_path = File.read_link!(link_path)
            abs_target_path = Path.expand(target_path, dev_input_dir)
            {file_name, abs_target_path}
          end)
        |> Enum.filter(fn {_name, path} ->
            String.starts_with?(path, "/dev/input/event")
          end)
        |> case do
            [] -> {:error, :no_suitable_keyboard_found}
            [{name, path} | _rest] -> {:ok, {name, path}}
           end
      rescue
        e in File.Error -> {:error, "Filesystem error: #{inspect(e)}"}
      end
    end
  end

  @doc """
  Parses the raw event data from the keyboard. Specifically looks for CAPSLOCK key events.
  """
  defp parse_event(<<
         _time_sec::integer-size(64)-little,
         _time_usec::integer-size(64)-little,
         type::integer-size(16)-little,
         code::integer-size(16)-little,
         value::integer-size(32)-little
       >>) do
    if type == 1 && code == 58 do # EV_KEY & KEY_CAPSLOCK
      case value do
        1 -> :pressed
        0 -> :released
        _ -> :ignore
      end
    else
      :ignore
    end
  catch
    :error, reason -> {:error, reason}
  end

  # Handles unexpected data formats in the event data.
  defp parse_event(other_data) do
    Logger.warn("Received unexpected data format in parse_event: #{inspect(other_data)}")
    {:error, :unexpected_data_format}
  end
end
