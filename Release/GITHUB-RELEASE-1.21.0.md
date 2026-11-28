# AirTranslate 1.21.0

## Faster session startup and translation scheduling

- Session warmup, speech recognition startup, and audio capture startup now overlap at capture start. Apple Translation caches ready sessions per language pair and strategy, Hy-MT2 preloads its local model during session warmup, and Apple Speech checks installed locales concurrently.
- **Fast Captions** tightens partial recognition cadence (`0.16s`) and first short-phrase quiet fallback (`0.15s`), while finalized utterances and idle translation queues skip unnecessary debounce delays.
- Superseded active partial translations are cancelled when newer utterances arrive, and matching finalized lines reuse already-completed translations without re-translating.
- `TranslationSegmentCache` uses an O(1) LRU cache retained across capture start/stop until language, engine, or protected-term settings change (excluding Hy-MT2).

## Local Hy-MT2, Keychain, transport, TTS, and UI responsiveness

- **Hy-MT2** runs model loading, prefill, and token decode on a dedicated serial queue with cooperative cancellation, FIFO waiter scheduling, KV-cache prefix reuse across consecutive prompts, and coalesced main-actor progress updates.
- All nine macOS **Keychain** API-key stores cache presence and values in memory with non-interactive `LAContext` reads and `SecItemUpdate` / `SecItemAdd` writes.
- Realtime cloud engines replace polling loops with condition waiters, fix a startup handshake send-queue race in Gemini Live and Meta Voice, enforce monotonic audio pacing in Qwen and Grok, and harden WebSocket and HTTP `URLSession` instances with ephemeral configurations and HTTP redirect rejection.
- **Gemini TTS** and **MAI Voice** prefetch the next queued utterance audio with generation guards, `TranslatedSpeechOutput` synchronizes utterance state with locking, and MAI Voice bounds chunked HTTP downloads.
- Input audio metering uses Accelerate/`vDSP` without per-callback heap allocations, throttles UI meter refreshes, and isolates caption board, floating caption window, and console audio-meter views from unrelated updates while caching floating history layout.
- Latency trace diagnostics (`AIRTRANSLATE_LATENCY_TRACE=1`) record opaque `session_id` and `line_id` UUIDs asynchronously with zero transcript text and report `first_source_to_translation_ms` for matched pairs.

## 한국어 요약

- 세션 시작 시 번역 엔진 예열(Apple 번역 및 로컬 Hy-MT2 모델 사전 로드), 음성 인식기 시작, 오디오 캡처 시작을 겹쳐 실행하며 Apple 음성 인식 지원 언어 확인을 병렬화했습니다.
- **빠른 자막**의 부분 인식 주기와 첫 짧은 구절 대기 시간을 줄이고, 확정된 발화와 빈 대기열의 불필요한 디바운스 대기를 건너뛰며, 새 발화가 오면 이전 미확정 번역을 취소하고 동일 확정 문장은 기존 번역을 재사용합니다.
- **Hy-MT2** 모델 로드·프리필·토큰 디코드를 전용 직렬 큐와 KV 캐시 접두사 재사용·코얼레싱된 진행률 갱신으로 처리하고, 모든 API 키 저장소에 Keychain 메모리 캐시를 적용했습니다.
- Gemini Live/Meta Voice 핸드셰이크 순서 경합을 수정하고, 실시간 WebSocket/OpenAI/Jev 세션의 임시 `URLSession` 및 리다이렉트 차단·조건 대기를 적용했으며, Gemini TTS/MAI Voice 다음 발화 사전 로드와 Accelerate/`vDSP` 오디오 레벨 계산, 자막 보드/플로팅 자막/오디오 미터 뷰 분리를 반영했습니다.

## Compatibility and distribution

- Requires **macOS 26 or later**. Apple Translation's Quality First strategy is available on macOS 26.4 or later; optional EmbeddingGemma 2 file transcription requires Apple Silicon and macOS 27 or later.
- DMG and ZIP packages are ad-hoc signed and unnotarized. See the [installation guide](https://github.com/himomohi/AirTranslate/blob/master/docs/GETTING-STARTED.md).

## Download

- [Repository](https://github.com/himomohi/AirTranslate)
- [AirTranslate 1.21.0 release](https://github.com/himomohi/AirTranslate/releases/tag/v1.21.0)
- [Latest stable DMG download](https://github.com/himomohi/AirTranslate/releases/latest/download/AirTranslate.dmg)
- [AirTranslate-1.21.0.zip](https://github.com/himomohi/AirTranslate/releases/download/v1.21.0/AirTranslate-1.21.0.zip)

Version **1.21.0 / build 1210**.
