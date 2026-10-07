# Encrypted native WireGuard synchronization

This opt-in integration captures persistent WireGuard profiles, not merely
active `wg showconf` output. No manual ZIP export is needed after enrollment.

## Scope

| Platform | Persistent store | Privileged component |
|---|---|---|
| Windows | WireGuard `Data/Configurations/*.conf.dpapi` | Protected LocalSystem service and restricted local client |
| Linux | `/etc/wireguard/*.conf` (`wg-quick`) | Root-owned narrow helper invoked with sudo |

Only explicitly enrolled tunnel names are handled. NetworkManager and
systemd-networkd are not supported by this backend. macOS is not a native backend.
Restore does not start, stop, or restart tunnels. Stop affected tunnels yourself
before replacing their stored configuration and keep them inactive throughout restore. External root/administrator editors and service managers do not participate in the helper lock. This also prevents Linux
`SaveConfig=true` from overwriting a just-restored profile on shutdown.

## Policy and encryption

After installing the platform helper, create machine-local
`~/.config/dotfiles/wireguard.nuon` from
[`templates/wireguard.nuon.example`](templates/wireguard.nuon.example).
The protected helper policy must authorize the same device identifier and names.
There are no user-configurable privileged destination paths.

Configure the existing age vault first (`dotctl config vault init` if it has
not been initialized). Keep the recovery identity outside the synchronized tree.
A new unrelated age identity cannot decrypt existing backups: recover an
authorized identity or encrypt to the destination's public recipient beforehand.

`dotpush` captures enrolled settings and publishes only
`secrets/wireguard-<device_id>.age` beneath the existing private data root
(normally `Initial-setup/private`). Temporary plaintext is machine-local,
access-restricted, and removed after use. Neither private keys nor decrypted
profiles are printed in status output.

`dotpull` authenticates the incoming bundle before applying live settings.
Existing local changes are guarded; privileged helpers preserve recovery data
when replacing profiles. The common local fingerprint includes WireGuard
content so unsynchronized edits are visible to normal conflict handling.
An enrolled but unavailable helper is an error, not a silent skip.

## One-time enrollment

Run these commands from the updated `Initial-setup` checkout. Substitute your
own device identifier and existing tunnel names (without `.conf`). Portable
names are limited to 15 characters. Installation is explicit; normal push/pull
does not request elevation or install a service.

### Windows

In the **ordinary user's PowerShell**, obtain the account SID (not a secret):

```powershell
[Security.Principal.WindowsIdentity]::GetCurrent().User.Value
```

Then in an **Administrator PowerShell**, using that ordinary user's SID:

```powershell
.\scripts\windows\install-wireguard-sync-helper.ps1 -DeviceId 'my-laptop' -TunnelNames 'wg0' -CallerSid 'S-1-5-21-REPLACE-WITH-YOUR-SID'
```

This compiles the helper with the Windows .NET Framework compiler, installs a
restricted LocalSystem service, and starts only the sync helper—not the VPN.
Do not rerun against an existing installation: implicit replacement is refused.
The Windows-native test harness is
`tools/wireguard-helper/Test-WireGuardSync.ps1`; see its adjacent README before
running the privileged integration checklist.

### Linux (`wg-quick`)

Run as the **ordinary sync user**, not as root:

```sh
python3 scripts/linux/install-wireguard-helper.py --device my-laptop --tunnel wg0
```

The installer requests sudo once and enrolls a fixed root-owned helper and a
restricted sudoers rule. Repeat `--tunnel` for each allowed profile. Python 3,
sudo, and WireGuard tools must be installed. Restore refuses active interfaces,
executable lifecycle hooks, and `SaveConfig=true`; remove incompatible options
only after reviewing their purpose. Capture alone does not activate a tunnel.

### Local policy and command refresh (both platforms)

In Nushell, create the machine-local policy from the template; do not overwrite
an existing policy without reviewing it:

```nu
mkdir (~/.config/dotfiles | path expand)
cp templates/wireguard.nuon.example ~/.config/dotfiles/wireguard.nuon
nu --no-config-file scripts/refresh-commands.nu
```

Edit `~/.config/dotfiles/wireguard.nuon`: use `backend: "windows-dpapi"` on
Windows or `backend: "linux-wg-quick"` on Linux, and match the device/tunnel
allowlist enrolled above. Restart Nushell to reload commands. Initialize/recover
the age vault as described above, then run the commands below.

A fresh replacement machine may pull before its enrolled tunnel exists. A
push, however, refuses an incomplete allowlist rather than publishing a partial
backup. A first pull over different existing profiles requires reviewing the
local differences and explicitly using `dotpull --discard-local`.

## Commands

After refreshing installed command modules from the updated checkout:

```nu
dotctl config wireguard          # local policy location
dotctl config wireguard --check  # verify capture access without showing keys
dotpush                         # automatic encrypted capture + publish
dotpull                         # authenticated restore; no activation
```

Manual `--capture` and `--restore` are also available for diagnostics; ordinary
use should go through push/pull for transport and conflict handling.

## Device and OS boundaries

Use different device identifiers and VPN peer identities for computers that
connect concurrently. Reusing the same peer private key on two live clients
causes endpoint conflicts. Reusing a device identifier is appropriate for an
intentional replacement/recovery of that device, not cloning every machine.

Basic WireGuard fields are shared across OSes; DNS handling, interface naming,
route options, and `PreUp`/`PostUp`/`PreDown`/`PostDown` commands are not universally
portable. This is encrypted backup/restore, not an OS-specific script translator.
Review a cross-OS recovery before activating the tunnel.

## Verification boundary

Repository tests use synthetic profiles, isolated directories, and mocked
privilege/transport boundaries where the host cannot provide the target OS.
Those tests do not establish actual Windows DPAPI/service behavior or Linux
sudo/system ownership behavior. Platform runtime verification is required before
describing the privileged integration as production-validated.
