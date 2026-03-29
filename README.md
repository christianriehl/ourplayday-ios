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

## Was die App aktuell absichert

- Start-URL kommt aus `PLAYDAY_BASE_URL` in `playday/Info.plist`
- keine globale ATS-Deaktivierung mehr
- sichtbarer Ladezustand, Fehlerzustand und Retry-Button
- Retry bei transienten Netzwerkfehlern
- native Dialoge fuer JavaScript `alert`, `confirm` und `prompt`

## Offene Follow-ups

- Universal Links Ende-zu-Ende: Issue #6
- reproduzierbare Release-/Build-Validierung: Issue #7
