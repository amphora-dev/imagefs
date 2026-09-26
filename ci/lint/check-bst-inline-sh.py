#!/usr/bin/env python3
"""POSIX-check the inline commands of every BuildStream element.

BuildStream runs each *-commands entry with `sh -c -e` inside the sandbox, and
the host SDK is Ubuntu, so /bin/sh is dash. Bash-only syntax such as
`${var:0:8}` passes locally under bash and then fails in CI with
"Bad substitution" (build-box64 run 36211466431). Anything beyond a few lines
belongs in a `ci/**/*.sh` bash script invoked as `bash .bst/...`; this check
keeps what remains inline POSIX.

Each command is written to a temp file and run through `shellcheck -s sh`.
BuildStream `%{var}` substitutions are replaced with a placeholder first.
"""
from __future__ import annotations

import argparse
import re
import subprocess
import sys
import tempfile
from pathlib import Path

import yaml

ROOT = Path(__file__).resolve().parents[2]
ELEMENTS = ROOT / "buildstream" / "elements"
BST_VAR = re.compile(r"%\{[A-Za-z0-9_-]+\}")
# SC2154: vars come from the element/project environment.
# SC1091: sourced paths only exist inside the sandbox.
# SC2115: `rm -rf "$root/..."` roots are assigned from %{install-root}, never empty.
# SC2034: unused locals are harmless; editing an element only to drop one
#         would invalidate its cache key and rebuild every dependent.
EXCLUDES = "SC2154,SC1091,SC2115,SC2034"


def command_lists(doc: dict) -> list[tuple[str, list[str]]]:
    config = doc.get("config") or {}
    found = []
    for key, value in config.items():
        if not key.endswith("-commands") or not isinstance(value, list):
            continue
        found.append((key, [c for c in value if isinstance(c, str)]))
    return found


def check_element(path: Path, tmpdir: Path) -> list[str]:
    try:
        doc = yaml.safe_load(path.read_text(encoding="utf-8"))
    except yaml.YAMLError as exc:
        return [f"{path}: YAML error: {exc}"]
    if not isinstance(doc, dict):
        return []
    failures = []
    rel = path.relative_to(ROOT)
    for key, commands in command_lists(doc):
        for index, command in enumerate(commands):
            script = tmpdir / f"{rel.as_posix().replace('/', '__')}.{key}.{index}.sh"
            script.write_text(BST_VAR.sub("BSTVAR", command), encoding="utf-8")
            result = subprocess.run(
                ["shellcheck", "-s", "sh", "-S", "warning", "-e", EXCLUDES, "-f", "gcc", str(script)],
                capture_output=True,
                text=True,
            )
            if result.returncode != 0:
                out = result.stdout.replace(str(script), f"{rel}[{key}][{index}]")
                failures.append(out.rstrip())
    return failures


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("elements", nargs="*", type=Path, help="default: all .bst under buildstream/elements")
    args = parser.parse_args()
    paths = [p.resolve() for p in args.elements] or sorted(ELEMENTS.rglob("*.bst"))
    if not paths:
        print(f"no .bst elements found under {ELEMENTS}", file=sys.stderr)
        return 1
    failures: list[str] = []
    with tempfile.TemporaryDirectory() as tmp:
        for path in paths:
            failures.extend(check_element(path, Path(tmp)))
    print(f"checked {len(paths)} elements")
    if failures:
        print("\n".join(failures))
        print(
            "\nInline BuildStream commands run under POSIX sh (dash). "
            "Move bash logic into a ci/**/*.sh script and call it with `bash .bst/...`.",
            file=sys.stderr,
        )
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
