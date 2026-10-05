#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# dependencies = ["pathspec>=0.12"]
# ///
"""Run ci_verify.sh on the services a team owns, from its CODEOWNERS section.

CODEOWNERS sections are the team -> paths map for this repo (see
'CODEOWNERS' in the repo root): '[Controls]', '[Data Acquisition]' and
'[Tech UI]' -- '# [Controls]' etc. on GitHub, where section headers are
comments rather than CODEOWNERS syntax.
This reads the section for the given team, matches it against services/*,
and runs ci_verify.sh with just that list, so a team's CI -- or a developer
working locally -- checks only the services it owns. ci_verify.sh's
per-service checks (the runtime-lock.yaml pattern check and the helm chart
lint/template loop) are scoped by that service list; its pre-commit step is
scoped separately, by CI_VERIFY_TEAM_FILES below, to every tracked file the
team's CODEOWNERS section matches -- including shared files such as
services/values.yaml or .helm-shared/ that aren't under any one service's
directory. A file more than one section claims is scoped into each of their
runs.

Self-contained via a uv shebang and PEP 723 inline dependencies: no venv or
requirements.txt change needed to run it.
"""

import os
import re
import subprocess
import sys
from pathlib import Path

import pathspec

ALIASES = {"controls": "controls", "daq": "data acquisition", "techui": "tech ui"}
# [Name], ^[Name], [Name][2], each optionally followed by owners; '# ' may
# lead on GitHub, where section headers are comments (GitHub has no sections)
SECTION = re.compile(r"^(?:#\s*)?\^?\[([^\]]+)\]")


def sections(codeowners: Path) -> dict[str, list[str]]:
    result: dict[str, list[str]] = {}
    current = None
    for line in codeowners.read_text().splitlines():
        line = line.strip()
        if not line:
            continue
        if match := SECTION.match(line):
            current = match.group(1).strip().lower()
            result.setdefault(current, [])
        elif line.startswith("#"):
            continue
        elif current is not None:
            result[current].append(line.split()[0])
    return result


def main() -> None:
    args = sys.argv[1:]
    dry_run = "--dry-run" in args
    args = [a for a in args if a != "--dry-run"]
    if len(args) != 1 or args[0] not in ALIASES:
        sys.exit(f"usage: {sys.argv[0]} {'|'.join(ALIASES)} [--dry-run]")
    root = Path(__file__).resolve().parent
    codeowners = root / "CODEOWNERS"
    if not codeowners.exists():
        sys.exit(f"no {codeowners} file")

    all_sections = sections(codeowners)
    team = ALIASES[args[0]]
    if team not in all_sections:
        sys.exit(
            f"no [{team}] section in {codeowners} (expected layout: "
            "'[Controls]', '[Data Acquisition]' and '[Tech UI]' sections, "
            "as the template's CODEOWNERS.jinja generates)"
        )

    services = sorted(
        d.name
        for d in (root / "services").iterdir()
        if d.is_dir() and not d.name.startswith(".")
    )

    def owned(patterns: list[str]) -> set[str]:
        spec = pathspec.PathSpec.from_lines("gitwildmatch", patterns)
        return {s for s in services if spec.match_file(f"services/{s}/")}

    claimed = set().union(*(owned(p) for p in all_sections.values()))
    for service in sorted(set(services) - claimed):
        print(f"WARNING: services/{service} is not in any CODEOWNERS section")

    mine = sorted(owned(all_sections[team]))
    if not mine:
        sys.exit(f"no service matches the [{team}] section")
    print(f"[{team}]: {' '.join(mine)}")
    if not dry_run:
        tracked = subprocess.run(
            ["git", "ls-files"], cwd=root, capture_output=True, text=True, check=True
        ).stdout.splitlines()
        spec = pathspec.PathSpec.from_lines("gitwildmatch", all_sections[team])
        team_files = sorted(f for f in tracked if spec.match_file(f))
        env = os.environ.copy()
        env["CI_VERIFY_TEAM_FILES"] = "\n".join(team_files)
        sys.exit(subprocess.call([str(root / "ci_verify.sh"), *mine], env=env))


if __name__ == "__main__":
    main()
