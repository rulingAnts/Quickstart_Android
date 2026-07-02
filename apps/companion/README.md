# Dekereke Companion (desktop scaffold)

The researcher-side desktop app (plan §3, backlog #4): history, sync and
delegation for shared Dekereke databases. Flutter for Windows (decision
D6), sharing [`packages/dekereke_core`](../../packages/dekereke_core)
with the phone app.

Current state:

- **Health check** — functional: open a Dekereke `.xml` database and the
  core's health rules run against it (duplicate/empty References,
  SoundFile mismatches, missing/orphaned recordings when the settings
  file + audio folder sit next to the database).
- **History** (P1) and **Sync** (P2) — placeholder shells describing what
  they will do, in plain language (no VCS vocabulary anywhere).

## Development

```sh
flutter pub get
flutter analyze
flutter test
flutter build windows   # on a Windows machine / CI windows runner
```

CI: `.github/workflows/companion.yml` tests on ubuntu and builds a
Windows executable artifact whenever this app or the core changes.
