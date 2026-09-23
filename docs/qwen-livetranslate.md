# Qwen Audio options

AirTranslate 1.12.0 supports two realtime models in Qwen LiveTranslate and an asynchronous audio-file transcription tool. These use the user's Alibaba Cloud Singapore credentials. The realtime models send selected microphone or Mac audio during capture. Filetrans sends a public HTTPS audio URL to QwenCloud for processing.

## Shared setup

1. Prepare an Alibaba Cloud Model Studio API key for the Singapore region. Qwen3.8 LiveTranslate also requires its workspace ID. Qwen Audio 3.1 Realtime Plus and Filetrans use the API key without a workspace ID.
2. In AirTranslate, open **Settings → API Keys → Alibaba Cloud · Qwen** and enter the key. Enter the workspace ID itself, not a URL, if you use Qwen3.8 LiveTranslate.
3. The API key is stored in the dedicated macOS Keychain item `AirTranslate.Qwen`. The workspace ID and selected realtime model are local app preferences. A saved key only means local configuration is present; it does not confirm account authorization, quota, or paid access.

The app currently offers English, Korean, Japanese, Chinese, Spanish, French, and German as target languages. It does not add the provider's full language selector, image input, or voice cloning.

## Realtime translation

Choose **Qwen LiveTranslate** in the main mode picker. In Settings → General, select one of these Qwen models:

| Model | Behavior |
| --- | --- |
| `qwen3.8-livetranslate-flash-realtime` | Existing default. Uses the LiveTranslate realtime API and its session-finish/finished lifecycle. |
| `qwen-audio-3.1-realtime-plus` | New alternate. Uses the Qwen Audio Realtime WebSocket protocol, server VAD, and waits for each response to finish before closing. |

Both options send selected audio directly to Alibaba Cloud Singapore and return original captions and translated text. Qwen3.8 uses its Singapore workspace ID; Realtime Plus authenticates with the API key over the Qwen Audio WebSocket API. Translation is requested through the session instructions. The app retains its existing optional speech-output preference, initially off. Apple translation language assets are not required.

The 3.1 model uses the Qwen Audio WebSocket endpoint and event contract, not the LiveTranslate endpoint or `session.finish` event. During stop, AirTranslate sends a short silent audio tail to let server VAD close the final turn, then drains the final response. The two protocol paths remain separate.

The documented Singapore rate for the existing 3.8 model was checked on 2026-09-20 and is summarized in [model pricing](processing-mode-pricing.md). This guide does not state numeric rates for Realtime Plus; check the current Model Studio console for the selected account's rate, quota, and charges.

## Qwen Audio Filetrans

Open **Settings → General → Qwen Audio File Transcription**. Enter a public HTTPS URL for audio you are authorized to send to QwenCloud, then submit it. The provider fetches the audio URL and processes it asynchronously. AirTranslate does not upload a local audio file in this workflow.

The app sends `qwen-audio-3.1-asr-flash-filetrans` with the URL, receives a task ID, checks the task status, and reads the completed transcript from the returned transcription URL. The transcript is shown in Settings for copying. Submitting a URL does not start microphone or system-audio capture.

The URL must be reachable by QwenCloud without your local network or browser session. Do not submit private URLs, links containing credentials or access tokens, or audio you do not have permission to share. The provider's account access, retention, quotas, pricing, and service terms apply. Numeric Filetrans rates are not stated here; check Model Studio for the current account rate. Key and URL content should not be included in support reports.

## Data and storage

- Realtime audio is sent to Alibaba Cloud Singapore only after Qwen LiveTranslate capture starts. Qwen3.8 uses the configured workspace ID; Realtime Plus uses the API key without a workspace ID, as supported by the [Qwen Audio WebSocket API](https://docs.qwencloud.com/api-reference/qwen-audio-realtime/websocket-api).
- Filetrans sends the entered public URL to QwenCloud; QwenCloud fetches the audio. The app reads the task's transcript result URL without forwarding the Qwen authorization header to that result host.
- The API key stays in macOS Keychain. Workspace ID and realtime model selection stay in local app preferences. The submitted URL and transcript are held for the active tool interaction and are not added to transcript files by this tool.
- Saving live transcript files remains opt-in and only confirmed Qwen live results are saved.

AirTranslate has no developer-operated relay or shared Qwen credential. Alibaba Cloud terms and the user's account configuration govern provider-side processing and retention. Local implementation tests do not prove live account authorization, billing, translation or transcription quality, or latency.

## Verification

Automated tests use fake WebSocket and HTTP clients. They cover model selection and restoration, model-specific connection/configuration, final-response draining, Filetrans request and task polling, rejected input, result parsing, and error handling. They do not contact QwenCloud or use a real API key.

## Official model documentation

- [Qwen Audio 3.1 Realtime Plus](https://www.qwencloud.com/models/qwen-audio-3.1-realtime-plus)
- [Qwen Audio 3.1 ASR Flash Filetrans](https://www.qwencloud.com/models/qwen-audio-3.1-asr-flash-filetrans)
- [Qwen Audio realtime client events](https://docs.qwencloud.com/api-reference/qwen-audio-realtime/client-events)
- [Qwen Audio realtime server events](https://docs.qwencloud.com/api-reference/qwen-audio-realtime/server-events)
- [Qwen Audio asynchronous file transcription API](https://docs.qwencloud.com/developer-guides/speech/asr)
