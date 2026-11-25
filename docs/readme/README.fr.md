# Compositor Localization

[English](../../README.md) · [简体中文](README.zh-Hans.md) · [繁體中文](README.zh-Hant.md) · [日本語](README.ja.md) · [한국어](README.ko.md) · **Français** · [Deutsch](README.de.md) · [Español](README.es.md)

Compositor Localization est un fork communautaire de [Compositor, créé par Robbie Tilton](https://github.com/robbietilton/Compositor). C’est un éditeur d’images libre conçu pour le photomontage et la retouche photo sur macOS.

Le développement, les tests et les publications de ce fork concernent exclusivement macOS sur les Mac équipés d’une puce Apple.

## Configuration requise

- Un Mac équipé d’une puce Apple, sous macOS 26 ou version ultérieure.
- Xcode pour compiler l’application. L’intégration continue du projet d’origine utilise Xcode 26.6.

## Télécharger pour macOS

Téléchargez [`Compositor-Localization-1.8.0-macos-arm64.dmg`](https://github.com/coderscsy/Compositor-Localization/releases/download/v1.8.0/Compositor-Localization-1.8.0-macos-arm64.dmg) pour un Mac équipé **d’une puce Apple sous macOS 26 ou version ultérieure**. Le fichier `SHA256SUMS.txt`, disponible sur la même page, permet de vérifier le téléchargement. Ouvrez l’image disque et copiez l’app dans le dossier Applications. [Préversion sur GitHub](https://github.com/coderscsy/Compositor-Localization/releases/tag/v1.8.0)

L’app utilise une signature ad hoc et n’a pas été notariée par Apple. Gatekeeper peut en bloquer la première ouverture. Vous pouvez aussi compiler l’app à partir du code source en suivant les instructions ci-dessous. [Guide d’Apple sur l’ouverture des apps Mac](https://support.apple.com/fr-fr/102445)

## Fonctionnalités

- **Nouveautés v1.8.0 :** Importation de pinceaux Photoshop `.abr` et bibliothèque locale, verrouillage des calques, opacité de fond (Fill), options de fusion (Blend If), Biseautage et estampage, outil Plume et tracés de Bézier, masques vectoriels et opérations booléennes, texte vertical/déformé/sur tracé, déformation par maillage (Warp), Masque rapide (Q) et Sélectionner et masquer, panneaux Historique/Informations/Histogramme, export WebP sans perte et HEIC, et aller-retour PSD haute fidélité. [Journal des modifications](../../CHANGELOG.md)
- Calques, groupes, masques de fusion, masques d’écrêtage et modes de fusion.
- Déplacement, mise à l’échelle, rotation et symétrie non destructifs. Alignement et répartition des calques. Magnétisme aux repères et à la grille.
- Sélections rectangulaires et elliptiques, lasso, baguette magique, sélection d’objet et remplissage d’après le contenu.
- Pinceau, gomme, correcteur localisé, tampon de duplication, dégradés, formes et texte modifiables.
- Filtre Camera Raw avec aperçu en direct, ainsi que niveaux, courbes, teinte et saturation, balance des couleurs et autres filtres.
- Projets ouverts dans des onglets, recherche de commandes avec ⌘F et raccourcis clavier personnalisables.
- Importation d’images, de fichiers RAW et de fichiers Photoshop PSD/PSB. Exportation en PNG, JPEG, PDF et GIF animé, entre autres formats.

## Langue de l’interface

Ouvrez **Compositor → Réglages → Langue de l’interface**, choisissez une langue, puis quittez et rouvrez l’application. L’option **Selon le système** suit la langue que macOS attribue à Compositor. Pour la définir dans macOS, ouvrez **Réglages Système → Général → Langue et région → Applications**.

L’anglais est la langue source. Il s’affiche lorsqu’un texte n’a pas encore été traduit. Sept traductions sont disponibles.

- Chinois simplifié (`zh-Hans`) et chinois traditionnel (`zh-Hant`). La version traditionnelle privilégie la terminologie utilisée à Taïwan.
- Français (`fr`), allemand (`de`), espagnol (`es`), japonais (`ja`) et coréen (`ko`). Ces traductions sont en préversion. Les commandes courantes ont fait l’objet de vérifications ponctuelles. Le reste de l’interface comporte des traductions assistées par machine.

## Compiler depuis le code source

Le code source de chaque version est disponible au tag Git correspondant. Pour compiler une version précise, sélectionnez son tag dans le dépôt cloné avant de lancer `xcodebuild`.

```sh
git clone https://github.com/coderscsy/Compositor-Localization.git
cd Compositor-Localization
xcodebuild -project Compositor.xcodeproj -scheme Compositor \
  -configuration Release -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath build
open build/Build/Products/Release/Compositor.app
```

Vous pouvez aussi ouvrir `Compositor.xcodeproj` dans Xcode et exécuter le schéma **Compositor**.

Les configurations Debug et Release utilisent une signature ad hoc pour les compilations locales. L’application s’exécute dans un bac à sable et possède son propre identifiant de bundle. Pour conserver les deux éditions dans le dossier Applications, copiez l’app compilée sous le nom `Compositor Localization.app`. Pour mettre à jour votre compilation locale, recompilez l’app à partir d’une version plus récente de ce fork.

L’application officielle est signée par son développeur et notariée par Apple. Téléchargez-la sur la [page des versions du projet d’origine](https://github.com/robbietilton/Compositor/releases/latest).

## Signaler un problème ou contribuer

Pour signaler un problème sur macOS ou une erreur de traduction, ouvrez un ticket dans le [suivi des problèmes de ce fork](https://github.com/coderscsy/Compositor-Localization/issues). Indiquez la langue choisie, le menu, l’écran ou le panneau concerné, le texte affiché, la version de Compositor et celle de macOS. Vous pouvez également proposer une correction du [catalogue de chaînes](../../Compositor/Resources/Localizable.xcstrings) via une pull request dans ce dépôt.

## Licence et crédits

Ce fork est distribué sous [licence MIT](../../LICENSE). Compositor a été créé par Robbie Tilton. Le copyright d’origine appartient à Wonder Assembly LLC.

Le modèle de profondeur DepthMini, utilisé par l’éclairage volumétrique, est dérivé de [Depth Anything V2 Small](https://github.com/DepthAnything/Depth-Anything-V2) (Apache-2.0) et utilise comme point de départ les poids MobileNetV3 de torchvision entraînés sur ImageNet (BSD-3-Clause). Le modèle est téléchargé à la première ouverture du filtre Éclairage volumétrique.
