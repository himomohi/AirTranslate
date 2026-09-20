# 모드 툴팁 설명·요금 근거

공식 문서 확인일: **2026-09-19**, Qwen 추가 확인일: **2026-09-20**. 금액은 USD이며, 각 행은 실제 앱에서 사용하는 전송 방식과 세부 모델을 기준으로 한다. 요금은 확인일의 스냅샷이며 계정별 크레딧·무료 한도·세금·추가 옵션은 포함하지 않는다.

| 목록 항목·모델 | 툴팁 요금 | 공식 근거·조건 |
| --- | --- | --- |
| Apple 기본 모드 | 무료 · API 사용료 없음 | 기기 내 SpeechAnalyzer·Translation 사용. [Apple SpeechAnalyzer 설명](https://developer.apple.com/videos/play/wwdc2025/277/) |
| OpenAI 음성 → 번역 · `gpt-realtime-translate` | US$0.034/분 | [OpenAI 모델 문서](https://developers.openai.com/api/docs/models/gpt-realtime-translate)의 오디오 길이 기준 요금 |
| OpenAI 음성 → 원문 전사 · `gpt-live-transcribe` | US$0.017/분 | [OpenAI 모델 문서](https://developers.openai.com/api/docs/models/gpt-live-transcribe)의 오디오 길이 기준 요금 |
| Gemini · `gemini-3.5-live-translate-preview` | 유료 약 US$0.0368/분 · 토큰 기준 | [Google 요금표](https://ai.google.dev/gemini-api/docs/pricing): 오디오 입력 US$3.50/100만 토큰, 출력 US$21/100만 토큰. 공식 분당 추정치이며 실제 입력·출력 길이에 따라 달라짐 |
| Gemini · `gemini-3.5-transcribe-live` | 유료 약 US$0.009/분 · 토큰 기준 | [Google 요금표](https://ai.google.dev/gemini-api/docs/pricing): 오디오 입력 US$3.50/100만 토큰, 텍스트 출력 US$21/100만 토큰. 입력 25토큰/초·출력 약175토큰/분 가정의 공식 추정치 |
| Meta · `muse-voice-transcribe-1.0` | US$0.18/시간 | [Meta 모델 문서](https://dev.meta.ai/models/muse-voice-transcribe), [개요](https://dev.meta.ai/docs/overview). 화자 구분을 지원하는 실시간 전사 모델 |
| Azure · `MAI-Transcribe-2` | US$0.10/시간 · 할인 ~2026-12-31 | [Microsoft 모델 요금](https://microsoft.ai/models/mai-transcribe-2/), [Azure Speech 요금 조건](https://azure.microsoft.com/en-us/pricing/details/speech/). Preview 할인은 2026-12-31까지, 오디오 초 단위 청구. 앱은 5초 구간으로 전송 |
| Nari · `qwen3-asr` | US$0.06/시간 | [Nari 공식 요금](https://narilabs.com/pricing/), [STT 설명](https://narilabs.com/product/stt/). Standard 입력 오디오 길이 기준 |
| Nari · `qwen3-asr-fast` | US$0.12/시간 | [Nari 공식 요금](https://narilabs.com/pricing/). Fast 입력 오디오 길이 기준 |
| Nari · `qwen3-asr:free`, `qwen3-asr-fast:free` | 사용 불가 · GA 모델 선택 필요 | [Nari GA 공지](https://narilabs.com/blog/nari-model-apis-general-availability/): 무료 베타는 2026-09-16 23:59 PT 종료. US$0로 안내하지 않음 |
| Grok · `grok-voice-transcribe-2.0` | US$0.20/시간 | [xAI 요금표](https://docs.x.ai/developers/pricing), [Grok Voice Transcribe 2.0 공지](https://x.ai/news/grok-voice-transcribe-2). 앱의 WebSocket 스트리밍 요금이며 REST 일괄 전사 US$0.10/시간과 구분 |
| Qwen · `qwen3.8-livetranslate-flash-realtime` | 입력 $0.189/시간 + 번역문 $20/100만 토큰 · 음성 출력 추가 $1.35/시간 | [Alibaba Cloud 공식 모델·가격](https://www.alibabacloud.com/help/en/model-studio/qwen3-8-livetranslate-flash-realtime), 싱가포르 기준. 입력 7토큰/초, 음성 출력 12.5토큰/초. 원문 전사는 무료. [계산·설정 안내](qwen-livetranslate.md) |

Gemini 무료 티어는 별도로 존재한다. 툴팁은 유료 요금의 분당 추정치임을 표시하며 모든 계정에 정액 요금을 약속하지 않는다. Azure 할인 종료 후 요금은 새 공식 요금 확인 전 추정하지 않는다.

## 앱 연결과 검증

`ProcessingModeInfo`는 짧은 설명과 요금을 두 줄로 만들고 `ProcessingModePicker`의 모드 행에 macOS 기본 도움말(`help`)로 연결한다. 비활성 선택 버튼을 감싼 영역에 도움말을 적용해 API 키가 없는 항목에서도 확인할 수 있게 한다. 선택 버튼에는 같은 접근성 힌트를 제공하고, 톱니바퀴에는 기존 설정 안내를 유지한다. 목록 헤더의 요금 아이콘 도움말에 확인일과 통화를 표시한다. 모드 이름만 한 줄로 노출하고 키 상태·설명/요금은 각자의 아이콘과 툴팁으로 제공한다.

Gemini는 현재 세부 모델 또는 저장된 선호 모델의 요금을 사용한다. Nari가 켜져 있으면 현재 모델, 꺼져 있으면 기존 선택 동작이 사용하는 Fast 요금을 표시한다. 툴팁 조회는 선택·설정·키 값을 변경하지 않으며 과금 API를 호출하지 않는다.

`ProcessingModePickerTests`는 세부 모델 전환, 기존 선호 모델, Grok 스트리밍 단가, Azure 할인 기한, 종료된 무료 베타, 두 줄 형식을 검증한다. 실제 앱의 접근성 도움말과 화면 검증은 별도 실행 기록으로 남긴다. 키 존재는 인증 성공이나 실제 청구 금액 검증을 뜻하지 않는다.

## OpenAI 음성 통합

목록과 일반 설정에는 OpenAI 제공자 하나만 표시한다. 콘솔·일반/출력 설정의 동일한 출력 아이콘으로 번역과 원문 전사를 선택한다. 번역은 기존 `gpt-realtime-translate`, 원문 전사는 기존 `gpt-live-transcribe` 계약을 사용하며 전송 방식은 바꾸지 않는다. 정보 아이콘에는 현재 모델과 그 요금, OpenAI가 비활성이면 다시 선택할 마지막 출력의 모델과 요금을 표시한다.

마지막 출력은 저장해 다른 제공자로 이동하거나 앱을 다시 열어도 복원한다. OpenAI 내부의 전사/번역 왕복은 번역 대상 언어·번역 음성 출력 선호·플로팅 자막 형식을 보존한다. 전사 중에는 번역 음성을 끄고 원문 자막만 표시한다. 시작·실행·일시정지 중에는 출력 전환을 차단한다. 다른 제공자에서 OpenAI 번역으로 처음 진입할 때의 기존 기본값은 유지한다.
