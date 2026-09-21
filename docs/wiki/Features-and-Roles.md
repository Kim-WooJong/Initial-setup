# Features and Roles

| Component | Role | Typical command |
|---|---|---|
| `setup.nu` | Canonical setup entry and prerequisite routing | `nu setup.nu` |
| chezmoi layer | Applies and captures managed dotfiles | `dotpull`, `dotpush` |
| sync provider | Tracks private configuration state and remote heads | `dotstatus`, `dotsync` |
| Cloud-wins | Guarded one-way import from a cloud mirror | `dotcloud` |
| snapshots | Creates recoverable configuration checkpoints | `dotsnapshot`, `dotrollback` |
| diagnostics | Finds missing tools, invalid state, or environment problems | `dotdoctor` |
| preflight | Shows pending managed changes before applying them | `dotpreflight --diff` |
| toolchains | Installs/captures Rust and Julia environment state | `dottoolchain`, `dotcapture` |
| secrets | Keeps machine-local secret material separate from public configuration | `dotsecrets`, `dotvault` |
| Git/SSH | Manages folder-specific identities and local SSH settings | `dotgitids`, `dotsshkeys` |
| update layer | Updates project/runtime components under safety checks | `dotupdate`, `dotupgrade`, `dotnuupdate` |


## Explicit rclone-only transport

`dotrpush` and `dotrpull` are for an additional rclone revision store that must remain independent from the machine's normal sync provider. They reuse the verified revision/HEAD implementation but keep provider baseline state separate and avoid mutating the normal provider source.
