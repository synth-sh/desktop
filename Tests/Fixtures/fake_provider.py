"""Run the Swift integration tests against a deterministic loopback provider."""

import argparse
import json
import os
import subprocess
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def send_body(self, data, content_type):
        self.send_response(200)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):
        if self.path == "/v1/models":
            models = (
                ["gpt-fixture-key"]
                if self.headers.get("Authorization") == "Bearer fixture-rotated-key"
                else ["gpt-fixture", "gpt-fixture-alt"]
            )
        elif self.path == "/alternate/v1/models":
            self.send_body(b'{"data":[{"id":"gpt-fixture-other-endpoint","context_length":262144},'
                           b'{"id":"gpt-fixture-small","context_length":4096}]}', "application/json")
            return
        elif self.path == "/api/tags":
            self.send_body(b'{"models":[{"model":"fixture-ollama"}]}', "application/json")
            return
        else:
            self.send_error(404)
            return
        self.send_body(json.dumps({"data": [{"id": model} for model in models]}).encode(), "application/json")

    def do_POST(self):
        request = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
        if self.path == "/api/show":
            if request["model"] == "fixture-ollama":
                self.send_body(b'{"model_info":{"fixture.context_length":262144}}', "application/json")
            else:
                self.send_error(404)
            return
        if self.path not in ("/v1/chat/completions", "/alternate/v1/chat/completions"):
            self.send_error(404)
            return
        messages = request["messages"]
        last = messages[-1]
        prompt = last.get("content")
        parts = prompt if isinstance(prompt, list) else []
        if parts:
            prompt = "".join(block.get("text", "") for block in parts)
        delta = {"content": "Fixture complete: " + str(prompt)[:120]}
        finish = "stop"

        if messages[0].get("content", "").startswith("You review actions an AI coding agent"):
            delta = {"content": "BLOCK\nVERDICT: BLOCK: Fixture denied this call"}

        if isinstance(prompt, str) and prompt.startswith("verify fixture attachments"):
            image_urls = [block["image_url"]["url"] for block in parts if block["type"] == "image_url"]
            valid = (
                prompt.count("<file path=\"project notes.txt\">") == 1
                and prompt.count("project fixture body") == 1
                and prompt.count("pasted fixture body") == 1
                and len(image_urls) == 1
                and image_urls[0].startswith("data:image/png;base64,")
            )
            delta = {"content": "Fixture attachments verified" if valid else "Fixture attachments incomplete"}

        if prompt == "check browser tools":
            browser_tools = {
                tool["function"]["name"]
                for tool in request.get("tools", [])
                if tool["function"]["name"].startswith("browser_")
            }
            delta = {"content": "Browser tools offered" if browser_tools else "Browser tools omitted"}

        if last["role"] == "user":
            tool = {
                "approve fixture write": (
                    "write",
                    {"path": "approved.txt", "content": "approved"},
                ),
                "deny fixture write": (
                    "write",
                    {"path": "denied.txt", "content": "denied"},
                ),
                "always allow fixture command": ("bash", {"command": "printf fixture"}),
                "block fixture auto approval": ("bash", {"command": "printf 'fixture should not run'"}),
                "read fixture bytes": ("read", {"path": "legacy.txt"}),
                "ask fixture choice": (
                    "ask_user",
                    {"question": "Choose a color", "options": ["Blue", "Green"]},
                ),
                "cancel fixture question": (
                    "ask_user",
                    {"question": "Will be cancelled"},
                ),
                "shared fixture question": (
                    "ask_user",
                    {"question": "Which client answers?"},
                ),
                "inspect fixture browser": ("browser_snapshot", {}),
                "cancel fixture browser": ("browser_snapshot", {}),
            }.get(prompt)
            if tool:
                name, arguments = tool
                delta = {
                    "tool_calls": [
                        {
                            "index": 0,
                            "id": "fixture-call",
                            "type": "function",
                            "function": {
                                "name": name,
                                "arguments": json.dumps(arguments),
                            },
                        }
                    ],
                }
                finish = "tool_calls"

        def frame(value):
            return ("data: " + json.dumps(value, ensure_ascii=False) + "\n\n").encode()

        frames = [
            frame(
                {"choices": [{"delta": {"reasoning_content": "Checking the fixture"}}]}
            ),
            frame({"choices": [{"delta": delta}]}),
            frame({"choices": [{"delta": {}, "finish_reason": finish}]}),
            b"data: [DONE]\n\n",
        ]
        self.send_response(200)
        self.send_header("Content-Type", "text/event-stream")
        self.send_header("Content-Length", str(sum(map(len, frames))))
        self.end_headers()
        try:
            for chunk in frames:
                self.wfile.write(chunk)
                self.wfile.flush()
                time.sleep(0.06)
        except (BrokenPipeError, ConnectionResetError):
            pass

    def log_message(self, *_):
        pass


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("engine", type=Path)
    parser.add_argument("swift_args", nargs=argparse.REMAINDER)
    args = parser.parse_args()
    engine = args.engine.resolve(strict=True)
    desktop = Path(__file__).resolve().parents[2]
    with ThreadingHTTPServer(("127.0.0.1", 0), Handler) as server:
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        env = {
            **os.environ,
            "SYNTH_TEST_ENGINE": str(engine),
            "SYNTH_TEST_PROVIDER": f"http://127.0.0.1:{server.server_port}/v1",
        }
        return subprocess.run(
            ["swift", "test", "--package-path", str(desktop), *args.swift_args],
            env=env,
            check=False,
        ).returncode


if __name__ == "__main__":
    raise SystemExit(main())
