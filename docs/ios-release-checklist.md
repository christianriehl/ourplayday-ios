# iOS Release Checklist

Diese Checkliste ist der pragmatische Pfad fuer Builds, TestFlight und spaetere App-Store-Releases.

## 1. Vor dem Build

- Xcode ist aktuell genug fuer das Projekt und hat eine installierte iOS-Simulator-Runtime
- du bist mit dem richtigen Apple-Developer-Account in Xcode eingeloggt
- das Team `KNU644979P` ist verfuegbar
- Bundle Identifier und Signing passen zum Ziel `de.christianriehl.playday`
- die Web-Domain `playday.christianriehl1.workers.dev` ist erreichbar

## 2. Schneller Technik-Check

Lokaler Simulator-Build ohne Code Signing:

```sh
xcodebuild \
  -project playday.xcodeproj \
  -scheme playday \
  -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  -derivedDataPath /tmp/playday-derived \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  build
```

Optionaler Swift-Typecheck:

```sh
xcrun --sdk iphoneos swiftc \
  -target arm64-apple-ios17.0 \
  -module-cache-path /tmp/playday-swift-module-cache \
  -typecheck \
  playday/AppConfiguration.swift \
  playday/ContentView.swift \
  playday/WebView.swift \
  playday/playdayApp.swift
```

## 3. Manuelle Smoke-Checks

- App startet ohne Crash
- WebView zeigt die PlayDay-Startseite
- Ladezustand ist sichtbar
- Fehlerzustand zeigt Retry-UI bei absichtlichem Offline-Test
- externer Link verlaesst die App korrekt in Richtung Safari
- JavaScript `alert`, `confirm` und `prompt` funktionieren

## 4. Universal Links

App-Seite:
- Associated Domains sind in `playday/playday.entitlements` gesetzt
- `NSUserActivityTypeBrowsingWeb` wird in `playday/playdayApp.swift` verarbeitet

Domain-Seite:
- `/.well-known/apple-app-site-association` liefert `HTTP 200`
- Response kommt als `application/json`
- die App-ID `KNU644979P.de.christianriehl.playday` ist enthalten

Praxis-Test:
- am besten auf einem echten iPhone pruefen
- Link aus Notes, Nachrichten oder Safari aufrufen
- die App sollte statt Safari oeffnen

## 5. Signing und Archive

Fuer Geraet, TestFlight und App Store gilt:

- in Xcode `Signing & Capabilities` fuer das richtige Team pruefen
- automatisches Signing bevorzugen, solange kein manuelles Profil notwendig ist
- Archive ueber `Product > Archive` erzeugen
- im Organizer validieren, bevor nach TestFlight hochgeladen wird

Wenn `xcodebuild` lokal wegen Provisioning-Profilen scheitert:
- Apple-Account in Xcode neu anmelden
- Signing einmal im Projekt target pruefen
- bei Bedarf automatische Profile neu erzeugen lassen

## 6. Vor TestFlight

- aktueller `main`-Branch ist gruen
- GitHub Action `iOS Build` ist erfolgreich
- relevante PRs sind gemerged
- Versionsnummer und Build-Nummer sind korrekt
- kurzer Geraetetest fuer Start, Links und Fehlerfall wurde gemacht

## 7. Nach dem Upload

- TestFlight-Build erscheint fuer den richtigen Bundle Identifier
- Start der App auf Geraet pruefen
- Universal Links erneut testen
- kein leerer Screen bei Netzwerkfehlern
- externes Link-Verhalten pruefen
