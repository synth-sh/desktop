# Releasing Synth Desktop

Set these Actions secrets in the Desktop repository before the first release:

- `DEVELOPER_ID_CERTIFICATE` is the base64-encoded Developer ID Application
  certificate and private key exported as a password-protected `.p12`.
- `DEVELOPER_ID_CERTIFICATE_PASSWORD` is the export password.
- `NOTARY_API_KEY` is the contents of the App Store Connect team API key
  `.p8`. `NOTARY_KEY_ID` and `NOTARY_ISSUER_ID` identify that key and team.

Update `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` in `project.yml`
and merge the version change into `main`. Wait for **Build and Test** to pass
and upload `tested-synth-app` for the exact `main` commit you want to release.
Then push a matching stable tag for that commit, such as `v0.1.0` for
marketing version `0.1.0`.

**Release Desktop** downloads that tested app without rebuilding, checks its
version against the tag, signs both executables, notarizes the app, and
attaches the ZIP to the GitHub release. If the tag was pushed too early, rerun
the release once the `main` run succeeds. The artifact is retained for 30 days.
If it's missing or expired, rerun **Build and Test** for the tagged commit if
GitHub still allows it, then rerun the release. Otherwise, cut the release from
a new `main` commit with a successful build and a fresh artifact.

After the release publishes, open
[Actions → Sync stable releases](https://github.com/synth-sh/homebrew-tap/actions/workflows/sync.yml)
in the tap and click **Run workflow** to propose the cask update PR.
