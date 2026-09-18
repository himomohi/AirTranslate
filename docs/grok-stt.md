# Grok Voice Transcribe 2.0

SpaceXAI(xAI)의 `grok-voice-transcribe-2.0`으로 마이크나 Mac에서 재생되는
음성을 원문 자막으로 바꾸는 선택형 전사 엔진이다. AirTranslate 1.10.0부터
포함되며, 별도의 xAI API 키가 필요하다.

## 사용

1. 설정 → API 키에서 SpaceXAI(xAI) 제공자에 본인의 API 키를 저장한다.
2. 엔진 메뉴에서 Grok STT를 선택한다. 처음 선택하면 원문 전사로 시작한다.
3. PC 소리 또는 마이크를 선택하고 시작한다.

키는 [xAI 콘솔](https://console.x.ai/)에서 발급한다. 키 저장 상태는
서비스 인증 성공을 뜻하지 않는다. 제공자의 API 이용 요금, 계정 권한과
한도가 적용된다. 기존 Apple 기본값과 다른 제공자의 키는 유지한다.

## 전사 연결

- 모델을 `grok-voice-transcribe-2.0`으로 명시한다. 공식 API는 모델을 생략하면
  1.0을 사용하므로 버전을 생략하지 않는다.
- `wss://api.x.ai/v1/stt`에 TLS로 연결하고 API 키는 인증 헤더로만 보낸다.
- 16 kHz 모노 PCM16 little-endian 오디오를 바이너리 프레임으로 보낸다.
  준비 응답 `transcript.created` 이전에는 오디오를 전송하지 않는다.
- `transcript.partial`의 수정 가능한 결과, 확정된 구간, 전체 발화 확정을
  구분한다. 전체 발화에 이미 포함된 구간을 다시 붙이지 않는다.
- 중지할 때 `audio.done`을 보내고 서버의 마지막 `transcript.done`을 처리한다.

Grok의 `language` 매개변수는 숫자·통화·단위의 표기 형식을 위한 값이다.
특정 언어만 인식하도록 강제하는 값이 아니다. 서버가 감지 언어를 보내지
않으면 수동 선택 언어를 감지 결과처럼 표시하지 않는다.

## 개인정보와 검증 범위

Grok을 선택하고 캡처를 시작하면 선택한 입력의 오디오가 xAI API로 직접
전송된다. 개인 API 키는 별도 macOS Keychain 항목에 보관하며 앱 설정이나
기록에 원문 키를 저장하지 않는다. 앱 개발자가 운영하는 중계 서버는 없다.
전사 파일 저장은 기존의 사용자 선택 설정을 따른다.

로컬 테스트와 앱 화면 확인은 실제 계정 인증, 사용 한도, 음성 인식 품질을
증명하지 않는다. 이 부분은 유효한 사용자 키와 실제 음성으로 별도 확인해야 한다.

공식 계약 확인: 2026-09-18.

- [Speech to Text 가이드](https://docs.x.ai/developers/model-capabilities/audio/speech-to-text)
- [Speech to Text API 레퍼런스](https://docs.x.ai/developers/rest-api-reference/inference/speech-to-text)
