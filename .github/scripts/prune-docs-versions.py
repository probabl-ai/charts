#!/usr/bin/env python3
"""Prune old documentation versions from the gh-pages branch.

Released documentation is versioned with mike. Keep the `dev` version and the
`KEEP` most recent release versions; delete anything older. The `latest` alias
always points at the newest release and is left untouched.
"""

import json
import re
import subprocess
import sys

KEEP = 10

# Release versions, including pre-release suffixes (0.2.0, 0.2.0-rc1, ...).
SEMVER = re.compile(r"^(\d+)\.(\d+)\.(\d+)(?:-([0-9A-Za-z.-]+))?$")


def version_key(version: str) -> tuple | None:
    """Sort key for a release version; a pre-release sorts before its release."""
    match = SEMVER.match(version)
    if not match:
        return None
    major, minor, patch, pre = match.groups()
    return (int(major), int(minor), int(patch), pre is None, pre or "")


def read_versions() -> list[dict]:
    for ref in ("gh-pages", "origin/gh-pages"):
        try:
            return json.loads(
                subprocess.check_output(
                    ["git", "show", f"{ref}:docs/versions.json"],
                    text=True,
                    stderr=subprocess.DEVNULL,
                )
            )
        except subprocess.CalledProcessError:
            continue
    raise SystemExit("Could not find docs/versions.json on the gh-pages branch")


def release_versions(versions: list[dict]) -> list[str]:
    """Release version names, newest first."""
    return sorted(
        (entry["version"] for entry in versions if version_key(entry["version"])),
        key=version_key,
        reverse=True,
    )


def newest() -> None:
    releases = release_versions(read_versions())
    if releases:
        print(releases[0])


def main() -> None:
    releases = release_versions(read_versions())
    obsolete = releases[KEEP:]

    if not obsolete:
        print(f"{len(releases)} documentation release(s); nothing to prune")
        return

    subprocess.run(
        ["mike", "delete", "--push", "--deploy-prefix", "docs", *obsolete],
        check=True,
    )
    print(f"Pruned documentation versions: {', '.join(obsolete)}")


if __name__ == "__main__":
    if sys.argv[1:] == ["--newest"]:
        newest()
    else:
        main()
