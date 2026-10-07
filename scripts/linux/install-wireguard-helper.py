#!/usr/bin/env python3
"""Explicit one-time Linux privilege enrollment, run as the ordinary user.

Example: python3 scripts/linux/install-wireguard-helper.py --device laptop --tunnel wg0
Installs only a root-owned fixed helper and root-owned uid/device/tunnel policy.
Uses sudo for install primitives, never executes a checkout script as root.
"""
import argparse
import json
import os
import re
import subprocess
import sys
import tempfile
from pathlib import Path


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--device", required=True)
    parser.add_argument("--tunnel", action="append", required=True)
    args = parser.parse_args()
    if not sys.platform.startswith("linux") or os.getuid() == 0:
        parser.error("Run on Linux as the ordinary sync user, not with sudo.")
    if not re.fullmatch(r"[a-zA-Z0-9][a-zA-Z0-9_-]{0,40}", args.device):
        parser.error("Invalid device id.")
    if len(args.tunnel) != len(set(args.tunnel)) or any(not re.fullmatch(r"[a-zA-Z0-9_=+.-]{1,15}", n) or n in [".", ".."] for n in args.tunnel):
        parser.error("Invalid or duplicate tunnel name.")
    source = Path(__file__).resolve().with_name("wireguard-helper.py")
    helper = "/usr/local/libexec/initial-setup-wireguard-helper"
    subprocess.run(["sudo", "-v"], check=True)
    with tempfile.TemporaryDirectory(prefix="wireguard-enroll-") as temporary:
        policy = Path(temporary) / "policy.json"
        policy.write_text(json.dumps({"schema_version": 1, "uid": os.getuid(), "device_id": args.device, "tunnels": args.tunnel}))
        policy.chmod(0o600)
        sudoers = Path(temporary) / "sudoers"
        sudoers.write_text("# Initial-setup: helper itself enforces uid and tunnel allowlists.\n#" + str(os.getuid()) + " ALL=(root) NOPASSWD: " + helper + "\n")
        sudoers.chmod(0o600)
        # Validate before any policy/privilege mutation.
        subprocess.run(["sudo", "/usr/sbin/visudo", "-cf", str(sudoers)], check=True)
        for path, mode in [("/usr/local/libexec", "755"), ("/etc/initial-setup", "700"), ("/etc/wireguard", "700")]:
            subprocess.run(["sudo", "/usr/bin/install", "-d", "-o", "root", "-g", "root", "-m", mode, path], check=True)
        for src, destination, mode in [(source, helper, "755"), (policy, "/etc/initial-setup/wireguard-sync.json", "600"), (sudoers, "/etc/sudoers.d/initial-setup-wireguard", "440")]:
            subprocess.run(["sudo", "/usr/bin/install", "-o", "root", "-g", "root", "-m", mode, str(src), destination], check=True)
    print("WireGuard helper enrolled. Configure machine-local wireguard.nuon with the same device and tunnel list. No tunnel was activated.")


if __name__ == "__main__":
    main()
