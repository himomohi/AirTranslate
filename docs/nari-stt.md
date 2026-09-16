# Nari 실시간 STT

Nari Qwen3-ASR은 음성을 원문 자막으로 바꾸는 선택형 엔진이다. 기존 Apple
기본값은 유지한다. 이 기능은 TTS나 음성 복제를 추가하지 않는다.

## 사용

1. 설정 → API 키 → Nari STT에서 본인의 Nari API 키를 저장한다.
2. 설정 → 일반 또는 하단 엔진 메뉴에서 Nari STT를 선택한다.
3. PC 소리 또는 마이크를 고르고 시작한다. 최초 Nari 선택은 원문 전사다.

Nari를 새로 선택하면 유료 크레딧을 사용하는 GA Fast 모델이 선택된다. 설정 →
일반에서 과금 안내를 확인하고 원하는 GA 모델을 선택한다. 기존에 저장된
Free Public Beta 모델은 그대로 보존하며 시작을 차단한다. 앱은 이 설정을
유료 모델로 자동 전환하지 않는다. 차단 안내의 설정 열기로 일반 화면에
이동한 뒤 사용자가 GA 모델을 직접 선택해야 Nari STT를 시작할 수 있다.
4. 필요하면 출력 메뉴에서 번역을 선택한다. 번역은 기존 Apple Translation을
   사용하며 해당 언어 자산이 필요하다.

Nari 설정에서 현재 GA STT 모델인 Fast `qwen3-asr-fast` 또는 Standard
`qwen3-asr`를 선택할 수 있다. 모델 사용 가능 여부, 한도, 접근 권한, 유료
크레딧 조건은 Nari의 최신 제공자 문서와 계정 상태를 따른다. 키 저장 표시는
인증 성공을 의미하지 않는다. 요금과 한도는
[Nari 공식 모델 안내](https://docs.narilabs.com/models-and-pricing)를 따른다.

원문 언어를 지정하거나 Nari 전용 자동감지를 켤 수 있다. Nari는 한국어 포함
30개 언어를 안내한다. AirTranslate의 수동 언어 목록은 기존 목록을 유지한다.
자동감지 결과가 앱의 번역 언어 목록 밖이거나 언어를 판별하지 못한 경우에는
원문을 보존하고 번역할 수 없음을 표시한다.

## 처리 계약

- WebSocket: `wss://api.narilabs.com/v1/realtime?intent=transcription`.
- `session.configure`를 보내고 `session.configured`를 받은 다음 오디오를 보낸다.
- 두 입력 모두 16 kHz 모노로 캡처하며, signed PCM16 little-endian으로 변환한다.
  WAV 헤더 없이 100 ms/3,200바이트씩 base64 JSON 메시지로 전송한다.
- 서버 VAD로 발화를 구분한다. `transcript.partial`은 같은 `item_id`의 이전
  가설 전체를 교체한다. `transcript.completed`만 확정 결과로 저장하며 빈
  최종 결과는 이전 가설을 제거한다. 발화 순서는 `previous_item_id`로 보존한다.
- 일시정지는 새 입력을 차단하고 남은 음성을 commit한 뒤 연결을 닫는다.
  재개는 새로 인증·설정한 연결을 사용하며 이전 연결의 늦은 결과를 배제한다.
- 앱 또는 macOS의 오디오 공유 중지는 마지막 commit 응답과 미완료 발화를
  최대 15초 기다린다. 번역 출력은 대기 중인 번역도 최대 15초 기다린다.
  이후 미완료 번역에는 기존 취소 안내가 적용되고 완료 원문은 남는다.
- 전송 대기열은 48개 오디오 청크로 제한한다. 연결·프로토콜·대기열 오류는
  캡처를 중지하고 완료 자막을 보존한다. 사용자가 다시 시작하며, 미완료
  오디오를 자동 재전송하거나 무한 재연결하지 않는다.

공식 [STT quickstart](https://docs.narilabs.com/stt-quickstart),
[API 레퍼런스](https://docs.narilabs.com/api-reference/speech-to-text/realtime/realtime-transcription),
[발화 처리](https://docs.narilabs.com/transcripts-and-turn-detection),
[오류 정책](https://docs.narilabs.com/errors)를 2026-09-13 확인했고,
[모델 안내](https://docs.narilabs.com/models-and-pricing)의 공개 베타 종료 및 GA 전환 공지는
2026-09-16 다시 확인했다. Nari 문서는 2026-09-17 PT부터 `:free` 엔드포인트가 요청을
받지 않으며 STT는 `qwen3-asr` 또는 `qwen3-asr-fast` GA 모델 ID를 사용하라고 안내한다.
문서의 서버 측 지연 수치를 AirTranslate에서 측정한 지연으로 간주하지 않는다.

## 보관과 검증 범위

사용자 키는 `AirTranslate.Nari`의 별도 macOS Keychain 항목에 저장한다.
오디오는 사용자가 Nari를 선택하고 캡처를 시작했을 때 Nari API로 직접 전송한다.
앱 개발자의 공용 키나 중계 서버는 사용하지 않는다. 모델 선택·자동감지 설정만
UserDefaults에 저장하며, API 키·오디오·전사 본문을 진단 로그에 출력하지 않는다.
기록 파일 저장은 기존처럼 기본 꺼짐이다.

`NariRealtimeTranscriberTests`, `NariSessionTests`, `NariModelSettingsTests`,
`APIKeyStorePresenceTests`가 프로토콜·수명주기·오디오 형식·설정·저장을 검증한다.
이 테스트의 가짜 연결은 테스트 주입점에만 사용하며 앱은 URLSession WebSocket에
연결한다. 실제 Nari 계정 권한, 키 인증, 마이크/PC 실음성 인식 정확도와 지연은
실서비스 검증이 별도로 필요하다.
