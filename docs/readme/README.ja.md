# Compositor Localization

[English](../../README.md) · [简体中文](README.zh-Hans.md) · [繁體中文](README.zh-Hant.md) · **日本語** · [한국어](README.ko.md) · [Français](README.fr.md) · [Deutsch](README.de.md) · [Español](README.es.md)

Compositor Localization は、Robbie Tilton が開発するオープンソースの画像合成・写真編集アプリ [Compositor](https://github.com/robbietilton/Compositor) の非公式な多言語フォークです。最初のリリースは本家の Compositor 1.7.1 をベースにしています。

## 動作環境

このプロジェクトは macOS 専用です。Appleシリコン搭載の Mac と macOS 26 以降が必要です。ソースからビルドするには Xcode が必要です。本家の CI では Xcode 26.6 を使用しています。

## macOS 版のダウンロード

**Appleシリコン搭載の Mac（macOS 26 以降）** 用の [`Compositor-Localization-1.7.2-macos-arm64.dmg`](https://github.com/coderscsy/Compositor-Localization/releases/download/v1.7.2/Compositor-Localization-1.7.2-macos-arm64.dmg) をダウンロードしてください。同じページの `SHA256SUMS.txt` でダウンロードしたファイルを検証できます。ディスクイメージを開き、アプリを「アプリケーション」フォルダにコピーします。[GitHub のプレリリース](https://github.com/coderscsy/Compositor-Localization/releases/tag/v1.7.2)

このアプリはアドホック署名を使用しており、Apple の公証は受けていません。初回起動時に Gatekeeper によってブロックされることがあります。下記の手順でソースからビルドすることもできます。[Apple の Mac アプリ起動ガイド](https://support.apple.com/ja-jp/102445)

## 主な機能

- レイヤー、フォルダ、描画モード、レイヤーマスク、クリッピングマスク、調整レイヤー。
- 元の画像を保持したまま移動、拡大・縮小、回転、反転。ガイド、スナップ、レイヤーの整列にも対応。
- 長方形・楕円形選択、なげなわ、自動選択、被写体選択、コンテンツに応じた塗りつぶし。
- ブラシ、消しゴム、スポット修復ブラシ、コピースタンプ、文字、シェイプ、グラデーション。
- Camera Raw、トーンカーブ、レベル補正、色相・彩度、ぼかし、シャープ、ノイズ軽減、背景の削除。
- プロジェクトをタブで管理し、`⌘F` でコマンドとツールを検索。キーボードショートカットも変更できます。
- PNG、JPEG、TIFF、PDF、アニメーション GIF、カメラ RAW、Photoshop PSD・PSB などを読み込めます。書き出しでは PNG、JPEG、PDF、アニメーション GIF などに対応します。

## 表示言語

**Compositor → 設定 → インターフェイスの言語**で選択し、Compositor を終了してから開き直します。**システムのデフォルト**を選ぶと、macOS が Compositor に適用する言語が使われます。アプリごとの言語は **システム設定 → 一般 → 言語と地域 → アプリケーション**でも設定できます。

英語 (`en`) に加えて、以下の7言語に対応しています。翻訳がない項目は英語で表示されます。

- 簡体字中国語 (`zh-Hans`)
- 繁体字中国語 (`zh-Hant`)
- 日本語 (`ja`)
- 韓国語 (`ko`)
- フランス語 (`fr`)
- ドイツ語 (`de`)
- スペイン語 (`es`)

日本語、韓国語、フランス語、ドイツ語、スペイン語はプレビュー版です。よく使う操作項目は一部確認済みで、その他の箇所には機械翻訳を活用しています。繁体字中国語では、可能な範囲で台湾の用語を使用しています。

## ソースからビルド

バージョンごとのソースコードは、対応する Git タグから取得できます。以下のコマンドでは既定ブランチを取得します。特定のリリースをビルドする場合は、ビルド前に対応するタグに切り替えてください。

```sh
git clone https://github.com/coderscsy/Compositor-Localization.git
cd Compositor-Localization
xcodebuild -project Compositor.xcodeproj -scheme Compositor \
  -configuration Release -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath build
open build/Build/Products/Release/Compositor.app
```

Xcode で `Compositor.xcodeproj` を開き、**Compositor** スキームを実行することもできます。Debug と Release のローカルビルドにはアドホック署名、App Sandbox、専用のバンドル識別子が使われます。本家のアプリと両方を「アプリケーション」フォルダに置く場合は、ビルドしたアプリを `Compositor Localization.app` という名前でコピーしてください。

ローカルビルドを更新するには、このフォークの新しいリリースからビルドし直してください。本家の署名済み・公証済みアプリは [本家のリリースページ](https://github.com/robbietilton/Compositor/releases/latest) で入手できます。

## 問題の報告と翻訳への協力

翻訳漏れ、不自然な表現、文字の見切れなどは、このフォークの [Issues](https://github.com/coderscsy/Compositor-Localization/issues) に報告してください。次の情報があると再現しやすくなります。

- 選択している表示言語
- 該当するメニュー、パネル、画面と、そこに表示される文言
- Compositor Localization と macOS のバージョン
- 可能であれば、再現手順、期待する文言、スクリーンショット

[翻訳カタログ](../../Compositor/Resources/Localizable.xcstrings)の修正は、このフォークへのプルリクエストでも受け付けています。対象の言語と、変更した文言が表示される場所を記載してください。

## ライセンス

このフォークは [MIT ライセンス](../../LICENSE) に基づき公開されています。元のアプリは [Robbie Tilton による Compositor](https://github.com/robbietilton/Compositor) で、原著作権は Wonder Assembly LLC に帰属します。
