# LightCraft Cloud Importer

Eine native macOS-App für den Umzug einer Adobe-Lightroom-Cloud-Bibliothek nach [LightCraft](https://github.com/storytold/lightcraft), mit möglichst allen Metadaten.

**Stand: Version 0.1, früher Stand.** Die App arbeitet mit einem lokalen Lightroom-Export. Ein erster echter Test mit 9 Fotos lief durch: Kopien prüfsummengleich, Metadaten, Album, Bewertungen und Regler-Werte kamen in LightCraft an. Farbmarkierungen, Ablehnungen, GPS, Masken und Personen sind mit echten Daten noch nicht geprüft. Das [klickbare Mockup](2026-11-23_LightCraft-Cloud-Importer_App-Mockup.html) zeigt das ursprüngliche Konzept mit Beispieldaten.

## Download

Fertige Versionen liegen unter [Releases](https://github.com/KSKHugo/lightcraft-cloud-importer/releases) als Disk-Image. Die App ist mit einer Developer ID signiert und von Apple notarisiert. Sie läuft ab macOS 14 auf Apple Silicon und Intel. Zum Installieren die App aus dem Image in den Ordner „Programme“ ziehen.

## Ablauf

1. In Lightroom die Fotos als „Original + Einstellungen“ exportieren, pro Album in einen Unterordner.
2. In der App den Export-Ordner und einen eigenen Zielordner wählen.
3. Alben auswählen und prüfen, wie jedes Metadatenfeld übernommen wird.
4. Importieren, mit Pause, Abbruch, Fortsetzen und Duplikaterkennung.
5. Den Bericht prüfen und den Zielordner in LightCraft importieren.

Der Export wird nur gelesen. Im Zielordner wird nichts überschrieben, und jede Kopie wird per SHA-256 mit dem Original verglichen. Die App enthält keinen Netzwerkcode. Sie ist nicht für den Mac App Store gedacht und läuft deshalb ohne App-Sandbox.

## Bauen

Voraussetzung sind macOS 14 oder neuer und Xcode.

```bash
swift test
```

```bash
Scripts/build_app.sh
```

Die fertige App liegt danach in `dist/`. Sie ist nur ad hoc signiert und für den eigenen Mac gedacht.

Das Disk-Image zum Download baut `Scripts/build_release.sh`: Universal-App, Developer-ID-Signatur, Notarisierung und Stapling. Dafür braucht es ein „Developer ID Application“-Zertifikat und im Schlüsselbund hinterlegte Notarisierungs-Zugangsdaten (siehe Kopf des Skripts). Das Icon zeichnet `Scripts/make_icon.swift`.

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
