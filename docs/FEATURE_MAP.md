# Feature Map

| Feature | Entry point | Core files and symbols | Data and external dependency | Verification |
| --- | --- | --- | --- | --- |
| Qwen realtime model selection | Main mode picker; Settings > General | `QwenTranslationModel`, `QwenRealtimeTranslationService`, `TranslationSessionStore`, `QwenCopy` | Microphone or Mac audio is sent to Alibaba Cloud Singapore after capture starts. Qwen3.8 uses the workspace ID; Realtime Plus authenticates with the API key and Qwen Audio WebSocket protocol. | `swift test --filter Qwen`; `./script/build_and_run.sh --verify` |
| Qwen Audio Filetrans | Settings > General > Qwen Audio File Transcription | `QwenAudioFileTranscriptionView`, `QwenAudioFileTranscriptionService` | A user-provided public HTTPS audio URL is sent to QwenCloud. QwenCloud fetches the file and returns an asynchronous task result. This workflow does not upload local audio files. | `swift test --filter QwenAudioFileTranscriptionServiceTests`; `./script/build_and_run.sh --verify` |
