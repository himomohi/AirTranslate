<p align="center">
  <img src="docs/assets/airtranslate-readme-hero.png" alt="AirTranslate" width="720">
</p>

# AirTranslate

회의, 영상, 강의, 인터뷰, 스트림을 위한 Mac 오디오 실시간 자막 및 번역 앱.

<p align="center">
  <a href="https://github.com/himomohi/AirTranslate/releases/latest/download/AirTranslate.dmg"><img alt="Download AirTranslate.dmg" src="https://img.shields.io/badge/Download-AirTranslate.dmg-2EA44F?style=for-the-badge&logo=apple&logoColor=white"></a>
  <a href="https://github.com/himomohi/AirTranslate/releases/latest"><img alt="Latest public release" src="https://img.shields.io/github/v/release/himomohi/AirTranslate?style=for-the-badge&label=Latest"></a>
  <a href="LICENSE"><img alt="License: Apache 2.0" src="https://img.shields.io/badge/License-Apache%202.0-blue?style=for-the-badge"></a>
</p>

<p align="center">
  <a href="README.md">English</a> ·
  한국어 ·
  <a href="README.ja.md">日本語</a> ·
  <a href="README.zh-CN.md">中文</a> ·
  <a href="CHANGELOG.md">변경 이력</a> ·
  <a href="docs/GETTING-STARTED.md">시작 안내</a>
</p>

AirTranslate는 Mac에서 재생되는 소리를 캡처해 실시간으로 전사하고, 번역 흐름을 선택하면 번역하며, 필요하면 다른 앱 위에 플로팅 자막을 유지합니다. Apple 기본 모드는 계속 로컬 우선 기본 경로입니다. 클라우드 엔진은 선택형이며 해당 제공자 키를 설정하면 사용할 수 있습니다.

AirTranslate **1.9.0/build190**은 선택형 Nari STT와 새 API 키 화면을 추가합니다.

## 다운로드

현재 공개 최신 릴리즈: **v1.9.0**.

- [AirTranslate.dmg 다운로드](https://github.com/himomohi/AirTranslate/releases/latest/download/AirTranslate.dmg)
- [AirTranslate-1.9.0.zip 다운로드](https://github.com/himomohi/AirTranslate/releases/download/v1.9.0/AirTranslate-1.9.0.zip)
- [AirTranslate.dmg.sha256 다운로드](https://github.com/himomohi/AirTranslate/releases/latest/download/AirTranslate.dmg.sha256)
- [버전 이력 보기](Release/VERSION-HISTORY.md)

오픈소스 DMG와 ZIP은 ad-hoc 서명 빌드이며 Apple 공증을 받지 않았습니다. 첫 실행이 차단되면 [설치 안내](docs/GETTING-STARTED.md)를 확인하세요. DMG 해시는 다음처럼 확인합니다.

```bash
shasum -a 256 AirTranslate.dmg
cat AirTranslate.dmg.sha256
```

## 실제 앱

![AirTranslate workspace](docs/assets/airtranslate-workspace.jpg)

캡처 시작 전의 1.9.0 로컬 빌드 화면입니다.

AirTranslate는 원문 기록과 번역문을 한 작업 공간에 유지하며, 다른 앱을 보거나 들을 때 플로팅 자막으로 볼 수 있습니다.

<details>
<summary>API 키 화면</summary>

![AirTranslate API Keys](docs/assets/airtranslate-api-keys.jpg)

</details>

## 3단계 시작

1. 앱을 설치하고 실제로 사용할 사본을 실행한 뒤 macOS가 요청하는 화면 기록과 시스템 오디오 녹음 권한을 허용합니다.
2. 원문과 번역 언어를 고른 다음 콘솔에서 Apple 기본 모드 또는 선택형 엔진을 선택합니다.
3. **시작**을 누르고 Mac 오디오를 재생하거나 마이크 입력을 선택한 뒤 기본 작업 공간이나 플로팅 자막 창에서 읽습니다.

API 기반 엔진은 **설정 > API 키**에서 키를 설정한 뒤 사용할 수 있습니다. 키가 설정됨은 AirTranslate에 로컬 제공자 설정이 있다는 뜻이며, 서비스 이용 권한은 세션을 시작할 때 확인됩니다.

## 핵심 기능

- ScreenCaptureKit 기반 시스템 오디오 캡처와 내장, Bluetooth, AirPods 마이크 입력.
- 기본 로컬 우선 경로인 Apple Speech 전사와 Apple Translation 번역.
- 번역 없이 원문 자막만 보는 전사 전용 모드.
- 플로팅 자막, 저장된 기록 보관함, 선택형 번역 음성, 원클릭 언어 바꾸기.
- 기록 파일 저장은 기본으로 꺼져 있습니다. 일반 `.txt` 파일을 Application Support에 남기려면 **Save Transcript Files**를 켭니다.
- 영어, 한국어, 일본어, 중국어 간체 앱 언어.

## 엔진

| 엔진 | 역할 | 필요 항목 |
| --- | --- | --- |
| Apple 기본 모드 | 기본 로컬 우선 전사와 번역입니다. | 없음 |
| GPT 모드 | OpenAI Realtime 기반 실시간 번역 출력입니다. | OpenAI |
| GPT 전사 | OpenAI 기반 원문 자막입니다. | OpenAI |
| Gemini Live | Gemini 실시간 번역 또는 자동 음성 언어 감지 원문 전사입니다. | Gemini |
| Meta Scribe | AirTranslate 번역 전 단계의 화자 라벨 포함 다국어 전사입니다. | Meta |
| Azure MAI | Apple Translation 자막과 함께 쓰는 프리뷰 클라우드 전사입니다. | Azure Speech 키와 엔드포인트 |
| Nari STT | 1.9.0 소스에 준비된 Nari Qwen3-ASR 원문 전사입니다. 마이크나 Mac 오디오를 사용할 수 있습니다. | Nari |

Nari STT는 1.9.0의 선택형 엔진입니다. Nari 최초 선택은 원문 전사로 시작하고, 원문 언어가 사용 가능할 때 Apple Translation으로 번역할 수 있습니다. Nari의 현재 GA STT 모델 ID는 qwen3-asr-fast와 qwen3-asr이며, 가용성·사용량 제한·유료 크레딧 조건은 Nari 제공자 문서와 계정 상태를 따릅니다. 자세한 내용은 [docs/nari-stt.md](docs/nari-stt.md)에 요약했습니다.

Nari는 한국어를 포함한 입력 언어 직접 선택과 음성 언어 자동 감지를 지원합니다.

Nari를 새로 선택하면 크레딧이 필요한 GA Fast 모델을 사용합니다. 저장된 Free Public Beta 모델 선택은 보존하고 시작을 차단하며, 유료 모델로 자동 전환하지 않습니다. 설정 > 일반에서 과금 안내를 확인한 뒤 GA 모델을 직접 선택하면 Nari STT를 다시 시작할 수 있습니다.

## API 키

1.9.0 API 키 화면은 **OpenAI**, **Gemini**, **Meta**, **Azure**, **Nari**를 하나의 서비스 목록에서 관리합니다. 각 행은 설정/준비 상태, 서비스 아이콘, 키 발급 콘솔 링크, 그리고 설정된 키가 서비스 권한 검증을 의미하지 않는다는 정보 팝오버를 보여 줍니다.

키는 macOS Keychain에 저장됩니다. AirTranslate는 계정 시스템, 개발자 운영 중계 서버, 하드코딩된 제공자 키를 포함하지 않습니다.

## 개인정보

- Apple 기본 모드는 macOS 프레임워크와 Apple 언어 자산을 사용합니다.
- GPT, Gemini, Meta, Azure, Nari 모드는 선택한 기능에 필요한 오디오나 텍스트만 사용자의 키로 해당 제공자에게 직접 보냅니다.
- 저장된 기록은 파일 저장을 켰을 때만 사용자 Mac의 일반 텍스트 파일로 남습니다.
- 더 긴 제공자 및 저장 안내는 [Release/PRIVACY-NOTICE.md](Release/PRIVACY-NOTICE.md)를 참고하세요.

## 요구 사항

- macOS 26.0 이상
- 소스 빌드용 Swift 6.2 이상
- 시스템 오디오 캡처를 지원하는 Mac
- Apple Speech와 Apple Translation 프레임워크 사용 가능 환경
- 선택 사항: OpenAI, Gemini, Meta, Azure Speech 또는 Nari 제공자 키

## 문서

- [시작 안내](docs/GETTING-STARTED.md)
- [개발 안내](docs/DEVELOPMENT.md)
- [Nari STT 참고](docs/nari-stt.md)
- [변경 이력](CHANGELOG.md)
- [버전 이력](Release/VERSION-HISTORY.md)

<details>
<summary>소스에서 빌드</summary>

```bash
./script/build_and_run.sh
./script/build_and_run.sh --verify
swift test
```

더 많은 명령은 [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md)에 있습니다.

</details>

## 기여

사용자에게 보이는 릴리즈 이력은 [CHANGELOG.md](CHANGELOG.md)에 보관합니다. README는 과거 릴리즈 노트를 반복하기보다 현재 제품, 다운로드 경로, 제공자 경계를 설명합니다.

## 라이선스

AirTranslate는 [Apache License 2.0](LICENSE)로 공개됩니다. 저작권 표기는 [NOTICE](NOTICE)에 있습니다.

AirTranslate는 독립 오픈소스 프로젝트이며 Apple, OpenAI, Google, Meta, Microsoft 또는 Nari와 제휴한 프로젝트가 아닙니다.
