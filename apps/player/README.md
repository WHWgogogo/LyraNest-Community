# Player

Flutter client for the music player service.

## Targets

- Windows
- Android

## Run

```bash
flutter pub get
flutter run -d windows
flutter run -d android
```

The server base URL can be changed in the Settings page. The initial value is `http://127.0.0.1:8080`.

## API

- `GET /api/v1/tracks`
- `GET /api/v1/tracks/{id}/lyrics`

Desktop lyrics overlay APIs are intentionally defined as cross-platform interfaces with Windows and Android capability models. Native overlay implementations are placeholders for a later platform-channel milestone.
