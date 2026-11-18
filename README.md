# Synth for macOS

Synth for macOS is a native SwiftUI client for the
[Synth engine](https://github.com/synth-sh/synth). It communicates with a
bundled `synth acp` subprocess. See the [wire contract](docs/acp.md).

## Build and run

The app supports Apple Silicon Macs running macOS 26 or later. Install and
select Xcode 26 or later. The build also needs XcodeGen and Zig 0.16. On Apple
Silicon, `nix develop` provides Zig, XcodeGen, and SwiftLint.

From the repository root:

```sh
Scripts/build-app.sh
```

The script fetches the engine revision pinned in `Engine.commit` from
`synth-sh/synth`, builds it, and embeds it in the app. The first build needs
network access for the engine and Swift packages. To use a compatible engine
you built yourself, set `SYNTH_ENGINE` to its absolute path.

Open `DerivedData/Build/Products/Release/Synth.app` in Finder. The app uses
the same provider configuration and credentials as the terminal client.
Manage provider credentials and MCP servers under **Settings > Models & MCP**.

To build in Xcode, run `xcodegen` before opening `Synth.xcodeproj`. A
successful run of the build script supplies the default engine at
`DerivedData/engine/bin/synth`. You can also set the `SYNTH_ENGINE` build
setting to another compatible engine. Xcode picks up new Swift files in
`App/` automatically. Rerun XcodeGen after changing `project.yml`.

The desktop version is set in `project.yml`. Update `Engine.commit`
separately when adopting changes from the engine.
See [Releasing Synth Desktop](docs/releasing.md) for distribution.

## Using the app

Choose **New Conversation** to chat without a project. Standalone chats use
`~/Library/Application Support/Synth/Conversations` as their working
directory. To work in a folder, choose **Open Project** or use the plus
button next to an existing project.

The sidebar shows when a background conversation is running or needs input.
Select **More Conversations** to load older chats. Press **Return** to send or
steer, **Shift–Return** for a new line, or **Stop** to cancel the current turn.

The composer renders Markdown as you type and reveals the syntax around your
caret. Use **Format** or the usual Bold, Italic, and Link shortcuts. Type `/`
at the start of a draft to discover actions and skills, or type `@` to select a
project file and include its contents. Use the arrow keys to move through
suggestions and **Tab** or **Return** to choose one.

Paste, drop, or choose images and text files using **Attach Files**. Long
pastes appear as removable text attachments that you can preview or insert back
into your draft. The composer keeps each conversation's draft and attachments
separate. Conversation messages use the same Markdown styles as the composer.
Select a linked file in a sent message to see the contents that went to the agent.

Choose **Synth > Settings > Themes** to browse the bundled themes.
Selecting a theme updates the conversation window immediately and saves your
choice for the next launch.

Use **Synth > Settings > Models & MCP** (⌘,) to connect providers and manage
MCP servers. Use the plus button next to model search to save an unlisted
model ID for a supported provider. Saved IDs appear in the conversation's
model picker alongside the provider catalog.

The **MCP Servers** tab shows each server's connection status in the current
conversation. Definition changes apply to new conversations. Enabling or
disabling a loaded server applies immediately.

Open **Synth > Settings > Notifications** to control alerts for input
requests and turn outcomes, and choose where sounds play. Select
**Enable macOS Notifications** to get alerts when the conversation window
is inactive. While you view another chat, alerts appear in the top-right
of the window. A dot in the sidebar marks a chat with unseen activity.

## Development

```sh
swiftlint lint --strict
swift test
python3 Tests/Fixtures/fake_provider.py DerivedData/Build/Products/Release/Synth.app/Contents/Helpers/synth
```

The integration test starts a provider on a loopback port with temporary
projects and its own database, config, and socket directory. It exercises
approvals, questions, steering, cancellation, reload, and multi-session
routing. Plain `swift test` skips the engine integration scenario.

After an intentional wire contract change, regenerate the fixture from
the matching engine checkout:

```sh
(cd /path/to/synth && zig build acp-fixtures) > Tests/SynthClientTests/Fixtures/stream.jsonl
```
