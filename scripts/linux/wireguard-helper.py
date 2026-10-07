#!/usr/bin/python3 -I
"""Narrow root-owned WireGuard disk configuration bridge; never activates tunnels.

Install root-owned at /usr/local/libexec/initial-setup-wireguard-helper.
Policy: /etc/initial-setup/wireguard-sync.json, root:root 0600:
{"schema_version":1,"uid":1000,"device_id":"laptop","tunnels":["wg0"]}
All secret transport uses caller-owned protected files, never stdout/stderr.
"""
import argparse
import contextlib
import fcntl
import hashlib
import json
import os
import re
import stat
import sys
import uuid

POLICY = "/etc/initial-setup/wireguard-sync.json"
CONFIG_ROOT = "/etc/wireguard"
LIMIT = 4 * 1024 * 1024
NAME = re.compile(r"[a-zA-Z0-9_=+.-]{1,15}\Z")
DEVICE = re.compile(r"[a-zA-Z0-9][a-zA-Z0-9_-]{0,40}\Z")


class Refused(Exception):
    pass


def require(condition):
    if not condition:
        raise Refused()


@contextlib.contextmanager
def directory(path):
    """Pin each directory with openat + O_NOFOLLOW (including every ancestor)."""
    require(os.path.isabs(path) and ".." not in path.split("/"))
    fd = os.open("/", os.O_RDONLY | os.O_DIRECTORY)
    try:
        for part in path.split("/"):
            if not part or part == ".":
                continue
            next_fd = os.open(part, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=fd)
            os.close(fd)
            fd = next_fd
        yield fd
    finally:
        os.close(fd)


def private_info(info, uid):
    require(info.st_uid == uid and not (info.st_mode & 0o077))


def read_at(fd, name, uid, optional=False):
    try:
        handle = os.open(name, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK, dir_fd=fd)
    except FileNotFoundError:
        if optional:
            return None
        raise
    with os.fdopen(handle, "rb") as stream:
        info = os.fstat(stream.fileno())
        require(stat.S_ISREG(info.st_mode) and info.st_nlink == 1)
        private_info(info, uid)
        require(info.st_size <= LIMIT)
        value = stream.read(LIMIT + 1)
        require(len(value) <= LIMIT)
        return value


def write_at(fd, name, value, uid, gid):
    require("/" not in name and name not in [".", ".."])
    require(len(value) <= LIMIT)
    handle = os.open(name, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600, dir_fd=fd)
    with os.fdopen(handle, "wb") as stream:
        os.fchown(stream.fileno(), uid, gid)
        stream.write(value)
        stream.flush()
        os.fsync(stream.fileno())


def encoded(value):
    return json.dumps(value, sort_keys=True, separators=(",", ":")).encode()


def digest(value):
    return hashlib.sha256(value).hexdigest() if value is not None else ""


def validate_names(names):
    require(isinstance(names, list) and 0 < len(names) <= 128)
    require(all(isinstance(n, str) and NAME.fullmatch(n) and n not in [".", ".."] for n in names))
    require(len(set(names)) == len(names))


def validate_config(value, restore=False):
    require(isinstance(value, str) and len(value.encode()) <= LIMIT and "\x00" not in value)
    require(len(re.findall(r"(?m)^\s*\[Interface\]\s*$", value)) == 1)
    # Imported hooks are privileged code when wg-quick later runs. This bridge
    # intentionally does not authorize transferring executable hooks.
    if restore:
        require(not re.search(r"(?im)^\s*(PreUp|PostUp|PreDown|PostDown)\s*=", value))
        require(not re.search(r"(?im)^\s*SaveConfig\s*=\s*true\s*(?:#.*)?$", value))
    return value.encode()


def validate_bundle(bundle, device, names):
    require(isinstance(bundle, dict) and bundle.get("schema_version") == 1)
    require(bundle.get("device_id") == device)
    rows = bundle.get("tunnels")
    require(isinstance(rows, list) and len(rows) == len(names))
    require(all(isinstance(r, dict) and set(r) == {"name", "config"} for r in rows))
    require(sorted(r["name"] for r in rows) == sorted(names))
    return {r["name"]: validate_config(r["config"], restore=True) for r in rows}


def trusted_install():
    path = os.path.abspath(__file__)
    for target in [path, os.path.dirname(path), os.path.dirname(os.path.dirname(path))]:
        info = os.lstat(target)
        require(info.st_uid == 0 and not (info.st_mode & 0o022) and not stat.S_ISLNK(info.st_mode))


def run(action, request_path, response_path):
    require(sys.platform.startswith("linux") and os.geteuid() == 0)
    trusted_install()
    uid = int(os.environ.get("SUDO_UID", "-1"))
    gid = int(os.environ.get("SUDO_GID", "-1"))
    require(uid > 0 and gid >= 0)
    with directory(os.path.dirname(POLICY)) as policy_fd:
        private_info(os.fstat(policy_fd), 0)
        policy = json.loads(read_at(policy_fd, os.path.basename(POLICY), 0))
    require(policy.get("schema_version") == 1 and policy.get("uid") == uid)
    names = policy.get("tunnels")
    validate_names(names)
    device = policy.get("device_id")
    require(isinstance(device, str) and DEVICE.fullmatch(device))
    parent = os.path.dirname(request_path)
    require(os.path.isabs(request_path) and os.path.dirname(response_path) == parent)
    with directory(parent) as exchange, directory(CONFIG_ROOT) as root:
        private_info(os.fstat(exchange), uid)
        private_info(os.fstat(root), 0)
        request = json.loads(read_at(exchange, os.path.basename(request_path), uid))
        require(request.get("schema_version") == 1 and request.get("device_id") == device)
        require(request.get("tunnels") == names)
        bundle_path = request.get("bundle_path")
        require(isinstance(bundle_path, str) and os.path.dirname(bundle_path) == parent)
        bundle_name = os.path.basename(bundle_path)
        require(bundle_name not in [os.path.basename(request_path), os.path.basename(response_path)])
        # Root-owned lock serializes all helper operations. No global temp paths.
        lock = os.open(".initial-setup-sync.lock", os.O_RDWR | os.O_CREAT | os.O_NOFOLLOW, 0o600, dir_fd=root)
        try:
            require(stat.S_ISREG(os.fstat(lock).st_mode))
            private_info(os.fstat(lock), 0)
            fcntl.flock(lock, fcntl.LOCK_EX)
            current = {n: read_at(root, n + ".conf", 0, optional=True) for n in names}
            if action == "capture":
                rows = [{"name": n, "config": current[n].decode("utf-8")} for n in names if current[n] is not None]
                for row in rows:
                    validate_config(row["config"])
                write_at(exchange, bundle_name, encoded({"schema_version": 1, "device_id": device, "tunnels": rows}), uid, gid)
                result = {"ok": True, "baseline": {n: digest(v) for n, v in current.items()}}
            else:
                incoming = validate_bundle(json.loads(read_at(exchange, bundle_name, uid)), device, names)
                require(not any(os.path.exists("/sys/class/net/" + name) for name in names))
                # An active wg-quick SaveConfig can undo an apparently successful
                # restore on shutdown; fail before modifying such configurations.
                for value in current.values():
                    if value is not None:
                        validate_config(value.decode("utf-8"), restore=True)
                baseline = {n: digest(v) for n, v in current.items()}
                result = {"ok": True, "baseline": baseline}
                if action == "restore":
                    require(request.get("baseline") == baseline)
                    result["recovery"] = commit(root, current, incoming)
            write_at(exchange, os.path.basename(response_path), encoded(result), uid, gid)
        finally:
            os.close(lock)


def commit(root, current, incoming):
    backup_name = ".initial-setup-backup-" + str(uuid.uuid4())
    os.mkdir(backup_name, 0o700, dir_fd=root)
    backup = os.open(backup_name, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=root)
    changed = []
    candidates = []
    try:
        for name, value in current.items():
            if value is not None:
                write_at(backup, name + ".conf", value, 0, 0)
        os.fsync(backup)
        for name, value in incoming.items():
            candidate = ".initial-setup-new-" + str(uuid.uuid4())
            write_at(root, candidate, value, 0, 0)
            candidates.append((name, candidate))
        for name, candidate in candidates:
            require(read_at(root, name + ".conf", 0, optional=True) == current[name])
            os.replace(candidate, name + ".conf", src_dir_fd=root, dst_dir_fd=root)
            changed.append(name)
        os.fsync(root)
    except Exception:
        for name in reversed(changed):
            if current[name] is None:
                os.unlink(name + ".conf", dir_fd=root)
            else:
                candidate = ".initial-setup-rollback-" + str(uuid.uuid4())
                write_at(root, candidate, current[name], 0, 0)
                os.replace(candidate, name + ".conf", src_dir_fd=root, dst_dir_fd=root)
        raise
    finally:
        for _, candidate in candidates:
            try:
                os.unlink(candidate, dir_fd=root)
            except FileNotFoundError:
                pass
        os.close(backup)
    return CONFIG_ROOT + "/" + backup_name


def main():
    parser = argparse.ArgumentParser(description="Protected WireGuard configuration bridge")
    parser.add_argument("action", choices=["capture", "validate", "restore"])
    parser.add_argument("--request", required=True)
    parser.add_argument("--response", required=True)
    args = parser.parse_args()
    try:
        run(args.action, args.request, args.response)
    except Exception:
        # Never render exceptions: parsing or OS errors can include secret data.
        print("WireGuard helper refused the operation; verify policy, protected paths, privileges, configuration compatibility and unchanged baseline.", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
