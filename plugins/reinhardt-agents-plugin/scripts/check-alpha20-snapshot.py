#!/usr/bin/env python3
"""Compare the pinned feature graph to a verified framework source checkout."""
import argparse
import json
from pathlib import Path
import tomllib

ROOT = Path(__file__).resolve().parent.parent

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("framework_source", type=Path)
    args = parser.parse_args()
    snapshot = json.loads((ROOT / "compatibility/reinhardt-web-alpha20.json").read_text())
    manifest = tomllib.loads((args.framework_source / "Cargo.toml").read_text())
    expected = (snapshot["package"], snapshot["version"], snapshot["rust_version"], snapshot["features"])
    actual = (manifest["package"]["name"], manifest["package"]["version"],
              manifest["workspace"]["package"]["rust-version"], manifest["features"])
    if actual != expected:
        parser.exit(1, "Framework manifest differs from the pinned snapshot.\n")
    print("Framework manifest matches the 0.4.0-alpha.20 snapshot.")

if __name__ == "__main__":
    main()
