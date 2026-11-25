# Compositor Localization

[English](../../README.md) · [简体中文](README.zh-Hans.md) · [繁體中文](README.zh-Hant.md) · [日本語](README.ja.md) · **한국어** · [Français](README.fr.md) · [Deutsch](README.de.md) · [Español](README.es.md)

Compositor Localization은 Robbie Tilton의 Compositor를 여러 언어로 제공하는 비공식 포크입니다. Compositor는 이미지 합성과 사진 편집을 위한 macOS용 오픈 소스 편집기입니다. 이 포크의 첫 릴리스는 원본 Compositor 1.7.1을 기반으로 합니다. [원본 프로젝트](https://github.com/robbietilton/Compositor)

이 포크는 Apple Silicon Mac의 macOS 앱만 개발하고 배포합니다.

## 시스템 요구 사항

- Apple Silicon이 탑재된 Mac
- macOS 26 이상
- 소스에서 빌드하려면 Xcode가 필요합니다. 원본 프로젝트의 지속적 통합 환경에서는 Xcode 26.6을 사용합니다.

## macOS용 다운로드

**macOS 26 이상을 실행하는 Apple Silicon Mac**용 [`Compositor-Localization-1.7.2-macos-arm64.dmg`](https://github.com/coderscsy/Compositor-Localization/releases/download/v1.7.2/Compositor-Localization-1.7.2-macos-arm64.dmg)를 다운로드하세요. 같은 페이지에 있는 `SHA256SUMS.txt`로 다운로드한 파일을 확인할 수 있습니다. 디스크 이미지를 열고 앱을 응용 프로그램 폴더에 복사하세요. [GitHub 미리 보기 릴리스](https://github.com/coderscsy/Compositor-Localization/releases/tag/v1.7.2)

이 앱은 임시 서명(ad hoc signing)을 사용하며 Apple의 공증을 받지 않았습니다. 처음 열 때 Gatekeeper가 실행을 차단할 수 있습니다. 아래 안내에 따라 소스에서 빌드할 수도 있습니다. [Apple의 Mac 앱 열기 안내](https://support.apple.com/ko-kr/102445)

## 주요 기능

- **레이어와 마스크.** 레이어와 폴더, 혼합 모드, 클리핑 마스크, 레이어 마스크를 지원합니다. 획, 그림자, 광선 등의 레이어 효과를 적용한 뒤에도 편집할 수 있습니다.
- **변형과 선택.** 원본 픽셀을 보존하면서 이동, 크기 조절, 회전, 뒤집기를 할 수 있습니다. 눈금자, 안내선, 격자에 맞춰 정렬할 수 있으며 선택 윤곽, 올가미, 자동 선택 도구, 개체 선택으로 영역을 지정하거나 피사체를 자동으로 선택할 수 있습니다.
- **그리기와 보정.** 브러시, 지우개, 스팟 복구 브러시, 복제 도장, 내용 인식 채우기를 지원합니다. 도형, 그레이디언트, 텍스트는 만든 뒤에도 편집할 수 있습니다.
- **조정과 필터.** 레벨, 곡선, 색조/채도, 노출, Camera Raw, 흐림, 노이즈 감소 등을 지원합니다. 실시간으로 미리 보거나 선택 영역에만 효과를 적용할 수 있습니다.
- **가져오기와 내보내기.** JPEG, PNG, HEIC, TIFF, WebP, SVG, PDF, GIF, 카메라 RAW, Photoshop PSD/PSB(8비트 RGB)를 가져올 수 있습니다. 애니메이션 GIF는 프레임 단위로 편집할 수 있습니다. PNG, JPEG, 한 페이지 PDF 또는 애니메이션 GIF는 결과를 미리 본 뒤 내보낼 수 있습니다.
- **프로젝트와 단축키.** 탭으로 여러 프로젝트를 열고 ⌘F로 명령과 도구를 검색할 수 있습니다. **편집 → 키보드 단축키**에서 단축키를 변경할 수 있습니다.
- **프로젝트 자동화.** 스크립트나 AI 에이전트로 `.comp` 프로젝트를 직접 만들고 편집할 수 있습니다. 열려 있는 프로젝트에는 변경 사항이 실시간으로 반영됩니다. [`.comp` 프로젝트 작성 안내](../writing-comp-files.md)

## 인터페이스 언어

**Compositor → 설정 → 인터페이스 언어**에서 언어를 선택한 뒤 앱을 종료하고 다시 여세요. **시스템 기본값**을 선택하면 macOS에서 Compositor에 지정한 언어를 사용합니다. 앱별 언어는 **시스템 설정 → 일반 → 언어 및 지역 → 응용 프로그램**에서 변경할 수 있습니다.

- 영어(`en`)는 원문 언어입니다. 번역이 없는 항목은 영어로 표시됩니다.
- 중국어 간체(`zh-Hans`)와 번체(`zh-Hant`)를 지원합니다. 번체에는 가능한 한 대만에서 쓰는 용어를 사용합니다.
- 일본어(`ja`), 한국어(`ko`), 프랑스어(`fr`), 독일어(`de`), 스페인어(`es`)는 미리 보기 번역입니다. 자주 쓰는 항목의 번역은 일부 확인했으며, 나머지 인터페이스에는 기계 번역을 활용한 문구가 포함되어 있습니다.

## 소스에서 빌드

각 버전의 소스 코드는 해당 Git 태그에서 받을 수 있습니다. 아래 명령은 기본 브랜치를 사용합니다.

```sh
git clone https://github.com/coderscsy/Compositor-Localization.git
cd Compositor-Localization
xcodebuild -project Compositor.xcodeproj -scheme Compositor \
  -configuration Release -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath build
open build/Build/Products/Release/Compositor.app
```

Xcode에서 `Compositor.xcodeproj`를 열고 **Compositor** 스킴을 실행할 수도 있습니다. 로컬 Debug 및 Release 빌드에는 임시 서명(ad hoc signing), 앱 샌드박스, 별도의 번들 식별자가 적용됩니다.

원본 앱과 함께 설치하려면 결과물을 `Compositor Localization.app`이라는 이름으로 응용 프로그램 폴더에 복사하세요. 로컬 빌드를 업데이트하려면 이 포크의 새 릴리스를 받아 다시 빌드하세요.

원본 개발자가 서명하고 Apple이 공증한 앱은 원본 프로젝트의 릴리스 페이지에서 받을 수 있습니다. [원본 릴리스](https://github.com/robbietilton/Compositor/releases/latest)

저장소에 포함된 `scripts/release.sh`, `scripts/publish.sh`, `appcast.xml`은 원본 프로젝트의 릴리스 절차에서 사용하는 파일입니다.

## 문제 제보와 기여

macOS 앱, 번역 또는 문서 문제를 제보할 때는 인터페이스 언어, 문제가 보이는 메뉴 또는 화면, 표시되는 문구, 앱 버전과 macOS 버전을 알려 주세요. 가능하면 제안 문구나 화면 캡처도 첨부해 주세요. [문제 제보](https://github.com/coderscsy/Compositor-Localization/issues)

풀 리퀘스트를 열어 번역을 수정할 수 있습니다. 이 포크의 문자열 카탈로그를 편집할 때는 서식 자리표시자와 단축키 기호를 유지하고 실제 앱에서 수정한 문구를 확인해 주세요. [문자열 카탈로그](../../Compositor/Resources/Localizable.xcstrings)

## 라이선스

이 포크에는 MIT 라이선스가 적용됩니다. 원본 저작권은 Wonder Assembly LLC에 있습니다. [MIT 라이선스](../../LICENSE)

볼류메트릭 라이트에 사용하는 깊이 추정 모델 DepthMini는 Depth Anything V2 Small(Apache-2.0)을 증류했으며, torchvision의 ImageNet 학습 MobileNetV3 가중치(BSD-3-Clause)를 초기값으로 사용했습니다. 모델은 볼류메트릭 라이트를 처음 열 때 다운로드됩니다. [Depth Anything V2](https://github.com/DepthAnything/Depth-Anything-V2)
