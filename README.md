# ourplayday-ios

Eine schlanke iOS-Huelle fuer die PlayDay-Web-App auf Basis von `WKWebView`.

## Lokaler Build

Voraussetzungen:
- Xcode mit iOS-Simulator-Runtime
- optional: gueltige Apple-Signing-Konfiguration fuer Device-Builds

Simulator-Build ohne Code Signing:

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

Weiterfuehrend:
- Release- und TestFlight-Checkliste: `docs/ios-release-checklist.md`

## Was die App aktuell absichert

- Start-URL kommt aus `PLAYDAY_BASE_URL` in `playday/Info.plist`
- keine globale ATS-Deaktivierung mehr
- sichtbarer Ladezustand, Fehlerzustand und Retry-Button
- Retry bei transienten Netzwerkfehlern
- native Dialoge fuer JavaScript `alert`, `confirm` und `prompt`
- Universal Links fuer `playday.christianriehl1.workers.dev` sind auf App-Seite vorbereitet

## Offene Follow-ups

- Universal Links Ende-zu-Ende: Issue #6
  Die App- und Domain-Seite sind vorbereitet; der finale Geraetetest steht noch aus.
- reproduzierbare Release-/Build-Validierung: Issue #7
