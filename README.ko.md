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

AirTranslate **1.16.0/build1160**은 Apple 번역 옵션, 실험적 Jev 후보 선택, 캡처를 바로 시작하는 플로팅 전용 모드를 추가합니다.

- **플로팅 전용 시작과 제어:** 대기 중이면 캡처를 시작하고 일시정지 중이면 재개한 뒤, 실행 상태가 되면 메인 창을 최소화합니다. 시작에 실패하면 메인 제어 화면을 유지합니다. 메뉴 막대와 앱 메뉴에서도 시작·중지와 일시정지·재개를 사용할 수 있습니다.
- **이전 자막 표시:** 현재 자막과 함께 직전 자막 한 블록을 최대 두 줄로 8초 동안 표시하며 동작 줄이기 설정을 따릅니다.
- **플로팅 자막 렌더링:** 제한된 크기의 텍스트 레이아웃을 재사용하고 메인 창 최소화 시 메인 자막 표시 작업을 줄입니다. 음성 인식과 번역은 계속됩니다.
- **Apple 전사·번역 흐름:** 주변 인식 문맥을 활용하고 중지 시 마지막 발화를 보존하며, 오래된 번역 작업이 새 자막을 덮어쓰지 않도록 처리합니다.
- **실험적 Jev 후보 선택:** 기본값은 꺼짐입니다. Apple 전사와 번역을 함께 사용할 때 확정 인식 후보 중 하나를 골라 번역할 수 있습니다. 활성화하면 후보 텍스트와 앞선 최대 6개 전사 구간(1,000 UTF-8 바이트)을 Keychain에 저장한 사용자 키로 TypeSafe에 직접 전송합니다. API 사용량과 요청당 최대 1.2초의 응답 대기가 추가됩니다. 후보 없음·불확실·오류·시간 초과 시 원문을 유지하며 정확도 향상은 보장하지 않습니다. [설정과 데이터 처리](docs/apple-translation-options.md).
- **Apple 번역 품질과 용어 보존:** macOS 26.4 이상에서 실시간(기본값) 또는 품질 우선을 선택하고 표기를 유지할 용어를 등록할 수 있습니다. 품질 우선은 더 오래 걸릴 수 있으며 Apple 모델 가용성에 따라 달라집니다. 실패하면 해당 언어쌍은 앱 재시작까지 실시간 번역을 사용합니다. 등록 용어가 바뀌면 해당 구간을 원문으로 유지합니다. Apple 텍스트 번역에 적용됩니다.
- **macOS 27 오디오 입력 호환성:** 기존 16 kHz 모노 경로를 유지하면서 다른 PCM 입력 형식을 Apple 음성 인식에 맞게 변환합니다.
- **소스 빌드 요구사항:** macOS 27 SDK가 포함된 Xcode 27과 Swift 6.4 이상이 필요합니다. 배포 앱은 macOS 26 이상에서 실행됩니다.

설정 > API 키 > Qwen에 **Alibaba Cloud 싱가포르 API 키**를 입력하세요. Qwen3.8 LiveTranslate는 워크스페이스 ID도 필요하지만 Qwen Audio 3.1 Realtime Plus와 Filetrans는 키만 사용합니다. 키는 macOS Keychain의 전용 항목에 저장하며, 캡처를 시작하면 선택한 실시간 오디오를 Alibaba Cloud 싱가포르로 직접 전송합니다. 설정 > 일반에서 기존 기본 모델 `qwen3.8-livetranslate-flash-realtime` 또는 `qwen-audio-3.1-realtime-plus`를 선택할 수 있습니다. Qwen Audio 3.1 Realtime Plus는 AirTranslate의 번역 지시를 받는 양방향 실시간 음성 대화 모델입니다. Qwen3.8 LiveTranslate는 전용 실시간 번역 모델입니다. **음성 출력은 선택 사항이며 처음에는 꺼져 있습니다**. Qwen Audio 요금은 Model Studio에서 확인하세요.

설정 > 일반의 `qwen-audio-3.1-asr-flash-filetrans`는 비동기 파일 전사 도구입니다. **공개 HTTPS 오디오 URL만 지원**하며 QwenCloud가 URL에서 오디오를 가져옵니다. 이 흐름은 로컬 파일을 업로드하지 않습니다. 제공자에게 보낼 권한이 있는 오디오만 공유하세요. [Qwen 설정·요금 안내](docs/qwen-livetranslate.md)를 참고하세요. 실제 계정 인증·과금·번역·전사 품질·지연은 미검증입니다.

**API 키 상태를 반영하는 모드 선택기**는 키가 없는 제공자를 회색으로 표시하고 각 행에 설정 바로가기를 제공합니다. 정보 아이콘에서 모델과 요금 기준을 확인할 수 있습니다. **OpenAI 음성은 번역과 원문 전사를 하나로 통합**하고 언어·출력 선호를 유지합니다. 메인 선택기에서 Apple, OpenAI, Gemini, Qwen, Nari의 모델을 기능별 설명과 함께 고를 수 있으며, 번역 음성 모델은 별도 선택기에서 선택합니다.

**플로팅 자막은 글자만 표시**합니다. 창 배경·테두리·도구막대·상태 문구·hover 리사이즈 조작은 표시하지 않습니다. 다섯 글자 스타일과 글꼴·색상·폭·줄 간격·배치·샘플 미리보기는 설정에서 조절하고, 메인 화면·메뉴바·⌘⇧C로 표시 여부를 바꿉니다.

**Qwen 중지 전에 최종 자막 수신을 기다립니다**. 빈 최종 응답은 임시 자막을 철회하고, 주기적 저장을 포함한 Qwen 기록에는 확정 결과만 남깁니다. Apple 기본 모드와 기록 파일 저장의 선택 사용 정책은 유지합니다.

**번역 음성 출력 모델을 선택할 수 있습니다**. 설정 또는 메인 화면의 별도 번역 음성 선택기에서 Apple 시스템 음성, Gemini 3.8 Flash TTS, Flash-Lite TTS 또는 MAI Voice 2.1·Flash를 고릅니다. 실시간 모드에서도 선택은 저장되지만 텍스트 번역에서만 사용하며, 실시간 제공자는 자체 음성을 계속 사용합니다. Gemini TTS는 안정된 번역 텍스트만 Google에 보냅니다.

## 다운로드

현재 공개 최신 릴리즈: **v1.16.0**.

- [AirTranslate.dmg 다운로드](https://github.com/himomohi/AirTranslate/releases/latest/download/AirTranslate.dmg)
- [AirTranslate-1.16.0.zip 다운로드](https://github.com/himomohi/AirTranslate/releases/download/v1.16.0/AirTranslate-1.16.0.zip)
- [AirTranslate.dmg.sha256 다운로드](https://github.com/himomohi/AirTranslate/releases/latest/download/AirTranslate.dmg.sha256)
- [버전 이력 보기](Release/VERSION-HISTORY.md)

오픈소스 DMG와 ZIP은 ad-hoc 서명 빌드이며 Apple 공증을 받지 않았습니다. 첫 실행이 차단되면 [설치 안내](docs/GETTING-STARTED.md)를 확인하세요. DMG 해시는 다음처럼 확인합니다.

```bash
shasum -a 256 AirTranslate.dmg
cat AirTranslate.dmg.sha256
```


## 실제 앱

![AirTranslate workspace](docs/assets/airtranslate-workspace.jpg)

캡처 시작 전의 AirTranslate 작업 공간입니다.

AirTranslate는 원문 기록과 번역문을 한 작업 공간에 유지하며, 다른 앱을 보거나 들을 때 플로팅 자막으로 볼 수 있습니다.

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
- 글자만 표시하는 플로팅 자막과 설정의 다섯 스타일·글꼴·색상·폭·줄 간격·배치·미리보기·저장·초기화.
- 기록 파일 저장은 기본으로 꺼져 있습니다. 일반 `.txt` 파일을 Application Support에 남기려면 **Save Transcript Files**를 켭니다.
- 영어, 한국어, 일본어, 중국어 간체 앱 언어.

## 엔진

| 엔진 | 역할 | 필요 항목 |
| --- | --- | --- |
| Apple 기본 모드 | 기본 로컬 우선 전사와 번역입니다. | 없음 |
| OpenAI 음성 | 하나의 제공자 안에서 번역 또는 원문 전사를 선택합니다. 출력 아이콘으로 `gpt-realtime-translate`·`gpt-live-transcribe`를 전환하고 툴팁에서 모델과 요금을 확인합니다. | OpenAI |
| Gemini Live | 문서화된 실시간 번역 모델 또는 자동 음성 언어 감지를 지원하는 별도 원문 전사 모델을 선택합니다. | Gemini |
| Meta Scribe | AirTranslate 번역 전 단계의 화자 라벨 포함 다국어 전사입니다. | Meta |
| Azure MAI | 5초 REST 구간 MAI-Transcribe-2 또는 중간 자막을 제공하는 MAI-Transcribe-2-Streaming과 Apple 번역. | 리소스 키와 엔드포인트; 스트리밍은 Foundry 배포 이름도 필요 |
| Nari STT | Nari Qwen3-ASR 원문 전사입니다. 마이크나 Mac 오디오를 사용할 수 있습니다. | Nari |
| Grok STT | 마이크나 Mac 오디오의 Grok Voice Transcribe 2.0 원문 전사입니다. | SpaceXAI (xAI) |
| Qwen LiveTranslate | Qwen3.8은 전용 실시간 번역 모델입니다. Qwen Audio 3.1 Realtime Plus는 AirTranslate의 번역 지시를 받는 전이중 실시간 음성 대화 모델이며 음성 응답을 제공할 수 있습니다. | Alibaba Cloud 싱가포르 API 키; Qwen3.8은 워크스페이스 ID도 필요 |

Qwen Audio 3.1 ASR Flash Filetrans는 설정 > 일반에서 공개 HTTPS 오디오 URL을 비동기 전사합니다. QwenCloud가 URL의 오디오를 가져오며, 이 기능은 로컬 오디오 파일을 업로드하지 않습니다.

Grok STT는 1.10.0부터 포함됩니다. 최초 선택은 원문 전사이며 본인의 xAI API 키를 사용합니다. 설정, 언어 처리와 검증 범위는 [Grok STT 참고](docs/grok-stt.md)를 확인하세요.

Nari STT는 1.9.0의 선택형 엔진입니다. Nari 최초 선택은 원문 전사로 시작하고, 원문 언어가 사용 가능할 때 Apple Translation으로 번역할 수 있습니다. Nari의 현재 GA STT 모델 ID는 qwen3-asr-fast와 qwen3-asr이며, 가용성·사용량 제한·유료 크레딧 조건은 Nari 제공자 문서와 계정 상태를 따릅니다. 자세한 내용은 [docs/nari-stt.md](docs/nari-stt.md)에 요약했습니다.

Nari는 한국어를 포함한 입력 언어 직접 선택과 음성 언어 자동 감지를 지원합니다.

Nari를 새로 선택하면 크레딧이 필요한 GA Fast 모델을 사용합니다. 저장된 Free Public Beta 모델 선택은 보존하고 시작을 차단하며, 유료 모델로 자동 전환하지 않습니다. 설정 > 일반에서 과금 안내를 확인한 뒤 GA 모델을 직접 선택하면 Nari STT를 다시 시작할 수 있습니다.

## 플로팅 자막

플로팅 자막은 화면 위에 원문·번역 글자만 표시합니다. 창 배경·테두리·도구막대·상태 문구·리사이즈 표시는 마우스를 올려도 나타나지 않으며, 자막이 없으면 아무것도 표시하지 않습니다. 조작은 설정·메인 화면·메뉴바에서 하고, ⌘⇧C로 자막을 표시하거나 숨깁니다.

기본·영화·강의·고대비·밝은 화면용의 5개 글자 스타일과 글꼴 4종, 굵기·줄 간격·그림자/윤곽선·글자 색상·정렬·줄 수·번역 우선 배치를 제공합니다. 밝은/어두운 예시 화면에서 실제 18–72pt 크기로 미리 볼 수 있고, 녹음 없이 샘플 자막을 띄울 수 있습니다. 가로 폭과 항상 위 표시는 설정에서 조절합니다. 기존 외형 설정은 복원하며, 예전 배경 설정값이 남아 있어도 창 배경은 표시하지 않습니다.

## Microsoft MAI 오디오 (1.15.0)

Azure MAI에서 **MAI-Transcribe-2-Streaming**을 선택하면 중간 원문 자막을 표시합니다. API 키 설정에 Microsoft Foundry 리소스 엔드포인트(`https://<resource>.services.ai.azure.com`), 해당 리소스 키와 배포 이름을 입력하세요. 오디오는 3초마다, 일시정지·중지 시 확정하고 확정 텍스트는 Apple로 번역합니다. 기존 5초 구간 MAI-Transcribe-2도 선택할 수 있습니다.

번역 음성 출력에서 **MAI-Voice-2.1** 또는 **MAI-Voice-2.1-Flash**를 선택하고 **OpenRouter** 키를 저장하세요. 번역 언어와 제공자의 음성 목록에 맞는 음성을 사용합니다. 한국어를 지원하며 일본어는 현재 지원하지 않습니다. 음성 생성에는 번역 텍스트만 전송하며 제공자 사용료는 별도입니다. [설정 안내](docs/microsoft-mai-audio.md).

Azure 캡처를 중지하면 제한 시간 안에서 마지막 확정 번역을 기다립니다. 빈 Azure 최종 결과는 메인 화면과 플로팅 자막의 임시 텍스트를 지웁니다.

## API 키

API 키 화면은 **OpenAI**, **Gemini**, **Meta**, **Azure**, **Nari**, **SpaceXAI (xAI)** · **Alibaba Cloud (Qwen)** · **OpenRouter** · **TypeSafe (Jev)**를 하나의 서비스 목록에서 관리합니다. 각 행은 설정/준비 상태, 서비스 아이콘, 키 발급 콘솔 링크, 그리고 설정된 키가 서비스 권한 검증을 의미하지 않는다는 정보 팝오버를 보여 줍니다.

키는 macOS Keychain에 저장됩니다. AirTranslate는 계정 시스템, 개발자 운영 중계 서버, 하드코딩된 제공자 키를 포함하지 않습니다.

Gemini 키는 Gemini Live와 선택형 Gemini 번역 음성 출력에서 함께 사용합니다. Gemini TTS를 선택해도 실제 계정 권한, 과금, 품질, 지연 검증을 의미하지 않습니다.

## 개인정보

- Apple 기본 모드는 macOS 프레임워크와 Apple 언어 자산을 사용합니다.
- GPT, Gemini, Meta, Azure, Nari, Grok, Qwen 모드는 선택한 기능에 필요한 오디오나 텍스트만 사용자의 키로 해당 제공자에게 직접 보냅니다. Gemini TTS는 사용자가 Gemini 음성 모델을 선택한 뒤 안정된 번역 텍스트만 전송합니다.
- 저장된 기록은 파일 저장을 켰을 때만 사용자 Mac의 일반 텍스트 파일로 남습니다.
- 더 긴 제공자 및 저장 안내는 [Release/PRIVACY-NOTICE.md](Release/PRIVACY-NOTICE.md)를 참고하세요.

## 요구 사항

- macOS 26.0 이상
- 소스 빌드용 Swift 6.4 이상
- 시스템 오디오 캡처를 지원하는 Mac
- Apple Speech와 Apple Translation 프레임워크 사용 가능 환경
- 선택 사항: OpenAI, Gemini, Meta, Azure Speech, Nari, xAI 또는 Alibaba Cloud 제공자 키

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

AirTranslate는 독립 오픈소스 프로젝트이며 Apple, OpenAI, Google, Meta, Microsoft, Nari 또는 SpaceXAI(xAI), Alibaba Cloud와 제휴한 프로젝트가 아닙니다.
