# Microsoft MAI 오디오 설정

AirTranslate는 MAI-Transcribe-2-Streaming 전사와 MAI-Voice-2.1·MAI-Voice-2.1-Flash 번역 음성을 선택형 모델로 제공합니다.

| 모델 | 선택 위치 | 필요한 설정 |
| --- | --- | --- |
| MAI-Transcribe-2-Streaming | 메인 모델 선택 또는 설정 > 일반 > Azure MAI | Microsoft Foundry 리소스 엔드포인트·키·배포 이름 |
| MAI-Voice-2.1 | 번역 음성 모델 | OpenRouter API 키 |
| MAI-Voice-2.1-Flash | 번역 음성 모델 | OpenRouter API 키 |

## 스트리밍 전사

API 키 설정의 **Azure / Microsoft Foundry**에서 스트리밍 모델을 고른 다음, 모델을 배포한 리소스의 `https://<resource>.services.ai.azure.com` 엔드포인트와 실제 배포 이름을 입력합니다. 키도 같은 리소스에서 발급한 값이어야 합니다. URL에 키나 경로를 넣지 않습니다. 기존 MAI-Transcribe-2 REST 모델은 Azure Speech 엔드포인트를 별도로 유지합니다.

선택한 입력의 16 kHz 모노 오디오를 스트리밍으로 보내 중간 원문 자막을 표시합니다. 서버가 자동으로 발화를 확정하지 않으므로 AirTranslate는 3초마다, 일시정지·중지할 때 남은 오디오를 확정합니다. 확정 결과는 중복 없이 저장하고 Apple로 번역합니다. 세션은 제공자의 1시간 제한과 대기열 제한을 따릅니다.

## 번역 음성

API 키 설정의 **OpenRouter**에서 키를 저장하고, 번역 음성 모델에서 MAI-Voice-2.1 또는 Flash를 선택합니다. 설정 > 출력 > MAI 음성에서 자동 음성을 사용하거나 번역 언어에 맞는 음성을 직접 선택할 수 있습니다. 음성 ID는 제공자의 공개 모델 카탈로그에서 확인하며, 두 모델의 음성 ID를 구분합니다.

한국어를 포함한 23개 언어가 카탈로그에 등록되어 있습니다. 일본어는 현재 음성 목록에 없으며, 해당 언어나 사용할 수 없는 음성을 선택하면 안내를 표시하고 자막을 계속 제공합니다. MAI 전사의 언어 지원과 MAI 음성의 언어 지원은 다릅니다.

번역 음성에는 확정된 번역 텍스트만 전송합니다. 전사와 음성 생성의 사용료는 별도이며, 키 저장이나 모델 선택만으로 계정 권한·잔액·배포 가용성이 확인되는 것은 아닙니다. OpenAI·Gemini·Qwen의 실시간 번역 모드에서는 제공자 자체 음성을 사용합니다.

## 공식 안내

- [Microsoft Foundry MAI 스트리밍 전사](https://learn.microsoft.com/en-us/azure/ai-services/speech-service/mai-transcribe-2-streaming-realtime)
- [OpenRouter 음성 생성 API](https://openrouter.ai/docs/guides/overview/multimodal/tts)
- [MAI Voice 2.1](https://openrouter.ai/microsoft/mai-voice-2.1)
- [MAI Voice 2.1 Flash](https://openrouter.ai/microsoft/mai-voice-2.1-flash)
