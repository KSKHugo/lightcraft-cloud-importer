# LightCraft Cloud Importer

Eine native macOS-App für den Umzug einer Adobe-Lightroom-Cloud-Bibliothek nach [LightCraft](https://github.com/storytold/lightcraft), mit möglichst allen Metadaten.

**Stand: früher Prototyp.** Die App arbeitet mit einem lokalen Lightroom-Export. Mit einem echten Export und dem anschließenden Import in LightCraft ist sie noch nicht getestet. Das [klickbare Mockup](2026-11-23_LightCraft-Cloud-Importer_App-Mockup.html) zeigt das ursprüngliche Konzept mit Beispieldaten.

## Ablauf

1. In Lightroom die Fotos als „Original + Einstellungen“ exportieren, pro Album in einen Unterordner.
2. In der App den Export-Ordner und einen eigenen Zielordner wählen.
3. Alben auswählen und prüfen, wie jedes Metadatenfeld übernommen wird.
4. Importieren, mit Pause, Abbruch, Fortsetzen und Duplikaterkennung.
5. Den Bericht prüfen und den Zielordner in LightCraft importieren.

Der Export wird nur gelesen. Im Zielordner wird nichts überschrieben, und jede Kopie wird per SHA-256 mit dem Original verglichen. Die App läuft in der macOS-Sandbox und hat keinen Netzwerkzugriff.

## Bauen

Voraussetzung sind macOS 14 oder neuer und Xcode.

```bash
swift test
```

```bash
Scripts/build_app.sh
```

Die fertige App liegt danach in `dist/`.

## Technische Grenzen

- **Originale:** Die [Lightroom Partner API](https://github.com/AdobeDocs/lightroom-partner-apis) dokumentiert das Hochladen von Originalen, aber keinen Download. Für RAW-Dateien ist deshalb nach aktuellem Stand ein Export „Original + Einstellungen“ aus Lightroom nötig.
- **Vollautomatischer Weg:** Über die API lassen sich JPEG-Renditions laden. Sie enthalten keine RAW-Daten, und Bearbeitungen sind fest eingerechnet.
- **API-Zugang:** Die API steht laut Adobe nur freigeschalteten Partner-Anwendungen zur Verfügung. Ob dieses Projekt eine Freigabe erhält, ist offen.
- **LightCraft:** LightCraft liest XMP-Sidecars und importiert Lightroom-Classic-Kataloge. Cloud-Bibliotheken (`.lrlibrary`) unterstützt es nicht.
- **GPS und Pick:** LightCraft liest GPS aus der Bilddatei, nicht aus XMP, und wertet `xmpDM:pick` nicht aus. Der Bericht listet betroffene Fotos auf.
- **Eingebettetes XMP:** Beim Import liest LightCraft es nur aus RAW- und DNG-Dateien. Für andere Formate legt die App deshalb eine XMP-Datei neben die Kopie.
- **Alben:** Ein Export enthält keine Alben. Die App übernimmt stattdessen die Unterordner des Exports.
- **Bearbeitungen:** Entwicklungseinstellungen werden in LightCraft nur angenähert. Das Ergebnis kann sichtbar vom Lightroom-Bild abweichen.

## Sicherheit

Vor jedem Push und auf GitHub laufen `gitleaks`, `osv-scanner` und `semgrep`.

```bash
brew install gitleaks osv-scanner semgrep
```

```bash
Scripts/install_hooks.sh
```

## Lizenz

Copyright (c) 2026 Pascal Hugo

Dieses Projekt steht wahlweise unter einer der beiden folgenden Lizenzen (`MIT OR Apache-2.0`):

- [MIT-Lizenz](LICENSE-MIT)
- [Apache-Lizenz 2.0](LICENSE-APACHE)

Sofern du nichts anderes angibst, wird jeder Beitrag, den du zur Aufnahme in dieses Projekt einreichst, ebenfalls unter diesen beiden Lizenzen veröffentlicht, ohne zusätzliche Bedingungen.

## Hinweis zu Marken

Der LightCraft Cloud Importer ist ein unabhängiges Projekt und kein offizielles LightCraft-Produkt. Er steht in keiner Verbindung zu Adobe oder zum LightCraft-Projekt. Adobe und Lightroom sind Marken von Adobe Inc.
