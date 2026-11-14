# Releasing Synth Desktop

Set these Actions secrets in the Desktop repository before the first release:

- `DEVELOPER_ID_CERTIFICATE` is the base64-encoded Developer ID Application
  certificate and private key exported as a password-protected `.p12`.
- `DEVELOPER_ID_CERTIFICATE_PASSWORD` is the export password.
- `NOTARY_API_KEY` is the contents of the App Store Connect team API key
  `.p8`. `NOTARY_KEY_ID` and `NOTARY_ISSUER_ID` identify that key and team.

Update `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` in `project.yml`.
Once the version change is on `main`, push a matching stable tag. For
example, use `v0.1.0` for marketing version `0.1.0`.

The release workflow builds and tests the app with the pinned engine, signs
both executables, notarizes the app, and attaches the ZIP to the GitHub
release. The [Synth tap](https://github.com/synth-sh/homebrew-tap) checks for
the release and opens a cask update PR. To update it immediately after
publication, run **Sync stable releases** in the tap's Actions tab.
