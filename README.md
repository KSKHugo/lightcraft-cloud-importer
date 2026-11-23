# Lightroom Importer

Ein geplantes Open-Source-Werkzeug für den Umzug einer Adobe-Lightroom-Cloud-Bibliothek nach [LightCraft](https://github.com/storytold/lightcraft), mit möglichst allen Metadaten.

**Stand: Mockup.** Das Projekt enthält noch keine funktionierende App. Das [klickbare Mockup](2026-11-23_Lightroom-Importer_App-Mockup.html) nutzt Beispieldaten, verbindet sich mit keinem Konto und verändert keine Dateien.

## Geplanter Ablauf

1. Lightroom-Bibliothek und LightCraft-Bibliothek verbinden.
2. Alben oder die ganze Bibliothek auswählen.
3. Für jedes Metadatenfeld sehen, wie es übernommen wird.
4. Importieren, mit Pause, Fortsetzen und Duplikaterkennung.
5. Im Bericht prüfen, was übernommen wurde und was nachgesehen werden sollte.

Die Lightroom-Bibliothek wird dabei nur gelesen.

## Technische Grenzen

- **Originale:** Die [Lightroom Partner API](https://github.com/AdobeDocs/lightroom-partner-apis) dokumentiert das Hochladen von Originalen, aber keinen Download. Für RAW-Dateien ist deshalb nach aktuellem Stand ein Export „Original + Einstellungen“ aus Lightroom nötig.
- **Vollautomatischer Weg:** Über die API lassen sich JPEG-Renditions laden. Sie enthalten keine RAW-Daten, und Bearbeitungen sind fest eingerechnet.
- **API-Zugang:** Die API steht laut Adobe nur freigeschalteten Partner-Anwendungen zur Verfügung. Ob dieses Projekt eine Freigabe erhält, ist offen.
- **LightCraft:** LightCraft liest XMP-Sidecars und importiert Lightroom-Classic-Kataloge. Cloud-Bibliotheken (`.lrlibrary`) unterstützt es nicht.
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

Die Lizenz ist noch nicht festgelegt. Bis eine `LICENSE`-Datei im Repository liegt, gelten die normalen Urheberrechte.

## Hinweis zu Marken

Dieses Projekt ist unabhängig und steht in keiner Verbindung zu Adobe oder zum LightCraft-Projekt. Adobe und Lightroom sind Marken von Adobe Inc.
