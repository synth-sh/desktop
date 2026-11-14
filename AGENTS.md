# Repository Guidelines

Synth for macOS is a SwiftUI client. The Swift package contains the ACP
protocol and subprocess client. The [Synth engine](https://github.com/synth-sh/synth)
owns tools, provider credentials, permissions, and session storage.

- Build the app with `Scripts/build-app.sh`.
- Run `swiftlint lint --strict` when changing Swift code.
- Run `swift test` for package tests. Use
  `python3 Tests/Fixtures/fake_provider.py <path-to-engine>` to include the
  integration tests against an isolated engine.
- Keep comments for non-obvious constraints. Use Conventional Commits with a scope.
- Keep generated Xcode files out of Git.
