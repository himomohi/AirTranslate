![AirTranslate hero](docs/assets/airtranslate-readme-hero.png)

# AirTranslate

macOS용 실시간 시스템 오디오 기록 및 번역 앱.

<p align="center">
  <a href="https://github.com/himomohi/AirTranslate/releases/latest/download/AirTranslate.dmg"><img alt="Download AirTranslate.dmg" src="https://img.shields.io/badge/Download-AirTranslate.dmg-2EA44F?style=for-the-badge&logo=apple&logoColor=white"></a>
  <a href="https://github.com/himomohi/AirTranslate/releases/latest"><img alt="Latest release" src="https://img.shields.io/github/v/release/himomohi/AirTranslate?style=for-the-badge&label=Latest"></a>
  <a href="https://himomohi.github.io/AirTranslate/"><img alt="Official guide site" src="https://img.shields.io/badge/Guide-Site-0A84FF?style=for-the-badge"></a>
</p>

<p align="center">
  <a href="https://himomohi.github.io/AirTranslate/">공식 안내 사이트</a> ·
  <a href="#다운로드">다운로드</a> ·
  <a href="#요구-사항">요구 사항</a> ·
  <a href="#개인정보와-api-키">개인정보</a> ·
  <a href="README.md">English</a> ·
  한국어 ·
  <a href="README.ja.md">日本語</a> ·
  <a href="README.zh-CN.md">中文</a>
</p>

<p align="center">
  <img alt="macOS 26+" src="https://img.shields.io/badge/macOS-26%2B-0A84FF?style=flat-square&logo=apple">
  <img alt="Swift 6.2+" src="https://img.shields.io/badge/Swift-6.2%2B-F05138?style=flat-square&logo=swift&logoColor=white">
  <a href="LICENSE"><img alt="License: Apache 2.0" src="https://img.shields.io/badge/License-Apache%202.0-blue?style=flat-square"></a>
</p>

AirTranslate는 Mac에서 재생되는 소리를 실시간으로 기록하고 번역하며, 필요하면 플로팅 자막 창으로 표시합니다. 회의, 강의, 영상, 인터뷰, 스트림처럼 외부 마이크로 우회하기 애매한 오디오를 Mac 시스템 오디오에서 직접 받아 처리하는 데 초점을 둡니다.

사용자용 소개, 설치 안내, 다운로드 경로는 [AirTranslate 공식 안내 사이트](https://himomohi.github.io/AirTranslate/)에서 볼 수 있습니다.

기본 처리 흐름은 Apple 프레임워크를 사용합니다. GPT Realtime, Gemini Live Translate, Meta Scribe는 선택형 API 기반 모드이며, 사용자가 직접 해당 API 키를 입력했을 때만 사용할 수 있습니다.

## 왜 AirTranslate인가

- **시스템 오디오 우선:** ScreenCaptureKit으로 Mac 재생음을 직접 캡처합니다.
- **읽기 좋은 실시간 작업 공간:** 원문과 번역을 나란히 유지합니다.
- **플로팅 자막:** 다른 앱 위에 자막을 띄워 영상이나 회의를 보며 확인할 수 있습니다.
- **Apple 기본 처리:** Apple Speech와 Apple Translation을 기본 경로로 유지합니다.
- **선택형 API 모드:** 필요한 경우에만 OpenAI Realtime Translation, Gemini Live Translate 또는 Meta Scribe를 켭니다.
- **Keychain 저장:** OpenAI, Gemini, Meta API 키는 사용자가 입력하고 macOS Keychain에 저장합니다.
- **일반 텍스트 기록:** 저장된 기록은 Mac 안의 `.txt` 파일로 남습니다.

![AirTranslate demo](docs/assets/airtranslate-readme-demo.gif)

> "Turn any Mac audio into live captions and translation, right where you are watching."

## 1.7.1 주요 변경사항

- **더 안정적인 플로팅 번역:** 새 번역이 준비될 때까지 이전 번역을 유지해, 인식기가 문장을 고칠 때마다 자막이 다시 쓰이거나 깜빡이지 않습니다.
- **예약된 자막 높이:** 플로팅 자막이 고정 블록 높이를 유지하고 교체 문구를 한 덩어리로 페이드해, 글자가 늘어나도 원문 줄이 위아래로 점프하거나 다시 가운데 맞춰지지 않습니다.
- **자막 안정화와 정렬:** 설정과 메뉴 막대에서 자막 안정화(빠름/기본/안정)와 자막 정렬(가운데/왼쪽)을 고를 수 있습니다. 왼쪽 정렬은 줄이 늘어나도 시작점이 고정됩니다.
- **프레젠테이션 품질 모드:** 스위치 하나로 번역만 표시되는 두 줄 청중용 오버레이와 더 안정적인 구절 타이밍을 설정합니다. 발표 맥락과 용어집을 추가해 이름, 브랜드, 약어, 선호 번역을 정확히 유지할 수 있습니다.

전체 내용은 [AirTranslate 1.7.1 릴리즈 노트](https://github.com/himomohi/AirTranslate/releases/tag/v1.7.1)에서 확인할 수 있습니다.

## 1.7.0 주요 변경사항

- **Meta Scribe:** 선택형 Muse Voice Transcribe가 화자 라벨과 25개 언어 코드 스위칭 실시간 전사를 기존 번역 레이어 앞에 추가합니다. 설정에서 Meta API 키를 입력하며, Apple 기본 모드는 계속 로컬 우선 기본값입니다.
- **Stage & Console:** 설정 사이드바를 없애고, 턴 기반 자막 블록이 창을 채우며 최신 턴은 시작/중지·오디오 소스·언어 경로·출력·음성·엔진이 있는 하단 콘솔 바로 위에 고정됩니다.
- **공유 Air teal 디자인 시스템:** 듣는 중/일시정지/중지 색, 레이어드 표면, 자막 타이포그래피가 메인 창·설정·기록 보관함·플로팅 자막·메뉴 막대에 라이트/다크 모두 적용됩니다.
- **키보드 포커스 링:** 커스텀 제어는 액센트 색 포커스 링을 쓰고, 시작 버튼이 초기 포커스를 받으며, 세션 잠금 제어는 하나의 잠금 표시로 흐려지면서도 보조 기술에 완전히 설명됩니다.
- **Apple 기본 모드 장시간 롤오버:** 확정된 글자가 약 600자가 되거나 긴 무음이 있으면 라이브 줄을 새 턴 블록으로 롤오버해, 인식 갱신마다 전체 전사를 메인 스레드에서 다시 처리하지 않습니다. 저장된 기록에는 세션 전체가 남습니다.
- **스테이지 빈 화면 방지:** 피드는 최근 12개 턴 블록만 일반 스택으로 그려, 긴 세션이나 중지/시작 뒤 자막이 사라지던 문제를 고치고 렌더 비용을 일정하게 유지합니다.

전체 내용은 [AirTranslate 1.7.0 릴리즈 노트](https://github.com/himomohi/AirTranslate/releases/tag/v1.7.0)에서 확인할 수 있습니다.

## 1.6.2 주요 변경사항

- **화면 기록 요청은 최초 1회:** AirTranslate는 화면 기록 권한이 처음 필요한 시도에서만 macOS 시스템 요청을 엽니다. 이후에도 권한을 사용할 수 없으면 요청 창을 반복해서 띄우지 않고 개인정보 보호 및 보안 설정으로 안내합니다.
- **사용할 설치본 하나만 유지:** 오래되었거나 서명이 다른 AirTranslate 사본은 `dev.appcaster.AirTranslate` Bundle ID가 같아도 macOS TCC에서 서로 다른 권한 정체성으로 처리될 수 있습니다. 다른 사본은 제거하거나 보관하고 실제로 사용할 설치본 하나만 남기세요.
- **ad-hoc 업데이트 경계 명시:** 공개 DMG와 ZIP은 ad-hoc 서명 빌드이므로 업데이트 사이에 화면 기록 권한이 안정적으로 승계된다고 보장할 수 없습니다. 새 설치본을 시스템 설정에서 다시 확인해야 할 수 있습니다.
- **숨겨진 설정 포커스 루프 제거:** 보이지 않는 Settings Scene의 세그먼트 `Picker`가 캡처 시작 중 비활성화 상태로 바뀌지 않도록 했습니다. 이 전환은 AppKit 포커스 탐색과 AttributeGraph CPU 루프를 만들어 상단 Gemini Live 시작이 멈춘 것처럼 보이게 할 수 있었으며, 이제 시작 흐름이 정상 진행됩니다.

전체 내용은 [AirTranslate 1.6.2 릴리즈 노트](https://github.com/himomohi/AirTranslate/releases/tag/v1.6.2)에서 확인할 수 있습니다.

## 1.6.1 주요 변경사항

- **Gemini Live 시작 안정화:** 상단 시작 버튼이 선택한 Gemini Live 모드로 캡처를 시작합니다.
- **캡처 제어의 CPU 루프 방지:** 잠긴 세그먼트 제어는 보이는 상태를 유지하면서도 시작 중 AttributeGraph CPU 루프를 유발할 수 있는 macOS 비활성화 상태 포커스 경로를 사용하지 않습니다.
- **조치 가능한 시작 실패 안내:** 시작 실패가 일시적인 오버레이로 사라지지 않고 기본 창에 남아 API 키 설정, macOS 개인정보 보호 설정 또는 재시도 동작을 바로 제공합니다.
- **현재 빌드 권한 안내:** 권한 안내가 현재 서명된 AirTranslate 빌드를 식별합니다. macOS가 이를 인식하지 못할 때는 현재 앱만 남기고 해당 권한만 한 번 새로 고친 뒤 종료·재실행하면 되며, 일반 업데이트에 TCC 초기화는 필요하지 않습니다.

전체 내용은 [AirTranslate 1.6.1 릴리즈 노트](https://github.com/himomohi/AirTranslate/releases/tag/v1.6.1)에서 확인할 수 있습니다.

## 1.6.0 주요 변경사항

- **Gemini 원문 전사와 자동 언어 감지:** Gemini API 키를 직접 추가한 뒤 선택형 **Gemini 3.5 Transcribe Live**로 번역 없는 원문 자막을 만들 수 있으며, 캡처 중 말하는 언어를 자동 감지합니다.
- **장시간 Gemini 세션 안정화:** finished 상태 처리, 세션 재개, GoAway 재연결 권장 처리, 제한된 컨텍스트 압축, 40ms 오디오 청크 전송으로 긴 캡처 경로를 보강했습니다.
- **반응형 원문 전용 흐름:** 최소 지원 크기의 작업 공간과 설정 창도 제어를 가리지 않고 재배치하며, Apple·GPT·Gemini 전사 모드에서 대상 언어·번역문·번역 음성 제어를 일관되게 숨깁니다.

전체 내용은 [AirTranslate 1.6.0 릴리즈 노트](https://github.com/himomohi/AirTranslate/releases/tag/v1.6.0)에서 확인할 수 있습니다.

## 1.5.1 주요 변경사항

- **미니멀하고 일관된 인터페이스:** 메인 작업 공간, 사이드바, 메뉴 막대, 플로팅 자막, 기록 보관함, 설정이 간격·아이콘·표면·선택·호버 피드백을 하나의 절제된 디자인 체계로 공유합니다.
- **명확한 설정 상태:** 권한별로 확인 가능한 상태를 보여 주거나 시스템 설정에서 확인하도록 안내하고, 언어 자산 다운로드 진행·오류·재시도와 앱 버전·빌드 정보를 제공합니다.
- **안정적인 설정 제어:** 음량은 음성 출력 상태에 맞춰 활성화되고, API 키 저장은 세션 저장소의 단일 경로를 사용하며, 시작 시에는 비밀 데이터를 읽거나 인증 창을 띄우지 않고 Keychain 존재 여부만 확인하고, 플로팅 자막 미리보기는 선택한 표시 방식과 동기화됩니다.
- **키보드와 접근성:** 설정 구간을 이동해도 선택 상태가 안정적으로 유지되고, 접근성 레이블·값과 동작 줄이기 환경을 더 충실히 지원합니다.

전체 내용은 [AirTranslate 1.5.1 릴리즈 노트](https://github.com/himomohi/AirTranslate/releases/tag/v1.5.1)에서 확인할 수 있습니다.

## 1.5.0 주요 변경사항

- **Apple 기본 모드 수명주기 강화:** Apple 기본 모드는 계속 로컬 우선 기본 경로이며, 이전 시작 시도의 늦은 권한 응답·warm-up·캡처 콜백이 새 세션을 바꾸지 못하게 합니다.
- **외부 중지의 정상 처리:** 앱 밖에서 macOS 시스템 오디오 캡처를 중지해도 기록을 저장하고 세션 잠금을 풀어 다시 시작할 수 있습니다.
- **무음 입력 유실 방지:** 음성 입력 backpressure는 조용히 버리는 대신 사용자에게 보이는 제어된 중지로 처리합니다.
- **선택형 GPT 전사:** OpenAI API 키를 제공한 경우에만 `gpt-live-transcribe`로 원문 자막을 만들 수 있으며, GPT 실시간 번역과는 별도 모드입니다.

전체 내용은 [AirTranslate 1.5.0 릴리즈 노트](https://github.com/himomohi/AirTranslate/releases/tag/v1.5.0)에서 확인할 수 있습니다.

## 1.4.2 주요 변경사항

- **안정적인 마이크 권한 요청:** 서명된 로컬 및 릴리즈 빌드에 macOS 마이크 권한 요청에 필요한 audio-input 엔타이틀먼트를 포함합니다.
- **릴리즈 서명 점검:** 배포 전에 Hardened Runtime, 릴리즈/디버그 엔타이틀먼트 분리, 마이크 권한 설명을 패키징 검사로 확인합니다.

전체 내용은 [AirTranslate 1.4.2 릴리즈 노트](https://github.com/himomohi/AirTranslate/releases/tag/v1.4.2)에서 확인할 수 있습니다.

## 1.4.1 주요 변경사항

- **더 안정적인 번역 음성:** Apple 기본 모드는 스트리밍 번역문이 안정적인 문장 경계에 도달한 뒤 음성으로 읽습니다.
- **마지막 문장 보존:** 마침표 없이 끝난 최종 번역도 요청이 완료되면 바로 음성으로 출력합니다.
- **반복 꼬리 억제:** 짧게 줄었다가 복원된 문장 끝부분, 거의 같은 최종 수정본, 짧은 반복 접미어를 다시 읽지 않습니다.
- **깔끔한 더빙 전환:** 번역 음성을 켰을 때 이미 화면에 보이던 번역문을 다시 읽지 않습니다.
- **정상 반복 유지:** 짧은 재생 방지 시간이 지난 뒤 실제로 반복되는 문구는 같은 세션 안에서도 다시 읽을 수 있습니다.
- **집중 회귀 테스트:** 번역 음성 진행 로직을 전용 AirTranslateCore 테스트로 검증합니다.

전체 내용은 [AirTranslate 1.4.1 릴리즈 노트](https://github.com/himomohi/AirTranslate/releases/tag/v1.4.1)에서 확인할 수 있습니다.

## 핵심 기능

- Mac 시스템 오디오 실시간 캡처
- Apple Speech 기반 전사
- Apple Translation 기반 번역
- 원문만 집중해서 보는 전사 전용 모드
- 내장 마이크/블루투스, AirPods 마이크 입력 지원
- Apple 기본 모드의 원문 언어 자동 감지는 언어 전환 안정성 개선을 위해 일시 비활성화
- OpenAI Realtime Translation 기반 GPT 모드
- 원문 자막용 선택형 `gpt-live-transcribe` GPT 전사 모드
- Gemini 3.5 Live Translate 모드와 자동 언어 감지 원문 전사용 선택형 Gemini 3.5 Transcribe Live 모드
- 화자 라벨과 25개 언어 전사를 기존 번역 레이어 앞에 두는 선택형 Meta Scribe 모드
- API 기반 번역 스트림용 LIVE 번역 모드
- 마이크 입력 안정성 개선(중복 입력/전환 흔들림 완화)
- 원문/번역 언어 한 번에 바꾸기
- 플로팅 자막 창
- macOS 맞춤법 후보 기반 기록 다듬기
- 선택형 번역 음성 출력
- 저장된 기록 확인, 수정, 삭제, 폴더 열기
- Mac 언어 설정에 맞춘 영어, 한국어, 일본어, 중국어 간체 UI 자동 선택

## 처리 방식

AirTranslate는 빠른 선택과 상세 설정을 분리합니다.

| 모드 | 적합한 경우 | 설명 |
| --- | --- | --- |
| Apple 기본 모드 | 로컬 중심 전사와 번역 | Apple Speech로 전사하고 Apple Translation으로 선택한 언어쌍을 번역합니다. 원문 언어 자동 감지는 언어 전환 안정성 개선을 위해 일시 비활성화되어 있습니다. |
| GPT 모드 | OpenAI Realtime 실시간 번역 | 오디오를 OpenAI Realtime Translation으로 직접 스트리밍합니다. 저장된 API 키가 없으면 설정 모달을 열고 API 키 입력칸에 포커스를 둡니다. |
| GPT 전사 | OpenAI 원문 자막 | 선택형 모드에서 OpenAI API 키를 제공하면 `gpt-live-transcribe`로 번역 없이 원문 자막을 만듭니다. |
| Gemini Live | Gemini 3.5 Live Translate 또는 원문 전사 | Gemini 3.5 Live Translate는 원문/번역 전사를 표시하고, Gemini 3.5 Transcribe Live는 자동 언어 감지 원문 자막만 표시합니다. 두 모드 모두 사용자가 제공한 Gemini API 키가 필요합니다. |
| Meta Scribe | 화자 라벨이 있는 다국어 자막 | Muse Voice Transcribe로 화자 라벨과 25개 언어 코드 스위칭 실시간 전사를 만든 뒤 AirTranslate의 기존 번역 레이어를 사용합니다. Meta API 키가 필요합니다. |
| 전사만 | 번역 없이 원문 자막만 필요할 때 | Translation 없이 원문 기록만 남깁니다. |
| LIVE 번역 | 번역 스트림을 직접 만들고 싶을 때 | 선택한 API 제공자의 실시간 번역 모델이 번역 결과를 직접 생성하는 경로를 사용합니다. |

GPT, Gemini, Meta 모델 세부 선택, API 키 입력, 기록 다듬기, 음성 출력은 톱니바퀴 설정 창에서 관리합니다. 일상적인 캡처 제어는 Stage 아래 떠 있는 콘솔 바에 있습니다.

## 개인정보와 API 키

AirTranslate는 계정 시스템이나 개발자 운영 중계/백엔드 서버를 포함하지 않습니다. 그렇다고 모든 모드가 오프라인이라는 뜻은 아닙니다. 선택형 제공자 모드는 선택한 기능에 필요한 오디오나 텍스트를 해당 외부 API로 직접 전송합니다.

- Apple 기본 모드는 macOS 프레임워크와 Apple 언어 자산을 사용합니다.
- GPT 모드 또는 선택형 GPT 전사 모드를 켰을 때만 필요한 오디오나 텍스트가 사용자의 OpenAI API 키로 OpenAI API에 직접 전송됩니다.
- Gemini Live Translate 또는 Gemini 3.5 Transcribe Live를 켰을 때만 필요한 오디오가 사용자의 Gemini API 키로 Google Gemini API에 직접 전송됩니다.
- Meta Scribe를 켰을 때만 필요한 오디오가 사용자의 Meta API 키로 Meta Muse Voice Transcribe API에 직접 전송됩니다.
- OpenAI, Gemini, Meta API 키는 사용자가 제공해 Keychain에 저장하며, 앱에 하드코딩하거나 커밋하거나 릴리즈 패키지에 포함하지 않습니다.
- API 키는 `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` 옵션으로 macOS Keychain에 저장합니다.
- 저장된 기록은 사용자 Mac의 일반 텍스트 파일입니다.

API 키가 필요하면 [OpenAI API 키 페이지](https://platform.openai.com/api-keys), [Google AI Studio API 키 페이지](https://aistudio.google.com/app/apikey) 또는 [Meta 개발자 포털](https://dev.meta.ai)에서 키를 만든 뒤 AirTranslate 설정 창에 붙여 넣으세요.

## Apple 번역 언어팩

Apple 기본 모드는 macOS가 관리하는 번역 언어 자산을 사용합니다. 새로운 언어쌍으로 Apple 기본 모드를 사용하기 전에 필요한 Apple 번역 언어팩을 내려받으세요.

1. **시스템 설정**을 엽니다.
2. **일반 > 언어 및 지역**으로 이동합니다.
3. **번역 언어**를 클릭합니다.
4. 사용할 원문 언어와 번역 언어마다 **다운로드**를 클릭합니다.
5. 선택 사항: 가능한 번역을 Mac에서 처리하고 싶다면 **온디바이스 모드**를 켭니다.

선택한 언어쌍을 사용할 수 없거나 아직 다운로드하지 않았다면, macOS에 필요한 언어 자산이 준비될 때까지 Apple 기본 모드 번역이 시작되지 않거나 사용할 수 없음 상태가 표시될 수 있습니다.

## 필요한 권한

AirTranslate는 캡처와 전사 흐름에 필요한 권한만 요청합니다.

- 화면 기록
- 시스템 오디오 녹음
- 마이크(마이크 입력을 선택한 경우에만)
- 음성 인식

ScreenCaptureKit의 시스템 오디오 캡처 경로 때문에 화면 기록 권한이 필요합니다. AirTranslate는 화면 프레임을 녹화 파일로 저장하지 않습니다. 시스템 요청은 권한이 처음 필요한 시도에서만 열며, 그 뒤에도 권한을 사용할 수 없으면 요청 창을 다시 띄우지 않고 개인정보 보호 및 보안 설정으로 안내합니다.

문제를 확인하기 전에 Applications, Downloads, 개발용 `dist` 폴더 등 실행 가능한 위치의 오래된 AirTranslate 사본을 제거하거나 보관하세요. 실제로 사용할 설치본 하나만 남기고 그 앱을 실행한 뒤 **설정 > 정보**에서 버전을 확인하세요. 오래되었거나 서명이 다른 사본은 `dev.appcaster.AirTranslate` Bundle ID가 같아도 macOS가 서로 다른 TCC 권한 정체성으로 저장할 수 있습니다.

최초 요청 뒤에도 현재 앱에서 권한을 사용할 수 없다면 **시스템 설정 > 개인정보 보호 및 보안 > 화면 및 시스템 오디오 기록**에서 현재 설치본을 확인한 뒤 앱을 종료하고 다시 실행하세요. 일반적인 `tccutil` 초기화는 필요하지 않습니다. 공개 ad-hoc 서명 빌드는 업데이트 간 TCC 권한 승계를 보장하지 않으므로 새 설치본을 다시 확인해야 할 수 있습니다.

권한이 올바른데도 Gemini Live 시작이 멈춘 것처럼 보였다면 **설정 > 정보**에서 1.7.1 이상인지 확인하세요. 1.6.2부터는 시작 중 숨겨진 설정 세그먼트 제어가 AppKit 포커스 탐색/AttributeGraph 루프에 들어가지 않습니다.

## 다운로드

최신 오픈소스 빌드는 [GitHub Releases](https://github.com/himomohi/AirTranslate/releases/latest)에서 받을 수 있습니다. DMG가 가장 쉬운 설치 경로이며, ZIP도 가벼운 압축 배포 형식으로 계속 제공합니다.

AirTranslate는 Apache-2.0 라이선스의 오픈소스 프로젝트입니다. DMG 파일은 macOS 사용자가 더 쉽게 설치할 수 있도록 추가로 제공되는 설치 패키지이며, 소스코드 공개를 대체하는 것이 아닙니다. 소스코드, 빌드 스크립트, 릴리즈 자료, LICENSE, NOTICE 파일은 모두 이 저장소에 공개되어 있습니다.

- [AirTranslate.dmg 다운로드](https://github.com/himomohi/AirTranslate/releases/latest/download/AirTranslate.dmg)
- [AirTranslate-1.7.1.zip 다운로드](https://github.com/himomohi/AirTranslate/releases/download/v1.7.1/AirTranslate-1.7.1.zip)
- [AirTranslate.dmg.sha256 다운로드](https://github.com/himomohi/AirTranslate/releases/latest/download/AirTranslate.dmg.sha256)
- [버전 히스토리 보기](Release/VERSION-HISTORY.md)

릴리즈 DMG와 ZIP은 오픈소스 배포용 ad-hoc 서명 빌드입니다. 아직 Apple notarization이 완료된 배포가 아니므로 처음 실행할 때 macOS가 "확인되지 않은 개발자" 경고를 표시할 수 있습니다. 또한 ad-hoc 서명은 업데이트 간 TCC 권한 승계를 보장하지 않습니다.

1. DMG를 열고 `AirTranslate.app`을 Applications 폴더로 드래그합니다.
2. Applications에서 `AirTranslate.app`을 Control-클릭 또는 오른쪽 클릭합니다.
3. **열기**를 선택한 뒤 macOS 경고 창에서 다시 **열기**를 선택합니다.

다운로드한 DMG는 다음처럼 체크섬을 확인할 수 있습니다.

```bash
shasum -a 256 AirTranslate.dmg
cat AirTranslate.dmg.sha256
```

## 요구 사항

- macOS 26.0 이상
- Swift 6.2 이상
- 시스템 오디오 캡처를 지원하는 Mac
- Apple Speech 및 Apple Translation 프레임워크 사용 가능 환경
- 선택 사항: GPT 모드 또는 GPT 전사용 OpenAI API 키
- 선택 사항: Gemini Live 모드용 Gemini API 키
- 선택 사항: Meta Scribe 모드용 Meta API 키

## 소스에서 빌드

앱 번들 실행:

```bash
./script/build_and_run.sh
```

빌드 후 실행 확인:

```bash
./script/build_and_run.sh --verify
```

로그 확인:

```bash
./script/build_and_run.sh --logs
```

개발 중 권한 초기화:

```bash
./script/build_and_run.sh --reset-permissions
```

SwiftPM 확인:

```bash
swift build
swift test
```

## 기본 사용법

1. 원문 언어와 번역 언어를 선택합니다.
2. 방향을 바꾸고 싶으면 가운데 언어 바꾸기 버튼을 누릅니다.
3. 콘솔 바에서 Apple 기본 모드, GPT 모드, Gemini Live 또는 Meta Scribe를 선택합니다.
4. API 기반 모드에서 안내가 나오면 설정 창에 OpenAI, Gemini 또는 Meta API 키를 입력합니다.
5. 시작 버튼을 누릅니다.
6. Mac에서 회의, 강의, 영상, 인터뷰, 스트림 오디오를 재생합니다.
7. 메인 작업 공간이나 플로팅 자막 창에서 원문과 번역을 확인합니다.
8. 중지하면 현재 기록이 저장됩니다.

## 저장된 기록

저장된 기록은 일반 텍스트 파일로 보관됩니다.

```text
~/Library/Application Support/AirTranslate/Transcripts/*.txt
```

원문과 번역을 함께 저장할 때는 `_original.txt`, `_translation.txt` 파일로 분리 저장하고, 앱의 저장소 UI에서는 하나의 묶음으로 보여줍니다.

## 프로젝트 구조

```text
Package.swift
Resources/
  AppIcon.png
  AppIcon.icns
Sources/AirTranslate/
  App/
  Models/
  Services/
  Support/
  Views/
Sources/AirTranslateCore/
Tests/
script/
  build_and_run.sh
docs/assets/
  airtranslate-readme-hero.png
```

## 핵심 구현 영역

- `SystemAudioCapture`: ScreenCaptureKit으로 Mac 시스템 오디오를 캡처합니다.
- `LiveSpeechTranscriber`: Apple Speech 기반 전사를 스트리밍합니다.
- `AppleTranslationService`: Apple Translation 작업을 격리합니다.
- `OpenAIRealtimeTranscriber`: 선택형 OpenAI 실시간 번역과 전사 이벤트를 처리합니다.
- `GeminiLiveTranslationService`: 선택형 Gemini Live Translate 웹소켓 세션을 처리합니다.
- `OpenAIAPIKeyStore` / `GeminiAPIKeyStore`: API 키를 macOS Keychain에 저장합니다.
- `TranslationSessionStore`: 캡처, 기록 상태, 번역, 저장, 음성 출력을 조율합니다.
- `SidebarView`: 언어, 처리 방식, 세션, 설정 진입점을 제공합니다.
- `CaptionBoardView`: 실시간 기록, 번역, 컨트롤, 오디오 미터를 표시합니다.
- `TranscriptLibraryView`: 저장된 기록 관리를 담당합니다.
- `FloatingCaptionWindowController`: 플로팅 자막 창 생명주기를 관리합니다.

## 라이선스

AirTranslate는 [Apache License 2.0](LICENSE)로 공개됩니다. 저작권 표기는 [NOTICE](NOTICE)에 있습니다.

AirTranslate는 독립 오픈소스 프로젝트이며 Apple, OpenAI 또는 Google과 제휴한 프로젝트가 아닙니다.
