# Codex Remote

Codex Remote is a Flutter mobile client for connecting to a remote Codex app-server from Android or iOS.

It is designed for running Codex away from your workstation while still being able to:

- read and reply in active threads
- review approvals, command output, file changes, and tool activity
- switch model, reasoning effort, approval policy, and sandbox mode
- connect directly over WebSocket or through a relay bridge
- pair relay devices from a pairing code or QR code
- manage thread-scoped downloads and automations

## Features

- Direct mode with configurable WebSocket URL and optional bearer-token authentication
- Relay mode with device pairing and end-to-end encrypted session setup
- Thread list, resume support, and compact mobile-first conversation UI
- Command execution output and approval handling
- Download support for changed files and generated artifacts
- Automation workflows for file watching, downloads, and APK install flows
- Android foreground transport support for keeping the connection alive

## Requirements

- Flutter `3.35.x` or newer
- Dart `3.10.x` or newer
- Android Studio / Xcode for platform builds
- A reachable Codex app-server or relay deployment

## Quick Start

```bash
flutter pub get
flutter run
```

On first launch, open `Settings` and choose one of the supported connection modes:

### Direct Mode

1. Set `Connection mode` to `direct`.
2. Enter the remote WebSocket endpoint, for example `ws://192.168.1.20:8080`.
3. Optionally provide a bearer token if the app-server requires Authorization during the handshake.

### Relay Mode

1. Set `Connection mode` to `relay`.
2. Enter the relay base URL.
3. Paste a pairing code from `codex-remote-cli`, or scan the QR code shown by the bridge.
4. Save settings and connect.

## Development

Run static analysis and widget tests:

```bash
flutter analyze
flutter test
```

The repository also contains an app-server smoke test in [`test/app_server_protocol_smoke_test.dart`](test/app_server_protocol_smoke_test.dart). It expects a local app-server listening on `ws://127.0.0.1:5000`.

## Project Layout

- [`lib/`](lib) Flutter app source
- [`test/`](test) widget and protocol tests
- [`tool/generate_release_assets.dart`](tool/generate_release_assets.dart) icon and splash asset generator
- [`app_server_schema/`](app_server_schema) JSON schema snapshots used by the client

## Security

- Do not commit relay private keys, bearer tokens, or local platform signing material.
- Android signing keys, `android/local.properties`, generated build output, and Flutter ephemeral files are intentionally excluded from version control.
- If you discover a security issue, follow [`SECURITY.md`](SECURITY.md).

## License

This project is released under the MIT License. See [`LICENSE`](LICENSE).
