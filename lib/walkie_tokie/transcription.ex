defmodule WalkieTokie.Transcription do
  use GenServer
  require Logger

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  @impl true
  def init(:ok) do
    Logger.info("[Transcription] Starting transcription service...")

    repo_id = "openai/whisper-tiny"

    # 1. Load the Model (Weights and Architecture)
    Logger.info("Loading Model...")
    {:ok, model_info} = Bumblebee.load_model({:hf, repo_id})

    # 2. Load Featurizer (Process Audio)
    Logger.info("Loading Featurizer...")
    {:ok, featurizer} = Bumblebee.load_featurizer({:hf, repo_id})

    # 3. Load Tokenizer (Process Text)
    Logger.info("Loading Tokenizer...")
    {:ok, tokenizer} = Bumblebee.load_tokenizer({:hf, repo_id})

    # 4. Load Generation Config (Required for Whisper to know how to generate text)
    Logger.info("Loading Generation Config...")
    {:ok, generation_config} = Bumblebee.load_generation_config({:hf, repo_id})

    # 5. Create the Serving
    # This combines all parts into an executable serving struct
    serving =
      Bumblebee.Audio.speech_to_text_whisper(
        model_info,
        featurizer,
        tokenizer,
        generation_config,
        compile: [batch_size: 1], # Optimization for single streams
        defn_options: [compiler: EXLA] # Ensure you have EXLA/Torch configured if you want speed
      )

    state = %{
      serving: serving,
      buffer: <<>>,
      is_recording: false
    }

    Logger.info("[Transcription] Transcription service started.")
    {:ok, state}
  end

  def transcribe(audio_chunk) do
    GenServer.cast(__MODULE__, {:transcribe, audio_chunk})
  end

  def start_recording do
    GenServer.cast(__MODULE__, :start_recording)
  end

  def stop_and_transcribe do
    GenServer.cast(__MODULE__, :stop_and_transcribe)
  end

  @impl true
  def handle_cast({:transcribe, audio_chunk}, state) do
    if state.is_recording do
      buffer = state.buffer <> audio_chunk
      {:noreply, %{state | buffer: buffer}}
    else
      {:noreply, state}
    end
  end

  def handle_cast(:start_recording, state) do
    Logger.info("[Transcription] Starting recording...")
    # Limpa o buffer antigo e começa a gravar
    {:noreply, %{state | buffer: <<>>, is_recording: true}}
  end

  def handle_cast(:stop_and_transcribe, state) do
    Logger.info("[Transcription] Stopped recording, processing buffer...")
    # Para de gravar e processa o buffer se não estiver vazio
    new_state = %{state | is_recording: false}

    if byte_size(state.buffer) > 0 do
      transcribe_buffer(state.buffer, state.serving)
      {:noreply, %{new_state | buffer: <<>>}}
    else
      Logger.info("[Transcription] Buffer is empty, nothing to transcribe.")
      {:noreply, new_state}
    end
  end

  defp transcribe_buffer(buffer, serving) do
    audio_tensor =
      Nx.from_binary(buffer, :s16)
      |> Nx.divide(32768.0)

    output = Nx.Serving.run(serving, audio_tensor)
    transcribed_text = Enum.map_join(output.chunks, " ", fn chunk -> chunk.text end)

    if String.trim(transcribed_text) != "" do
      Logger.info("[Transcription] Transcribed: #{inspect(transcribed_text)}")
      node_name = Atom.to_string(Node.self())

      Phoenix.PubSub.local_broadcast(
        WalkieTokie.ChatPubSub,
        "node_transcriptions",
        {:transcription, %{user: %{id: node_name, name: node_name}, text: transcribed_text, date: DateTime.utc_now()}}
      )
    end
  end
end
