#!/usr/bin/env python3
"""Build anonymized Codex rollout fixtures from a local corpus.

The Codex transcript format drifts between releases, and a single machine keeps
files written by many versions at once, so regression tests need real samples
per version rather than one hand-written example.

Nothing user-authored may ship into the repository. Redaction is therefore an
**allow-list**: a string value survives only if its key is one the decoder
actually reads *and* the value matches the shape that key is expected to have.
Everything else — prompts, model output, tool arguments, encrypted blobs, URLs,
absolute paths, and any field a future Codex release invents — is replaced with
a placeholder derived from a hash, so repeated runs produce identical output and
diffs stay reviewable.

A deny-list was tried first and leaked immediately: real transcripts nest user
content under dozens of key names, including ones that did not exist when the
list was written.

Usage:
    python3 scripts/codex-fixtures.py --source ~/.codex/sessions \\
        --out Tests/Fixtures/codex-rollouts [--per-version 2] [--max-lines 250]
"""

from __future__ import annotations

import argparse
import hashlib
import json
import pathlib
import re
import shutil
import sys
from collections import defaultdict

# Keys whose *string* values the decoder branches on. Values are additionally
# validated against ENUM_SHAPE below before being kept.
STRUCTURAL_KEYS = {
    "type",            # record type — the decoder's primary key
    "role",            # user / assistant
    "originator",      # surface classification
    "cli_version",     # version attribution for drift reports
    "thread_source",
    "history_mode",
    "other",           # subagent kind, e.g. "guardian"
    "status",
    "model_provider",
}

# `source` is polymorphic: a short enum string, or an object describing a
# spawned thread. Both shapes must survive intact — reproducing that split is
# the whole point of the edge fixtures.
POLY_KEYS = {"source"}

# Identifier keys: real UUIDs are replaced with deterministic fake ones so
# cross-file relationships (parent/child threads) stay intact without shipping
# anything that could be correlated back to a real session.
ID_KEYS = {
    "id", "session_id", "thread_id", "parent_thread_id",
    "parent_turn_id", "turn_id", "window_id", "call_id", "tool_call_id",
}

# Path-shaped keys keep a plausible path so workspace-name derivation still has
# something realistic to parse.
PATH_KEYS = {"cwd", "path", "file", "filename", "transcript_path", "workdir"}

# Timestamps are kept: ordering matters to the decoder and they carry no content.
TIME_KEYS = {"timestamp", "created_at", "updated_at"}

# A structural value must look like an identifier/enum/version — never prose.
ENUM_SHAPE = re.compile(r"^[A-Za-z0-9 ._@:-]{0,64}$")

UUID_SHAPE = re.compile(
    r"^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$"
)


def digest(value: str) -> str:
    return hashlib.sha256(value.encode("utf-8", "replace")).hexdigest()


def fake_uuid(value: str) -> str:
    h = digest(value)
    return f"{h[0:8]}-{h[8:12]}-{h[12:16]}-{h[16:20]}-{h[20:32]}"


def redact(value: str) -> str:
    return f"[redacted {len(value)}b {digest(value)[:8]}]"


def scrub(node, key: str | None = None):
    if isinstance(node, dict):
        return {k: scrub(v, k) for k, v in node.items()}
    if isinstance(node, list):
        return [scrub(v, key) for v in node]
    if isinstance(node, bool) or isinstance(node, (int, float)) or node is None:
        return node
    if not isinstance(node, str):
        return redact(str(node))

    if key in ID_KEYS:
        return fake_uuid(node) if UUID_SHAPE.match(node) else redact(node)
    if key in TIME_KEYS:
        return node
    if key in PATH_KEYS:
        return f"/Users/dev/work/ws-{digest(node)[:8]}"
    if key in POLY_KEYS or key in STRUCTURAL_KEYS:
        # Keep only if it genuinely looks like an enum or version token.
        return node if ENUM_SHAPE.match(node) else redact(node)
    return redact(node)


def scrub_line(line: str) -> str | None:
    try:
        record = json.loads(line)
    except json.JSONDecodeError:
        return None
    if not isinstance(record, dict):
        return None
    return json.dumps(scrub(record), ensure_ascii=False, sort_keys=True)


def read_header(path: pathlib.Path) -> dict | None:
    try:
        with path.open("r", encoding="utf-8", errors="replace") as handle:
            first = handle.readline()
    except OSError:
        return None
    try:
        record = json.loads(first)
    except json.JSONDecodeError:
        return None
    if record.get("type") != "session_meta":
        return None
    return record.get("payload") or {}


KNOWN_ORIGINATORS = {
    "codex-tui", "Codex Desktop", "codex_work_desktop", "codex_exec",
}


def classify(payload: dict) -> str:
    """Bucket a transcript so edge cases are guaranteed representation."""
    if isinstance(payload.get("source"), dict):
        return "edge-subagent"
    if (payload.get("originator") or "") not in KNOWN_ORIGINATORS:
        return "edge-originator"
    return payload.get("cli_version") or "unknown"


def verify(out: pathlib.Path) -> list[str]:
    """Fail loudly if anything that looks like user content survived."""
    problems: list[str] = []
    suspicious = re.compile(r"/Users/(?!dev/work)|[A-Za-z0-9+/]{60,}={0,2}|https?://")
    for path in sorted(out.rglob("*.jsonl")):
        for number, line in enumerate(path.open(encoding="utf-8"), start=1):
            record = json.loads(line)

            def walk(node, key=None):
                if isinstance(node, dict):
                    for k, v in node.items():
                        walk(v, k)
                elif isinstance(node, list):
                    for v in node:
                        walk(v, key)
                elif isinstance(node, str):
                    if node.startswith("[redacted "):
                        return
                    if key in TIME_KEYS or key in ID_KEYS:
                        return
                    if len(node) > 64:
                        problems.append(f"{path}:{number} long value under '{key}'")
                    elif suspicious.search(node):
                        problems.append(f"{path}:{number} suspicious value under '{key}'")

            walk(record)
    return problems


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", required=True, type=pathlib.Path)
    parser.add_argument("--out", required=True, type=pathlib.Path)
    parser.add_argument("--per-version", type=int, default=2)
    parser.add_argument("--max-lines", type=int, default=250)
    args = parser.parse_args()

    source = args.source.expanduser()
    if not source.exists():
        print(f"source not found: {source}", file=sys.stderr)
        return 1

    buckets: dict[str, list[pathlib.Path]] = defaultdict(list)
    scanned = 0
    for path in sorted(source.rglob("rollout-*.jsonl")):
        scanned += 1
        payload = read_header(path)
        if payload is None:
            continue
        buckets[classify(payload)].append(path)

    if args.out.exists():
        shutil.rmtree(args.out)
    args.out.mkdir(parents=True, exist_ok=True)

    written = 0
    for bucket, paths in sorted(buckets.items()):
        quota = args.per_version * 2 if bucket.startswith("edge") else args.per_version
        target = args.out / bucket.replace("/", "_")
        target.mkdir(parents=True, exist_ok=True)
        for index, path in enumerate(paths[:quota]):
            lines: list[str] = []
            with path.open("r", encoding="utf-8", errors="replace") as handle:
                for raw in handle:
                    if len(lines) >= args.max_lines:
                        break
                    cleaned = scrub_line(raw)
                    if cleaned:
                        lines.append(cleaned)
            if not lines:
                continue
            (target / f"sample-{index:02d}.jsonl").write_text(
                "\n".join(lines) + "\n", encoding="utf-8"
            )
            written += 1
        print(f"{bucket}: {min(len(paths), quota)} of {len(paths)}")

    print(f"\nscanned {scanned} transcripts, wrote {written} fixtures")

    problems = verify(args.out)
    if problems:
        print(f"\nREDACTION CHECK FAILED — {len(problems)} issue(s):", file=sys.stderr)
        for line in problems[:20]:
            print(f"  {line}", file=sys.stderr)
        return 2

    print("Redaction check passed: no long, path-like, or encoded values remain.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
