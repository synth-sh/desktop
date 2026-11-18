# Synth's desktop ACP contract

Start `synth acp` and communicate over stdin/stdout with one UTF-8
JSON-RPC 2.0 object per line. The limit is 16 MiB per frame. Stderr is for
diagnostics. Request IDs can be integers or strings, and requests in each
direction have independent ID spaces.

Send `initialize` with `protocolVersion: 1`,
`_meta: {"synth":{"protocol":2}}` and
`clientCapabilities: {"elicitation":{"form":{}}}`. Check both versions
in the reply. This opts into Synth's session notifications in place of
ordinary ACP transcript updates. File and terminal capabilities are omitted,
so the engine handles those operations. Keep reading output while requests
are in flight.

| Method | Parameters and behavior |
| --- | --- |
| `session/new` | Absolute `cwd` and `mcpServers: []`. Returns a `sessionId`. |
| `session/load` | `sessionId`, absolute `cwd`, and `mcpServers: []`. Attaches to an existing host when one is listening. |
| `session/list` | Optional `cwd` for the project. Returns up to 50 persisted sessions. Pass `nextCursor` back as `cursor` with the same project scope to get the next page. Empty sessions are omitted. |
| `session/prompt` | `sessionId` and `prompt`, an array of content blocks. See the content blocks below. A second prompt during a busy turn is steering. Prompt replies arrive when the turn settles. |
| `session/cancel` | Notification with `sessionId`. Stops the turn. |
| `session/set_mode` | `sessionId` and a `modeId` from the open or load reply. |
| `session/set_config_option` | `sessionId`, `configId` of `model` or `effort`, and `value`. For a model from the catalog, include `_meta.synth.provider` with its provider ID. |
| `_synth/files` | `sessionId`. Lists project-relative paths for mention completion. Directories have a trailing slash. |
| `_synth/compact` | `sessionId`. Starts compaction for an idle conversation. |
| `_synth/load_attachment` | `sessionId`, message `seq`, and zero-based `index`. Returns the stored text attachment. |
| `_synth/load_image` | `sessionId`, message `seq`, and zero-based `index`. Returns one stored image as a base64 string. |
| `_synth/models` | `sessionId`. Returns cached offers, project recents, and pending provider lookups. The engine sends `_synth/models_updated` as lookups finish. |
| `_synth/providers` | `sessionId`. Returns provider IDs, hosts, connection state, and the active provider. |
| `_synth/connect_provider` | `sessionId`, provider ID, host, and optional API key. Connects or starts OAuth sign-in. |
| `_synth/cancel_sign_in` | `sessionId`. Cancels the provider sign-in in progress. |
| `_synth/sign_out` | `sessionId`. Signs out of the active OAuth provider. |
| `_synth/toggle_mcp` | `sessionId` and server name. Enables or disables a configured MCP server in the running session. |
| `$/cancel_request` | Notification with `requestId`. Withdraws an individual request. Withdrawing a prompt request leaves the turn running. |

The desktop composer uses three prompt block types:

- `{"type":"text","text":"…"}` contains Markdown, including `@path` and
  `@"path with spaces"` mentions resolved by the engine.
- `{"type":"resource","resource":{"uri":"snippet.txt","text":"…"}}` attaches
  explicitly supplied text.
- `{"type":"image","mimeType":"image/png","data":"…"}` attaches a base64 PNG.

The snapshot's `skills.found` entries contain `id`, `name`, `description`,
and source `dir`. Submit a skill by sending text that starts with `/id`. The
status's `vision` flag reports whether the active model can receive images.
A transcript message can include `image_count` without including image data.
Fetch each image on demand, including for messages loaded from history.

Subscribe before opening a session. `_synth/snapshot` may arrive before the
open or load reply. It replaces the session transcript and status, including
the current stream if present. `dropped` counts earlier messages still stored
by the engine. `_synth/appended` and `_synth/updated` carry a whole message
identified by `seq` within its session. `_synth/stream` adds text and reasoning
to a request number. Show the stream when that number matches the latest
`_synth/status` request. A finalized assistant message supersedes its stream.
`_synth/notice` carries a user-visible message. The `mcp` list in the status
reports each loaded server as `off`, `connecting`, `connected`, or `failed`,
with a reason when available. Every event names its session.
The engine can encode text payloads containing invalid UTF-8 as arrays of byte
values. The desktop client displays those payloads with replacement characters
where needed. The original bytes stay in the engine's data.

The router can host multiple sessions on the same connection. Replies can
arrive out of order. An incompatible attached endpoint can reject its
handshake. The router reports that error on the corresponding session request.

The router sends `_synth/session_stopped` with a session ID when an individual
engine process exits unexpectedly. Other sessions on the connection can continue.

Synth sends `session/request_permission` with a session, tool call and
available options. Reply with
`{"outcome":{"outcome":"selected","optionId":"<engine option ID>"}}`.
Synth sends `elicitation/create` with a form describing either an `answer`
field or a list of choices and an optional `other` field. Reply with
`{"action":"accept","content":{"answer":"…"}}` or
`{"action":"decline"}`. When the engine withdraws either request, discard it
using its exact RPC ID. This can happen when another client answers first.

Close stdin and continue draining stdout/stderr to disconnect gracefully.
The router applies the engine's existing last-client rules. A reconnect starts
a new router and loads known sessions by ID and working directory. The Swift
client reports each load failure and retains the last visible transcript.
It never replays prompts. Configuration, credentials and persistence stay
with the engine.
