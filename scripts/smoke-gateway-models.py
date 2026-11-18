#!/usr/bin/env python3
"""Check explicit model discovery against a loopback server and a dummy API key."""

import argparse
import http.server
import json
import os
import subprocess
import tempfile
import threading
from pathlib import Path
from typing import ClassVar


class Gateway(http.server.BaseHTTPRequestHandler):
    status = 200
    payload = (
        b'{"data":[{"id":"fixture-z"},{"id":"provider/fixture-a"},{"id":"fixture-z"}]}'
    )
    requests: ClassVar[list] = []

    def log_message(self, *_):
        pass

    def do_GET(self):
        type(self).requests.append((self.path, self.headers.get("Authorization")))
        self.send_response(type(self).status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(type(self).payload)))
        if type(self).status == 302:
            self.send_header("Location", "/must-not-follow")
        self.end_headers()
        try:
            self.wfile.write(type(self).payload)
        except (BrokenPipeError, ConnectionResetError):
            # The client closes the connection when the response exceeds its limit.
            pass


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--binary", type=Path)
    args = parser.parse_args()
    root = Path(__file__).resolve().parent.parent
    if args.binary is None:
        subprocess.run([str(root / "scripts/build.sh")], cwd=root, check=True)
    binary = (args.binary or root / "_build/default/bin/main.exe").resolve()
    checks = 0

    def check(name, condition):
        nonlocal checks
        checks += 1
        if not condition:
            raise AssertionError(name)

    with tempfile.TemporaryDirectory(prefix="factory-models-") as temporary:
        directory = Path(temporary).resolve()
        home = directory / "home"
        home.mkdir()
        # Discovery must ignore user curl configuration, including header/URL changes.
        (home / ".curlrc").write_text('url = "http://127.0.0.1:1/must-not-contact"\n')
        key = 'dummy-fixture-key-with-"quotes"-and-\\slash'
        config = directory / "gateway.toml"
        config.write_text(
            'base_url_environment="LITELLM_BASE_URL"\nkey_environment="LITELLM_API_KEY"\n'
        )
        env = {
            name: os.environ[name] for name in ("PATH", "LANG") if name in os.environ
        }
        env.update(HOME=str(home), XDG_CONFIG_HOME=str(home), TMPDIR=str(directory))
        with http.server.ThreadingHTTPServer(("127.0.0.1", 0), Gateway) as server:
            worker = threading.Thread(target=server.serve_forever, daemon=True)
            worker.start()
            try:
                env.update(
                    LITELLM_BASE_URL=f"http://127.0.0.1:{server.server_port}/v1/",
                    LITELLM_API_KEY=key,
                )

                def invoke(extra=(), environment=None):
                    return subprocess.run(
                        [
                            str(binary),
                            "--list-models",
                            "--gateway",
                            str(config),
                            *extra,
                        ],
                        check=False,
                        env=env if environment is None else environment,
                        capture_output=True,
                        text=True,
                        timeout=15,
                        cwd=directory,
                    )

                result = subprocess.run(
                    [str(binary), "--check-gateway", str(config)],
                    check=False,
                    env={
                        name: value
                        for name, value in env.items()
                        if name != "LITELLM_API_KEY"
                    },
                    capture_output=True,
                    text=True,
                    timeout=5,
                )
                check(
                    "setup check resolves URL without a key or request",
                    result.returncode == 0 and not Gateway.requests,
                )
                result = invoke()
                check(
                    "model discovery succeeds without a terminal",
                    result.returncode == 0,
                )
                response = json.loads(result.stdout)
                check(
                    "catalogue sorted and deduplicated",
                    response["models"] == ["fixture-z", "provider/fixture-a"],
                )
                check(
                    "discovery discloses no compatibility proof or agent start",
                    response["starts_agent"] is False
                    and response["compatibility_verified"] is False,
                )
                check(
                    "one request carries exact path and dummy auth header",
                    Gateway.requests == [("/v1/models", "Bearer " + key)],
                )
                check(
                    "key is absent from CLI output",
                    key not in result.stdout + result.stderr,
                )
                count = len(Gateway.requests)
                for missing in ("LITELLM_BASE_URL", "LITELLM_API_KEY"):
                    result = invoke(
                        environment={
                            name: value
                            for name, value in env.items()
                            if name != missing
                        }
                    )
                    check(
                        "missing environment prevents request",
                        result.returncode == 2
                        and len(Gateway.requests) == count
                        and result.stdout == "",
                    )
                for extra in (
                    ["--snapshot"],
                    ["--run-codex"],
                    ["--live-ui"],
                    ["--dry-run-codex"],
                    ["--database", str(directory / "must-not-create.sqlite")],
                    ["--fake-harness"],
                    ["--config", str(config)],
                    ["--check-config", str(config)],
                    ["--no-config"],
                ):
                    result = invoke(extra)
                    check(
                        "conflicting modes rejected before network/storage",
                        result.returncode == 2
                        and len(Gateway.requests) == count
                        and not (directory / "must-not-create.sqlite").exists(),
                    )
                for status, diagnostic in (
                    (401, "authentication"),
                    (403, "authentication"),
                    (404, "endpoint"),
                    (429, "rate-limited"),
                    (503, "HTTP status"),
                    (302, "HTTP status"),
                ):
                    Gateway.status = status
                    Gateway.payload = ("Untrusted response echoes " + key).encode()
                    result = invoke()
                    check(
                        "HTTP failure returns bounded safe diagnostic",
                        result.returncode == 2
                        and diagnostic in result.stderr
                        and result.stdout == ""
                        and key not in result.stderr,
                    )
                check(
                    "redirect is never followed with credentials",
                    all(path == "/v1/models" for path, _ in Gateway.requests),
                )
                Gateway.status = 200
                for payload in (
                    b"not-json",
                    b'{"data":[{"id":"bad\\nmodel"}]}',
                    json.dumps({"data": [{"id": key}]}).encode(),
                    b"x" * 1048577,
                ):
                    Gateway.payload = payload
                    result = invoke()
                    check(
                        "invalid or secret-bearing body withheld",
                        result.returncode == 2
                        and result.stdout == ""
                        and key not in result.stderr,
                    )
                config.write_text(
                    f'base_url="http://127.0.0.1:{server.server_port}"\nkey_environment="LITELLM_API_KEY"\n'
                )
                Gateway.payload = b'{"data":[]}'
                result = invoke()
                check(
                    "root API base requests /models without guessing v1",
                    Gateway.requests[-1][0] == "/models",
                )
                check(
                    "empty model catalogue reported accurately",
                    result.returncode == 0
                    and json.loads(result.stdout)["models"] == [],
                )
            finally:
                server.shutdown()
                worker.join()
        check(
            "discovery leaves no database or credential file",
            sorted(path.name for path in directory.iterdir())
            == ["gateway.toml", "home"]
            and sorted(path.name for path in home.iterdir()) == [".curlrc"],
        )
    print(
        f"Passed {checks} model-discovery CLI checks. Loopback and dummy key only; no agent or real gateway."
    )


if __name__ == "__main__":
    main()
