# 음성 모델 기능 분류 감사

확인일: **2026-09-24**
범위: 현재 AirTranslate가 UI에서 선택하거나 기능 경로에서 실제 호출하는 음성 모델. 각 제공자의 전체 모델 카탈로그는 포함하지 않는다.

## 분류 결과

| 제공자·앱 모델 | 제공자 문서상 기능 | AirTranslate의 사용 방식 | 정확한 분류 |
| --- | --- | --- | --- |
| Apple 기본 모드 | `SpeechTranscriber`는 기기 내 음성→텍스트, `TranslationSession`은 텍스트 번역 | 실시간 전사 뒤 기기 내 텍스트 번역 | 로컬 실시간 전사 + 텍스트 번역 |
| Apple 전사만 | `SpeechTranscriber` 음성→텍스트 | 번역 없이 원문 자막 | 로컬 실시간 전사 |
| Apple 시스템 음성 | `AVSpeechSynthesizer`는 텍스트→합성 음성 | Apple 텍스트 번역 결과를 시스템 음성으로 읽음 | 텍스트 번역용 로컬 TTS. 스트리밍 번역 모델 아님 |
| OpenAI `gpt-realtime-translate` | 전용 Realtime Translations 세션에서 음성 입력→번역 음성 및 자막 | 번역 전용 WebSocket 엔드포인트. 원문 입력 전사는 `gpt-realtime-whisper`로 요청 | 실시간 음성-대-음성 번역 |
| OpenAI `gpt-realtime-whisper` | 저지연 실시간 음성→텍스트 전사 | `gpt-realtime-translate` 세션의 입력 오디오 전사 보조 모델로 호출 | 번역 모델과 짝을 이루는 실시간 원문 전사. 별도 번역 음성 모델은 아님 |
| OpenAI `gpt-live-transcribe` | 실시간 오디오 입력→전사 텍스트 스트림 | Realtime transcription 세션 | 실시간 전사, 합성 음성 없음 |
| Gemini `gemini-3.5-live-translate-preview` | Live API의 오디오 입력→번역 오디오와 텍스트 | `responseModalities: AUDIO`, 입력·출력 전사 활성화 | 실시간 음성-대-음성 번역 |
| Gemini `gemini-3.5-transcribe-live` | Live API의 오디오 입력→텍스트 스트림 | `responseModalities: TEXT`, 자동 언어 감지·SMART 전사 | 실시간 전사, 합성 음성 없음 |
| Gemini `gemini-3.8-flash-tts`, `gemini-3.8-flash-lite-tts` | 텍스트 입력→오디오 출력. 모델 문서상 Live API 미지원 | 안정된 번역 텍스트를 Interactions API에 보내 WAV를 생성 | 별도 텍스트-대-음성 합성(TTS). Live 모델 선택과 분리 |
| Meta `muse-voice-transcribe-1.0` | 실시간 WebSocket 전사와 파일 전사, 텍스트 출력 | 실시간 ASR WebSocket 사용 | 실시간 원문 전사 |
| Azure `MAI-Transcribe-2` | Speech-to-text 전사 API. 이 통합 경로는 오디오 파일 REST 요청 | 5초 단위 WAV를 만들어 REST 요청을 순차 처리 | 구간형 REST 전사. 스트리밍 WebSocket 모델로 분류하지 않음 |
| Nari `qwen3-asr`, `qwen3-asr-fast` | Nari의 Qwen3-ASR 실시간 스트리밍 전사 제품 | Nari 실시간 전사 WebSocket; 번역은 별도 Apple 번역 흐름 | 실시간 원문 전사 |
| Grok `grok-voice-transcribe-2.0` | 파일 전사와 실시간 WebSocket 전사 | `/v1/stt` WebSocket 스트림 | 실시간 원문 전사 |
| Qwen `qwen3.8-livetranslate-flash-realtime` | 실시간 음성 번역 전용 모델 | Realtime WebSocket의 `translation.language` 설정 | 실시간 음성 번역 |
| Qwen `qwen-audio-3.1-realtime-plus` | 전이중 실시간 음성 대화 모델. 음성·텍스트 응답 가능. Model Studio의 기능 표는 번역 기능을 별도 지원 항목으로 표시하지 않음 | WebSocket 세션에 번역 역할 지시를 보내고 텍스트 및 사용자가 켠 경우 음성 응답을 사용 | 실시간 음성 대화 모델을 번역 지시와 함께 사용. Qwen3.8 LiveTranslate와 같은 전용 번역 API로 표기하지 않음 |
| Qwen `qwen-audio-3.1-asr-flash-filetrans` | 긴 파일의 비동기 음성 인식, 작업 제출·상태 조회·결과 다운로드 | 공개 HTTPS URL을 제출하고 작업 완료를 폴링 | 비동기 파일 전사. 실시간 모델 선택과 분리 |

## UI 판정과 반영

- **실시간 모델과 번역문 TTS를 나누는 기준은 맞다.** 실시간 번역 모델은 오디오 스트림을 처리하고 자체 음성 출력을 만들 수 있다. TTS 모델은 번역이 끝난 텍스트를 입력받아 오디오를 별도로 생성한다. Gemini TTS는 Gemini Live 모델이 아니다. Apple `TranslationSession`을 쓰는 흐름은 Apple 또는 STT 제공자가 만든 전사 텍스트를 번역한 뒤 Apple 시스템 음성이나 Gemini TTS로 읽을 수 있다.
- 기존 Gemini 모델 메뉴는 Gemini Live 두 모델 옆에 Gemini TTS 두 모델을 다시 노출했고, 아래의 별도 음성 선택기도 같은 `speechSynthesisModel` 값을 바꿨다. 그래서 TTS를 Gemini Live 제공자 모델처럼 보이게 했으며 중복 선택 경로였다. 메인 Gemini 메뉴에서는 TTS 항목을 제거하고, 별도 선택기의 라벨·도움말을 Apple 텍스트 번역의 음성 선택으로 명시한다.
- Qwen Audio 3.1은 Qwen3.8 LiveTranslate의 별칭이나 TTS 엔진이 아니다. 제공자 문서에서는 실시간 음성 대화 모델로 분류하고, 앱은 프롬프트로 번역 역할을 지정한다. 선택 행의 설명도 이 경계를 밝힌다.
- Azure는 사용자에게 구간별 결과를 제공하지만, 앱 구현은 매 5초마다 파일형 REST 전사 요청을 보내므로 프로토콜 수준의 실시간 스트리밍으로 분류하지 않는다.
- Nari의 과거 `qwen3-asr:free`, `qwen3-asr-fast:free`는 종료된 베타 ID다. 설정 선택기에는 기존 저장값과 복구를 위해 남아 있지만 `canStart`가 거부하고, 메인 모델 메뉴는 시작 가능한 GA 모델만 보여 준다.

## 공식 문서

- Apple: [SpeechTranscriber](https://developer.apple.com/documentation/speech/speechtranscriber), [TranslationSession](https://developer.apple.com/documentation/translation/translationsession), [AVSpeechSynthesizer](https://developer.apple.com/documentation/avfaudio/avspeechsynthesizer)
- OpenAI: [Realtime translation](https://developers.openai.com/api/docs/guides/realtime-translation), [Realtime transcription](https://developers.openai.com/api/docs/guides/realtime-transcription), [GPT-Live-Transcribe](https://developers.openai.com/api/docs/models/gpt-live-transcribe), [GPT-Realtime-Whisper](https://developers.openai.com/api/docs/models/gpt-realtime-whisper), [model catalog](https://developers.openai.com/api/docs/models)
- Google: [Gemini Live translation](https://ai.google.dev/gemini-api/docs/live-api/live-translate), [Gemini Live transcription](https://ai.google.dev/gemini-api/docs/live-api/live-transcribe), [Gemini 3.8 speech generation](https://ai.google.dev/gemini-api/docs/speech-generation), [Gemini 3.8 Flash TTS model capabilities](https://ai.google.dev/gemini-api/docs/models/gemini-3.8-flash-tts)
- Meta: [Muse Voice Transcribe speech-to-text](https://dev.meta.ai/docs/speech-to-text)
- Microsoft: [MAI-Transcribe-2](https://learn.microsoft.com/en-us/azure/ai-services/speech-service/mai-transcribe?pivots=ai-foundry)
- Nari: [Qwen3-ASR streaming STT](https://narilabs.com/blog/achieving-the-pareto-frontier-for-stt/), [Nari model API pricing and categories](https://narilabs.com/pricing/)
- SpaceXAI: [Speech to Text](https://docs.x.ai/developers/model-capabilities/audio/speech-to-text)
- Alibaba Cloud: [Speech-to-speech and realtime translation model matrix](https://help.aliyun.com/en/model-studio/s2s-model), [Qwen Audio realtime voice guide](https://help.aliyun.com/en/model-studio/qwen-audio-realtime-user-guides), [non-realtime speech recognition](https://help.aliyun.com/en/model-studio/non-realtime-speech-recognition-user-guide)

## 분류 범위 메모

- 범위는 메인 제공자·모델 선택기와 설정에서 실제로 시작 가능한 모델, 그리고 활성 통합 코드가 보조 호출하는 모델이다. 제공자 전체 카탈로그는 조사 범위가 아니다.
- OpenAI `gpt-realtime-2.1`과 `gpt-realtime-2.1-mini`는 앱 코드에 음성 에이전트 모델로 정의되어 있지만, 현재 메인 선택기는 `gpt-realtime-translate` 또는 `gpt-live-transcribe`만 고른다. 현재 실시간 번역 경로는 두 음성 에이전트 모델을 호출하지 않으므로 사용자에게 제공되는 모델 목록이나 통합 기능으로 분류하지 않았다. 공식 모델 카탈로그는 두 모델을 실시간 음성 에이전트로 구분한다.
- Qwen Audio Filetrans는 실시간 모델 선택기가 아니라 설정의 비동기 파일 전사 기능이다. Nari의 종료된 `:free` 베타 ID는 설정에 저장된 과거 선택 복구용으로만 남아 있고 시작할 수 없다.

이 기록은 기능 종류를 대조한다. 실제 제공자 인증, 계정별 요금·할당량, 번역·전사 품질은 확인하지 않았다.
