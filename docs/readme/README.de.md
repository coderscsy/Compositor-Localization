# Compositor Localization

[English](../../README.md) · [简体中文](README.zh-Hans.md) · [繁體中文](README.zh-Hant.md) · [日本語](README.ja.md) · [한국어](README.ko.md) · [Français](README.fr.md) · **Deutsch** · [Español](README.es.md)

Compositor Localization ist ein inoffizieller mehrsprachiger Fork von [Robbie Tiltons Compositor](https://github.com/robbietilton/Compositor), einem quelloffenen Programm für Bildmontage und Fotobearbeitung unter macOS. Die erste Version des Forks basiert auf Compositor 1.7.1.

## Systemvoraussetzungen

Dieses Projekt ist ausschließlich für macOS bestimmt. Es setzt einen Mac mit Apple-Chip und macOS 26 oder neuer voraus. Zum Bauen aus dem Quellcode wird Xcode benötigt. Die CI des Originalprojekts verwendet Xcode 26.6.

## Download für macOS

Lade [`Compositor-Localization-1.8.0-macos-arm64.dmg`](https://github.com/coderscsy/Compositor-Localization/releases/download/v1.8.0/Compositor-Localization-1.8.0-macos-arm64.dmg) für einen **Mac mit Apple-Chip und macOS 26 oder neuer** herunter. Mit `SHA256SUMS.txt` auf derselben Seite kannst du die heruntergeladene Datei prüfen. Öffne das Disk-Image und kopiere die App in den Ordner „Programme“. [Vorschauversion auf GitHub](https://github.com/coderscsy/Compositor-Localization/releases/tag/v1.8.0)

Die App ist ad hoc signiert und wurde nicht von Apple notarisiert. Gatekeeper kann den ersten Start blockieren. Du kannst die App auch wie unten beschrieben aus dem Quellcode bauen. [Apple-Anleitung zum Öffnen von Mac-Apps](https://support.apple.com/de-de/102445)

## Funktionen

- **Neu in v1.8.0:** Import von Photoshop-`.abr`-Pinseln mit lokaler Bibliothek, Ebenensperre, Flächendeckkraft (Fill), Farbbereichs-Überblendung (Blend If), Abgeflachte Kante und Relief, Zeichenstift und Bézier-Pfade, Vektormasken und boolesche Operationen, vertikaler/verkrümmter Text und Text auf Pfad, Gitter-Verkrümmung (Warp), Maskierungsmodus (Q) und Auswählen und maskieren, Protokoll-/Info-/Histogramm-Bedienfelder, verlustfreier WebP- & HEIC-Export sowie originalgetreuer PSD-Austausch. [Änderungsprotokoll](../../CHANGELOG.md)
- Ebenen, Ordner, Mischmodi, Ebenenmasken, Schnittmasken und Einstellungsebenen.
- Nichtdestruktives Verschieben, Skalieren, Drehen und Spiegeln. Hilfslinien, Einrasten und Ausrichten von Ebenen.
- Rechteckige und elliptische Auswahl, Lasso, Zauberstab, Motivauswahl und inhaltsbasiertes Füllen.
- Pinsel, Radiergummi, Bereichsreparatur-Pinsel, Kopierstempel, Text, Formen und Verläufe.
- Camera Raw, Gradationskurven, Tonwertkorrektur, Farbton und Sättigung, Weichzeichnen, Schärfen, Rauschreduzierung und Entfernen des Hintergrunds.
- Projekte in Tabs, Suche nach Befehlen und Werkzeugen mit `⌘F` sowie anpassbare Tastaturkurzbefehle.
- Import unter anderem von PNG, JPEG, TIFF, PDF, animierten GIFs, Kamera-RAW und Photoshop-Dateien (PSD und PSB). Export unter anderem als PNG, JPEG, PDF und animiertes GIF.

## Oberflächensprache

Wähle die Sprache unter **Compositor → Einstellungen → Oberflächensprache**. Beende Compositor und öffne die App erneut, damit die Änderung wirksam wird. Mit **Systemstandard** verwendet Compositor die Sprache, die macOS für die App auswählt. Die Sprache einzelner Apps lässt sich auch unter **Systemeinstellungen → Allgemein → Sprache & Region → Programme** festlegen.

Neben Englisch (`en`) stehen sieben weitere Sprachen zur Verfügung. Fehlt eine Übersetzung, wird der englische Text angezeigt.

- Vereinfachtes Chinesisch (`zh-Hans`)
- Traditionelles Chinesisch (`zh-Hant`)
- Japanisch (`ja`)
- Koreanisch (`ko`)
- Französisch (`fr`)
- Deutsch (`de`)
- Spanisch (`es`)

Die deutschen, französischen, spanischen, japanischen und koreanischen Übersetzungen sind Vorschauversionen. Häufig genutzte Bedienelemente wurden stichprobenartig geprüft. Weitere Texte sind mit maschineller Unterstützung übersetzt. Die traditionelle chinesische Übersetzung orientiert sich nach Möglichkeit am Sprachgebrauch in Taiwan.

## Aus dem Quellcode bauen

Den Quellcode jeder Version findest du unter dem zugehörigen Git-Tag. Die folgenden Befehle verwenden den Standardbranch. Wenn du eine bestimmte Version bauen möchtest, wechsle vor dem Erstellen zum entsprechenden Tag.

```sh
git clone https://github.com/coderscsy/Compositor-Localization.git
cd Compositor-Localization
xcodebuild -project Compositor.xcodeproj -scheme Compositor \
  -configuration Release -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath build
open build/Build/Products/Release/Compositor.app
```

Du kannst auch `Compositor.xcodeproj` in Xcode öffnen und das Schema **Compositor** ausführen. Lokale Debug- und Release-Builds verwenden eine Ad-hoc-Signatur, die App Sandbox und eine separate Bundle-ID. Wenn du beide Ausgaben im Ordner „Programme“ behalten möchtest, kopiere die erstellte App als `Compositor Localization.app` dorthin.

Um deinen lokalen Build zu aktualisieren, erstelle die App aus einer neueren Version dieses Forks. Die signierte und von Apple notarisierte Original-App findest du auf der [Release-Seite des Originalprojekts](https://github.com/robbietilton/Compositor/releases/latest).

## Fehler melden und mitarbeiten

Melde fehlende Übersetzungen, unklare Formulierungen oder abgeschnittene Texte in den [Issues dieses Forks](https://github.com/coderscsy/Compositor-Localization/issues). Hilfreich sind folgende Angaben.

- Die ausgewählte Oberflächensprache
- Das betroffene Menü, Bedienfeld oder Fenster und der dort angezeigte Text
- Die Versionen von Compositor Localization und macOS
- Wenn möglich, Schritte zum Reproduzieren, die erwartete Formulierung und ein Bildschirmfoto

Korrekturen am [Übersetzungskatalog](../../Compositor/Resources/Localizable.xcstrings) kannst du auch als Pull Request in diesem Fork einreichen. Gib bitte die Sprache und die Stelle an, an der der geänderte Text angezeigt wird.

## Lizenz

Dieser Fork steht unter der [MIT-Lizenz](../../LICENSE). Die ursprüngliche App ist [Compositor von Robbie Tilton](https://github.com/robbietilton/Compositor). Das ursprüngliche Urheberrecht liegt bei Wonder Assembly LLC.
