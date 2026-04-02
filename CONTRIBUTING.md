# Contributing

## Setup

```bash
flutter pub get
flutter analyze
flutter test
```

## Pull Requests

- Keep changes focused and reviewable.
- Add or update tests when behavior changes.
- Avoid committing generated build output, local IDE files, secrets, signing keys, or relay credentials.
- Document any user-visible setup or protocol changes in [`README.md`](README.md).

## Release Hygiene

- Verify `flutter analyze` and `flutter test` pass before opening a PR.
- Keep platform-specific signing material out of the repository.
- Treat relay keys, bearer tokens, and local connection details as secrets.
