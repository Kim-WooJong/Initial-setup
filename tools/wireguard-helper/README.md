# Windows WireGuard sync helper

`WireGuardSync.cs` is a fixed Windows service/client executable compiled by the
elevated `scripts/windows/install-wireguard-sync-helper.ps1` installer using the
inbox .NET Framework compiler. No downloaded compiler or NuGet package is used.

The service runs as LocalSystem and is the only component which decrypts and
encrypts WireGuard's `*.conf.dpapi` store. Its installed policy pins the caller
SID, device ID and tunnel names. Decryption rejects a DPAPI description that
does not exactly match the requested tunnel name (including renamed ciphertext). The client authenticates the pipe's SYSTEM
owner; the server impersonates and verifies the caller SID and rejects remote
clients. Neither endpoint executes scripts, starts tunnels or accepts store paths.

Client protocol:

```
wireguard-sync-helper.exe capture|validate|restore --request C:\absolute\request.json --response C:\absolute\response.json
```

Request: `{ "schema_version": 1, "device_id": "machine", "tunnels": ["home"], "bundle_path": "C:\\absolute\\bundle.json" }`.
Bundle: `{ "schema_version": 1, "device_id": "machine", "tunnels": [{ "name": "home", "config": "[Interface]\n..." }] }`.
The exact requested tunnel set must match policy. Capture creates the bundle
containing only existing tunnels (including an empty array on a fresh target).
Capture and validate return `baseline`, a record mapping each allowlisted name to
the SHA-256 of its DPAPI ciphertext, or `"missing"`. Capture binds these hashes to
the bytes it decrypted and rechecks them before responding. Restore requires this
record in its request, rejects stale/missing/extra entries, and checks it again
immediately before commit. The orchestrator must compare capture and validation
baselines to catch changes during preflight. This is optimistic concurrency, not
a lock against the WireGuard manager or an administrator writing concurrently.
Validate checks a complete restore bundle and installation readiness without
modifying the store; restore replaces existing or creates missing configured tunnels.
Validate and restore reject affected tunnel services unless stopped.
No tunnel service is activated or restarted: changes apply on its next start.

Plaintext staging files receive a protected DACL granting only the calling user
and SYSTEM. The request/response/bundle parent directories must already exist,
have no reparse-point ancestors or alternate-stream paths, and have a protected
DACL granting content read/write access
only to the user, SYSTEM and Administrators. The caller must remove staging files
after encryption/use. No plaintext is emitted to stdout, stderr, event logs or
arguments. Error messages deliberately omit exception details/configuration.

Restore first creates a SYSTEM-only recovery directory under the store, saves
the original DPAPI ciphertext, prepares replacements encrypted as SYSTEM with
the tunnel name as DPAPI description, then atomically replaces each file.
Caught failures roll back already replaced files. Recovery ciphertext is retained
after success or failure; power loss between multiple file replacements may
require manual recovery from that directory. A restore is not a transactional
multi-tunnel switch and must be run with affected tunnels stopped by the user.

The helper deliberately does not remove tunnels, register tunnel services, export to
stdout, grant access to the WireGuard store, accept arbitrary privileged paths,
or restart services. Install from trusted reviewed source in an elevated console.
Install once in elevated Windows PowerShell, with the SID of the ordinary user
who will run dotpush/dotpull (obtain it in that user's console with
`[Security.Principal.WindowsIdentity]::GetCurrent().User.Value`):

```powershell
.\scripts\windows\install-wireguard-sync-helper.ps1 -DeviceId 'workstation' -TunnelNames @('home','office') -CallerSid 'S-1-5-21-...'
```

The installer refuses existing services/directories rather than implicitly
replacing privileged code. Device/tunnel values must match the machine sync
policy (`backend: windows-dpapi`). Installer policy adds `caller_sid` and is
stored separately under Program Files; normal users cannot edit it. The helper
performs envelope, name and basic INI checks, not WireGuard's complete semantic
configuration parser. Malformed peer fields may be rejected later by WireGuard.

Windows runtime integration must be verified on Windows; non-Windows source
checks are not a substitute for pipe/SCM/DPAPI validation.

## Verification on a disposable Windows VM

1. Run `powershell -NoProfile -File tools\wireguard-helper\Test-WireGuardSync.ps1`
   to compile and test envelope/name allowlisting without administrator access.
2. Install for a disposable user and stopped test tunnels. Capture, encrypt and
   remove plaintext staging, decrypt to private staging, validate and restore;
   verify WireGuard can read the restored tunnel on its next user-initiated start.
3. Repeat with a missing configured target; capture must omit it and restore must
   create only that policy-authorized tunnel. Check the recovery manifest and
   original ciphertext retained under a SYSTEM-only ACL.
4. Confirm wrong SID, remote pipe clients, extra/missing bundle tunnels, wrong
   device, traversal names, reparse staging paths, permissive staging ACLs and a
   running affected tunnel all fail without configuration changes.
5. With the service stopped, squat its pipe as an ordinary user and confirm the
   client rejects its non-SYSTEM owner before sending any restore bytes.
6. Change a stopped tunnel after validation (also test missing-to-present); restore
   must reject the stale baseline without replacing any configurations.
7. Inject replacement failure on a later tunnel; confirm earlier replacements
   roll back and the sanitized response retains a recovery path. Exercise manual
   recovery separately for simulated machine interruption during multi-file commit.
