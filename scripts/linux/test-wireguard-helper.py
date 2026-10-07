"""Host-independent tests of privileged helper invariants, using dummy configs."""
import contextlib
import importlib.util
import json
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location("wg_helper", Path(__file__).with_name("wireguard-helper.py"))
helper = importlib.util.module_from_spec(spec)
spec.loader.exec_module(helper)
CONFIG = "[Interface]\nPrivateKey = FIXTURE_NOT_A_REAL_KEY\nAddress = 10.0.0.2/32\n"


class HelperTests(unittest.TestCase):
    def test_device_and_name_binding(self):
        bundle = {"schema_version": 1, "device_id": "laptop", "tunnels": [{"name": "wg0", "config": CONFIG}]}
        self.assertEqual(helper.validate_bundle(bundle, "laptop", ["wg0"]), {"wg0": CONFIG.encode()})
        with self.assertRaises(helper.Refused):
            helper.validate_bundle(bundle, "desktop", ["wg0"])
        with self.assertRaises(helper.Refused):
            helper.validate_bundle(bundle, "laptop", ["wg1"])

    def test_rejects_privileged_hooks_and_saveconfig(self):
        for dangerous in ["PostUp = do-not-run", "PreDown = do-not-run", "SaveConfig = true"]:
            with self.assertRaises(helper.Refused):
                helper.validate_config(CONFIG + dangerous + "\n", restore=True)

    def test_names_cannot_escape_store(self):
        for names in [["../secret"], ["."], [".."], ["wg0", "wg0"], []]:
            with self.assertRaises(helper.Refused):
                helper.validate_names(names)

    def test_no_symlink_or_hardlink_reads(self):
        with tempfile.TemporaryDirectory() as temporary:
            base = Path(temporary)
            secret = base / "dummy"
            secret.write_text(CONFIG)
            secret.chmod(0o600)
            (base / "link").symlink_to(secret)
            with helper.directory(str(base.resolve())) as fd:
                with self.assertRaises(OSError):
                    helper.read_at(fd, "link", os.getuid())
                os.link(secret, base / "hardlink")
                with self.assertRaises(helper.Refused):
                    helper.read_at(fd, "hardlink", os.getuid())

    def test_rejects_symlink_ancestor_and_nonregular_input(self):
        with tempfile.TemporaryDirectory() as temporary:
            base = Path(temporary).resolve()
            actual = base / "actual"
            actual.mkdir(mode=0o700)
            (base / "alias").symlink_to(actual, target_is_directory=True)
            with self.assertRaises(OSError):
                with helper.directory(str(base / "alias")):
                    self.fail("symlink ancestor accepted")
            os.mkfifo(actual / "fifo", 0o600)
            with helper.directory(str(actual)) as fd:
                with self.assertRaises(helper.Refused):
                    helper.read_at(fd, "fifo", os.getuid())

    def test_rejects_insecure_mode(self):
        with tempfile.TemporaryDirectory() as temporary:
            file = Path(temporary) / "dummy"
            file.write_text(CONFIG)
            file.chmod(0o644)
            with helper.directory(str(Path(temporary).resolve())) as fd:
                with self.assertRaises(helper.Refused):
                    helper.read_at(fd, "dummy", os.getuid())

    def test_protocol_baseline_and_conflict_end_to_end(self):
        # Exercise actual JSON, pinned directories and commits without sudo or
        # touching /etc. Only host identity/ownership checks are adapted.
        with tempfile.TemporaryDirectory() as temporary, contextlib.ExitStack() as stack:
            base = Path(temporary).resolve()
            native, exchange, policy_dir = [base / n for n in ["native", "exchange", "policy"]]
            for directory in [native, exchange, policy_dir]:
                directory.mkdir(mode=0o700)
            policy = policy_dir / "policy.json"
            policy.write_text(json.dumps({"schema_version": 1, "uid": 1000, "device_id": "fixture", "tunnels": ["wg0"]}))
            policy.chmod(0o600)
            config = native / "wg0.conf"
            config.write_text(CONFIG)
            config.chmod(0o600)
            original_private, original_write = helper.private_info, helper.write_at
            stack.enter_context(patch.object(helper, "POLICY", str(policy)))
            stack.enter_context(patch.object(helper, "CONFIG_ROOT", str(native)))
            stack.enter_context(patch.object(helper.sys, "platform", "linux"))
            stack.enter_context(patch.object(helper.os, "geteuid", return_value=0))
            stack.enter_context(patch.object(helper, "trusted_install"))
            stack.enter_context(patch.dict(helper.os.environ, {"SUDO_UID": "1000", "SUDO_GID": "1000"}))
            stack.enter_context(patch.object(helper, "private_info", lambda info, uid: original_private(info, os.getuid())))
            stack.enter_context(patch.object(helper, "write_at", lambda fd, name, value, uid, gid: original_write(fd, name, value, os.getuid(), os.getgid())))
            sequence = [0]
            def call(action, bundle, baseline=None):
                sequence[0] += 1
                request = exchange / (str(sequence[0]) + "-request.json")
                response = exchange / (str(sequence[0]) + "-response.json")
                request.write_text(json.dumps({"schema_version": 1, "device_id": "fixture", "tunnels": ["wg0"], "bundle_path": str(bundle), "baseline": baseline}))
                request.chmod(0o600)
                helper.run(action, str(request), str(response))
                return json.loads(response.read_text())
            capture = exchange / "capture.json"
            captured = call("capture", capture)
            self.assertEqual(captured["baseline"], {"wg0": helper.digest(CONFIG.encode())})
            incoming = exchange / "incoming.json"
            incoming.write_text(json.dumps({"schema_version": 1, "device_id": "fixture", "tunnels": [{"name": "wg0", "config": CONFIG + "# incoming\n"}]}))
            incoming.chmod(0o600)
            validated = call("validate", incoming)
            self.assertEqual(captured["baseline"], validated["baseline"])
            config.write_text(CONFIG + "# concurrent edit\n")
            with self.assertRaises(helper.Refused):
                call("restore", incoming, validated["baseline"])
            self.assertIn("concurrent edit", config.read_text())
            config.write_text(CONFIG)
            restored = call("restore", incoming, validated["baseline"])
            self.assertTrue(Path(restored["recovery"]).is_dir())
            self.assertEqual(config.read_text(), CONFIG + "# incoming\n")
            self.assertEqual((Path(restored["recovery"]) / "wg0.conf").read_text(), CONFIG)

    def test_atomic_commit_and_rollback(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary).resolve()
            for name in ["wg0", "wg1"]:
                (root / (name + ".conf")).write_bytes(CONFIG.encode())
                (root / (name + ".conf")).chmod(0o600)
            current = {"wg0": CONFIG.encode(), "wg1": CONFIG.encode()}
            incoming = {n: v + b"# changed\n" for n, v in current.items()}
            original_write = helper.write_at
            original_read = helper.read_at
            def local_write(fd, name, value, uid, gid):
                return original_write(fd, name, value, os.getuid(), os.getgid())
            def local_read(fd, name, uid, optional=False):
                return original_read(fd, name, os.getuid(), optional)
            real_replace = os.replace
            count = [0]
            def failing_replace(*args, **kwargs):
                count[0] += 1
                if count[0] == 2:
                    raise OSError("synthetic second-write failure")
                return real_replace(*args, **kwargs)
            with helper.directory(str(root)) as fd, patch.object(helper, "write_at", local_write), patch.object(helper, "read_at", local_read):
                with patch.object(helper.os, "replace", failing_replace):
                    with self.assertRaises(OSError):
                        helper.commit(fd, current, incoming)
                self.assertEqual((root / "wg0.conf").read_bytes(), current["wg0"])
                self.assertEqual((root / "wg1.conf").read_bytes(), current["wg1"])
                helper.commit(fd, current, incoming)
                self.assertEqual((root / "wg0.conf").read_bytes(), incoming["wg0"])
                self.assertEqual((root / "wg1.conf").stat().st_mode & 0o777, 0o600)


if __name__ == "__main__":
    unittest.main()
