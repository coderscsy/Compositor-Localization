# Compositor Localization

[English](../../README.md) · [简体中文](README.zh-Hans.md) · [繁體中文](README.zh-Hant.md) · [日本語](README.ja.md) · [한국어](README.ko.md) · [Français](README.fr.md) · [Deutsch](README.de.md) · **Español**

Compositor Localization es un fork comunitario de [Compositor, creado por Robbie Tilton](https://github.com/robbietilton/Compositor). Es un editor de imágenes de código abierto para componer y retocar fotografías en macOS.

El desarrollo, las pruebas y las publicaciones de este fork se centran exclusivamente en macOS para Mac con chip de Apple.

## Requisitos

- Un Mac con chip de Apple y macOS 26 o posterior.
- Xcode para compilar la aplicación. La integración continua del proyecto original utiliza Xcode 26.6.

## Funciones

- Capas, grupos, máscaras de capa, máscaras de recorte y modos de fusión.
- Desplazamiento, escala, rotación y volteo no destructivos. Alineación y distribución de capas. Ajuste a las guías y a la cuadrícula.
- Selecciones rectangulares y elípticas, lazo, varita mágica, selección de objetos y relleno según el contenido.
- Pincel, borrador, pincel corrector puntual, tampón de clonar, degradados, formas y texto editable.
- Filtro Camera Raw con vista previa en directo, además de niveles, curvas, tono y saturación, equilibrio de color y otros filtros.
- Proyectos en pestañas, búsqueda de comandos con ⌘F y atajos de teclado personalizables.
- Importación de imágenes, archivos RAW y documentos de Photoshop en PSD/PSB. Exportación a PNG, JPEG, PDF y GIF animado, entre otros formatos.

## Idioma de la interfaz

Abre **Compositor → Ajustes → Idioma de la interfaz**, elige un idioma y, a continuación, cierra y vuelve a abrir la aplicación. **Idioma del sistema** usa el idioma que macOS asigna a Compositor. Puedes cambiarlo en **Ajustes del Sistema → General → Idioma y región → Aplicaciones**.

El inglés es el idioma original y se muestra cuando falta una traducción. Hay siete traducciones disponibles.

- Chino simplificado (`zh-Hans`) y chino tradicional (`zh-Hant`). El chino tradicional usa, cuando es posible, la terminología habitual en Taiwán.
- Francés (`fr`), alemán (`de`), español (`es`), japonés (`ja`) y coreano (`ko`). Estas traducciones están en fase preliminar. Se han revisado algunos controles de uso habitual y el resto de la interfaz incluye traducciones asistidas por máquina.

## Compilar desde el código fuente

Las [publicaciones de GitHub](https://github.com/coderscsy/Compositor-Localization/releases) ofrecen el código fuente de cada versión mediante etiquetas. Para compilar una versión concreta, selecciona su etiqueta en el repositorio clonado antes de ejecutar `xcodebuild`. El comando `git switch --detach v1.7.2-l10n.1` selecciona la primera versión multilingüe.

```sh
git clone https://github.com/coderscsy/Compositor-Localization.git
cd Compositor-Localization
xcodebuild -project Compositor.xcodeproj -scheme Compositor \
  -configuration Release -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath build
open build/Build/Products/Release/Compositor.app
```

También puedes abrir `Compositor.xcodeproj` en Xcode y ejecutar el esquema **Compositor**.

Las compilaciones locales de Debug y Release usan una firma ad hoc. La aplicación se ejecuta en un entorno aislado y tiene un identificador de paquete propio. Para conservar ambas ediciones en la carpeta Aplicaciones, copia el resultado con el nombre `Compositor Localization.app`. Para actualizarla, compila una versión más reciente de este fork.

La aplicación oficial está firmada por su desarrollador y notarizada por Apple. Puedes descargarla en la [página de publicaciones del proyecto original](https://github.com/robbietilton/Compositor/releases/latest).

## Informar de un problema o colaborar

Si encuentras un problema en macOS o un error de traducción, abre una incidencia en el [registro de este fork](https://github.com/coderscsy/Compositor-Localization/issues). Incluye el idioma seleccionado, el menú, pantalla o panel correspondiente, el texto que ves y las versiones de Compositor y macOS. También puedes proponer una corrección al [catálogo de cadenas](../../Compositor/Resources/Localizable.xcstrings) mediante una solicitud de incorporación de cambios en este repositorio.

## Licencia y créditos

Este fork se distribuye bajo la [licencia MIT](../../LICENSE). Robbie Tilton creó Compositor. Los derechos de autor originales pertenecen a Wonder Assembly LLC.

DepthMini, el modelo de profundidad de la iluminación volumétrica, deriva de [Depth Anything V2 Small](https://github.com/DepthAnything/Depth-Anything-V2) (Apache-2.0) y parte de los pesos de MobileNetV3 de torchvision entrenados con ImageNet (BSD-3-Clause). El modelo se descarga la primera vez que abres el filtro Iluminación volumétrica.
