# WebView- und Xcode-Aenderungen

Dieses Dokument fasst die aktuell sichtbaren Aenderungen rund um die iOS-WebView-Integration zusammen. Grundlage ist der Stand der Dateien im Projekt am 27.03.2026.

## Ziel der Aenderung

Die iOS-App wurde von einer Standard-SwiftUI-Startansicht auf einen einfachen nativen Wrapper fuer die bestehende PlayDay-Web-App umgestellt. Die App oeffnet jetzt direkt die produktive Web-App in einem `WKWebView`.

## Von Xcode bzw. dem Projekt-Setup sichtbare Aenderungen

### Projektkonfiguration

In [`playday.xcodeproj/project.pbxproj`](/Users/christian/Documents/playday/playday.xcodeproj/project.pbxproj) wurden unter anderem diese Projektwerte angepasst:

- `INFOPLIST_FILE = playday/Info.plist` wurde gesetzt.
- `INFOPLIST_KEY_CFBundleDisplayName = PlayDay` wurde fuer Debug und Release gesetzt.
- `DEVELOPMENT_TEAM = KNU644979P` wurde eingetragen.
- Die synchronisierte Projektstruktur (`PBXFileSystemSynchronizedRootGroup`) wurde um eine Ausnahme fuer `Info.plist` erweitert.

Diese Aenderungen deuten darauf hin, dass das Projekt in Xcode fuer ein konkreteres App-Setup konfiguriert wurde und nicht mehr nur auf den komplett generierten Standardwerten laeuft.

### App-Icons

Im Asset-Katalog wurden neue App-Icon-Dateien angelegt:

- [`1024.png`](/Users/christian/Documents/playday/playday/Assets.xcassets/AppIcon.appiconset/1024.png)
- [`1024dark.png`](/Users/christian/Documents/playday/playday/Assets.xcassets/AppIcon.appiconset/1024dark.png)
- [`1024tinted.png`](/Users/christian/Documents/playday/playday/Assets.xcassets/AppIcon.appiconset/1024tinted.png)

In [`Contents.json`](/Users/christian/Documents/playday/playday/Assets.xcassets/AppIcon.appiconset/Contents.json) werden diese Varianten jetzt fuer `universal`, `dark` und `tinted` referenziert.

### Info.plist

In [`playday/Info.plist`](/Users/christian/Documents/playday/playday/Info.plist) wurde `NSAppTransportSecurity` mit `NSAllowsArbitraryLoads = true` gesetzt.

Bedeutung:
- Die App erlaubt damit aktuell auch nicht-HTTPS-Ladevorgaenge.
- Fuer eine Produktions-App ist das oft zu breit und sollte spaeter enger gefasst oder wieder entfernt werden, wenn nur HTTPS benoetigt wird.

## Funktionale UI-Aenderungen

### ContentView

[`ContentView.swift`](/Users/christian/Documents/playday/playday/ContentView.swift) wurde von der SwiftUI-Standardansicht (`Hello, world!`) auf eine Vollbild-WebView umgestellt.

Aktuelles Verhalten:
- Die App laedt direkt `https://playday.christianriehl1.workers.dev`.
- Die WebView ignoriert Safe Areas und fuellt den kompletten Bildschirm.

Das macht die iOS-App aktuell zu einem nativen Container fuer die bestehende Web-App.

## WebView-Implementierung

[`WebView.swift`](/Users/christian/Documents/playday/playday/WebView.swift) wurde von einer leeren Datei auf einen deutlich umfangreicheren `WKWebView`-Wrapper ausgebaut.

### Enthaltene Funktionen

- `UIViewRepresentable`-Wrapper fuer `WKWebView`
- Bindings fuer Ladezustand, Seitentitel und manuellen Reload-Trigger
- optionale Callbacks fuer Navigationsentscheidungen und Fehler
- optionaler `configurationProvider`
- optionaler `requestBuilder`
- optionales Pull-to-Refresh
- KVO fuer `estimatedProgress` und `title`
- JavaScript-Console-Bridge ueber `WKUserScript` und `WKScriptMessageHandler`
- `WKNavigationDelegate`- und `WKUIDelegate`-Anbindung

### Was die neue WebView bereits kann

- Initiales Laden einer URL
- erneutes Laden bei URL-Wechsel oder geaendertem Reload-Trigger
- JS-Konsole in native Logs spiegeln
- Ladezustand im SwiftUI-Host aktualisieren
- Seitentitel zurueck in SwiftUI spiegeln
- Fehler nach aussen melden
- Browser-Dialogs wie `alert()` und `confirm()` nativ darstellen

### Stand zu GitHub-Issue #1

`WebView.swift` wurde inzwischen fuer den Lifecycle des `WKWebView` robuster gemacht:

- KVO fuer `estimatedProgress` und `title` laeuft jetzt ueber `NSKeyValueObservation` statt ueber manuelles `addObserver`/`removeObserver`.
- Das reduziert Absturzrisiken beim Dealloc und macht das Deregistrieren explizit steuerbar.
- Fuer SwiftUI wurde `dismantleUIView(_:coordinator:)` ergaenzt, damit Delegates, Refresh-Control und Script-Handler beim Abbau gezielt entfernt werden.
- Der JavaScript-Bridge-Handler wird nicht mehr direkt am Coordinator registriert, sondern ueber einen schwachen Wrapper, damit kein unnoetiger Retain-Cycle zwischen `WKUserContentController` und Coordinator entsteht.

Damit ist der erste Stabilisierungspunkt aus dem Milestone technisch umgesetzt.

## Offene technische Auffaelligkeiten

Die aktuelle Implementierung ist als funktionaler erster Stand brauchbar, aber noch nicht komplett robust. Dazu passen auch die bereits angelegten GitHub-Issues.

Wichtige Punkte:
- `updateUIView` kann Reloads ausloesen, die potenziell unnoetig sind.
- Pull-to-Refresh ist noch fragil, weil `sender.superview as? WKWebView` nicht verlaesslich sein muss.
- `NSAllowsArbitraryLoads = true` ist fuer Produktion wahrscheinlich zu offen.

## Passende GitHub-Issues

Die folgenden Issues wurden dafuer im iOS-Repo angelegt und organisiert:

- [#1 WebView: KVO-Observer und Script-Handler sauber deregistrieren](https://github.com/christianriehl/ourplayday-ios/issues/1)
- [#2 WebView: unnoetige Reloads in updateUIView vermeiden](https://github.com/christianriehl/ourplayday-ios/issues/2)
- [#3 WebView: Pull-to-Refresh robuster implementieren](https://github.com/christianriehl/ourplayday-ios/issues/3)
- [#4 WebView: JS-Console-Bridge optional und produktionssicher machen](https://github.com/christianriehl/ourplayday-ios/issues/4)
- [#5 WebView: Navigation und Fehlerfaelle strukturierter an den Host melden](https://github.com/christianriehl/ourplayday-ios/issues/5)

Alle sind aktuell dem Milestone `WebView Stabilisierung` zugeordnet und mit den Labels `ios`, `webview` und `tech-debt` versehen.
