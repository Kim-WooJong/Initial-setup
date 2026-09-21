# Command Reference

Commands are installed into the Nushell environment after setup.

| Command | Role |
|---|---|
| `dotstatus` | Show synchronization and provider state. |
| `dotdiff` | Show managed configuration differences. |
| `dotpush` | Publish reviewed local source changes. |
| `dotpull` | Fetch/apply private source changes. Blocks post-baseline local edits by default; `--discard-local` explicitly permits replacement after showing the incoming diff. |
| `dotrpush` | Publish the current private source snapshot to a dedicated rclone remote without changing the normal provider. |
| `dotrpull` | Pull/apply from a dedicated rclone remote without replacing the normal provider source; the same post-baseline local-change guard applies. |
| `dotresolve` | Resolve merge/protected-file conflicts. |
| `dotsync` | Run the normal synchronization workflow. |
| `dotsnapshot` | Create a recoverable snapshot. |
| `dotrollback` | Restore a supported snapshot. |
| `dotversion` | Project maintenance or configuration command; run with `--help` for options. |
| `dotrepo` | Project maintenance or configuration command; run with `--help` for options. |
| `dotrelease` | Project maintenance or configuration command; run with `--help` for options. |
| `dotcleanup` | Project maintenance or configuration command; run with `--help` for options. |
| `dotaudit` | Project maintenance or configuration command; run with `--help` for options. |
| `dotstate` | Project maintenance or configuration command; run with `--help` for options. |
| `dotmigrate` | Project maintenance or configuration command; run with `--help` for options. |
| `dotchecklist` | Project maintenance or configuration command; run with `--help` for options. |
| `dotcapture` | Project maintenance or configuration command; run with `--help` for options. |
| `dotrestoreenv` | Project maintenance or configuration command; run with `--help` for options. |
| `dotdoctor` | Diagnose environment/setup problems. |
| `dotupdate` | Update managed project components. |
| `dotreport` | Project maintenance or configuration command; run with `--help` for options. |
| `dotlog` | Project maintenance or configuration command; run with `--help` for options. |
| `dotconfig` | Project maintenance or configuration command; run with `--help` for options. |
| `dotonedrive` | Project maintenance or configuration command; run with `--help` for options. |
| `dotrclone` | Project maintenance or configuration command; run with `--help` for options. |
| `dotlocal` | Project maintenance or configuration command; run with `--help` for options. |
| `dotsecrets` | Project maintenance or configuration command; run with `--help` for options. |
| `dotgitids` | Project maintenance or configuration command; run with `--help` for options. |
| `dotsshkeys` | Project maintenance or configuration command; run with `--help` for options. |
| `dotgitlocal` | Project maintenance or configuration command; run with `--help` for options. |
| `dotsshlocal` | Project maintenance or configuration command; run with `--help` for options. |
| `dotnvim` | Project maintenance or configuration command; run with `--help` for options. |
| `dotnu` | Project maintenance or configuration command; run with `--help` for options. |
| `dotenv` | Project maintenance or configuration command; run with `--help` for options. |
| `dotwezterm` | Project maintenance or configuration command; run with `--help` for options. |
| `dotstarship` | Project maintenance or configuration command; run with `--help` for options. |
| `dotrun` | Inspect, resume, or roll back setup runs. |
| `dotvalidate` | Validate project/configuration structure. |
| `dottest` | Run project self-tests. |
| `dotpreflight` | Inspect changes before applying them. |
| `dotlocalbackup` | Project maintenance or configuration command; run with `--help` for options. |
| `dotlocalrestore` | Project maintenance or configuration command; run with `--help` for options. |
| `newproj` | Create a new project scaffold. |
| `dotdata` | Project maintenance or configuration command; run with `--help` for options. |
| `dottools` | Project maintenance or configuration command; run with `--help` for options. |
| `dotplan` | Project maintenance or configuration command; run with `--help` for options. |
| `dotapply` | Project maintenance or configuration command; run with `--help` for options. |
| `dotverify` | Project maintenance or configuration command; run with `--help` for options. |
| `dottoolchain` | Project maintenance or configuration command; run with `--help` for options. |
| `dotmergecfg` | Project maintenance or configuration command; run with `--help` for options. |
| `dotvault` | Project maintenance or configuration command; run with `--help` for options. |
| `dotbackend` | Project maintenance or configuration command; run with `--help` for options. |
| `dotupgrade` | Perform guarded project/runtime upgrade operations. |
| `dotsecuritytest` | Project maintenance or configuration command; run with `--help` for options. |
| `dotnuupdate` | Update/select the managed Nushell runtime. |
| `dotcloud` | Manage Cloud-wins import/recovery. |


## Explicit rclone-only transport

Use these commands when you want an additional rclone transport without switching the normal synchronization provider.

```nu
# One-time explicit target; save it after reviewing the path.
dotrpush --remote "proton:Initial-setup-store" --save-remote

# Later calls can reuse ~/.config/dotfiles/rclone-sync.nuon.
dotrpush
dotrpull

# Pull with the same apply controls as the normal pull path.
dotrpull --backup
dotrpull --force
dotrpull --prune
```

`dotrpush` deliberately publishes the current private source snapshot as-is. It does not recapture live files into the normal provider source, because doing so could trigger an unrelated cloud client such as Proton Drive. `dotrpull` fetches into verified temporary staging and applies from that staging; it does not replace the normal provider source. The dedicated rclone transport uses its own provider baseline and does not advance the normal global sync baseline.
