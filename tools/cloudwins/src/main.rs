//! Reviewed, one-way regular-file import. Never execute a plan from an untrusted party.
//! Locks coordinate this tool, not editors/cloud clients; all external-writer checks
//! are optimistic. Filesystem snapshots/hostile concurrent path replacement are out
//! of scope. Source is only ever opened for reading.
use anyhow::{bail, ensure, Context, Result};
use clap::{Args, Parser, Subcommand};
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use std::collections::{BTreeMap, BTreeSet};
use std::fs::{self, File, OpenOptions};
use std::io::{BufReader, Read, Write};
use std::path::{Component, Path, PathBuf};
use std::sync::atomic::{AtomicU64, Ordering};
use std::thread;
use std::time::{Duration, SystemTime, UNIX_EPOCH};
use walkdir::WalkDir;

const FORMAT: u32 = 2; // Intentionally reject the unintegrated format-1 bundle.
const VERSION: &str = env!("CARGO_PKG_VERSION");
const EXCLUDES: &[&str] = &[".git", ".initial-setup-state"];
static SERIAL: AtomicU64 = AtomicU64::new(0);

// Format compatibility is distinct from the version allowed to create a new
// transaction. Old journals must remain readable after a patch-level upgrade.
fn stable_version(value: &str) -> Option<(u64, u64, u64)> {
    let values: Option<Vec<u64>> = value.split('.').map(|part| {
        if part.is_empty() || (part.len() > 1 && part.starts_with('0'))
            || !part.bytes().all(|byte| byte.is_ascii_digit()) {
            None
        } else {
            part.parse().ok()
        }
    }).collect();
    let values = values?;
    if values.len() != 3 { return None; }
    Some((values[0], values[1], values[2]))
}
fn supported_writer(version: &str) -> bool {
    match (stable_version(version), stable_version(VERSION)) {
        (Some(writer), Some(reader)) => writer >= (0, 13, 2) && writer <= reader,
        _ => false,
    }
}


#[derive(Parser)]
#[command(name = "cloudwins", version, about = "Review-first, non-deleting cloud-mirror import")]
struct Cli {
    #[command(subcommand)]
    command: Command,
}
#[derive(Subcommand)]
enum Command {
    Probe(Roots),
    Plan(Roots),
    Apply(ApplyArgs),
    Status(StateArgs),
    Verify(Roots),
    Ready(StateArgs),
    Rollback(RollbackArgs),
}
#[derive(Args, Clone)]
struct Roots {
    #[arg(long)]
    source: PathBuf,
    #[arg(long)]
    target: PathBuf,
    /// Must be outside both source and target. The Nushell wrapper chooses it.
    #[arg(long)]
    state_dir: PathBuf,
    #[arg(long, default_value_t = 1500)]
    settle_ms: u64,
}
#[derive(Args)]
struct ApplyArgs {
    #[arg(long)]
    plan: PathBuf,
    #[arg(long)]
    execute: bool,
    #[arg(long)]
    confirm: Option<String>,
}
#[derive(Args)]
struct StateArgs {
    #[arg(long)]
    target: PathBuf,
    #[arg(long)]
    state_dir: PathBuf,
}
#[derive(Args)]
struct RollbackArgs {
    #[command(flatten)]
    state: StateArgs,
    #[arg(long)]
    run: String,
    #[arg(long)]
    execute: bool,
    #[arg(long)]
    confirm: Option<String>,
}
#[derive(Clone, Debug, Serialize, Deserialize, PartialEq, Eq)]
#[serde(deny_unknown_fields)]
struct Fingerprint {
    bytes: u64,
    sha256: String,
}
type Tree = BTreeMap<String, Fingerprint>;
#[derive(Clone, Debug, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
enum Action {
    Create,
    Replace,
    Same,
}
#[derive(Clone, Debug, Serialize, Deserialize, PartialEq, Eq)]
#[serde(deny_unknown_fields)]
struct Entry {
    path: String,
    action: Action,
    before: Option<Fingerprint>,
    after: Fingerprint,
    local_changed_since_baseline: bool,
}
#[derive(Clone, Debug, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
struct Plan {
    format_version: u32,
    tool_version: String,
    plan_id: String,
    nonce: String,
    source: PathBuf,
    target: PathBuf,
    state_dir: PathBuf,
    source_digest: String,
    target_digest: String,
    excludes: Vec<String>,
    entries: Vec<Entry>,
    target_only_files: Tree,
}
#[derive(Clone, Debug, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
struct Baseline {
    format_version: u32,
    source: PathBuf,
    target: PathBuf,
    run_id: String,
    files: Tree,
    workspace_files: Tree,
}
#[derive(Clone, Debug, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
enum Phase {
    Prepared,
    Applying,
    Applied,
    RollingBack,
    RolledBack,
}
#[derive(Clone, Debug, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
struct Journal {
    format_version: u32,
    run_id: String,
    order: u128,
    phase: Phase,
    plan: Plan,
    completed_paths: Vec<String>,
    previous_baseline: Option<Baseline>,
}

fn stamp() -> u128 {
    SystemTime::now().duration_since(UNIX_EPOCH).unwrap_or_default().as_nanos()
}
fn nonce() -> String {
    format!("{}-{}-{}", stamp(), std::process::id(), SERIAL.fetch_add(1, Ordering::Relaxed))
}
fn digest<T: Serialize>(value: &T) -> Result<String> {
    Ok(format!("{:x}", Sha256::digest(serde_json::to_vec(value)?)))
}
fn emit(value: serde_json::Value) -> Result<()> {
    println!("{}", serde_json::to_string_pretty(&value)?);
    Ok(())
}
fn portable(rel: &str) -> Result<()> {
    ensure!(!rel.is_empty(), "Empty relative path");
    for part in rel.split('/') {
        ensure!(!part.is_empty() && part != "." && part != "..", "Unsafe path: {rel}");
        ensure!(!part.ends_with('.') && !part.ends_with(' '), "Non-portable path: {rel}");
        ensure!(!part.chars().any(|c| c.is_control() || "\\:<>\"|?*".contains(c)), "Non-portable path: {rel}");
        let stem = part.split('.').next().unwrap_or("").to_ascii_uppercase();
        let reserved = matches!(stem.as_str(), "CON" | "PRN" | "AUX" | "NUL")
            || ((stem.starts_with("COM") || stem.starts_with("LPT"))
                && stem.len() == 4
                && (b'1'..=b'9').contains(&stem.as_bytes()[3]));
        ensure!(!reserved, "Reserved Windows name: {rel}");
    }
    Ok(())
}
fn relative(path: &Path) -> Result<String> {
    let mut parts = Vec::new();
    for c in path.components() {
        match c {
            Component::Normal(p) => parts.push(p.to_str().context("Non-UTF-8 file name")?),
            _ => bail!("Unsafe relative path: {}", path.display()),
        }
    }
    let rel = parts.join("/");
    portable(&rel)?;
    Ok(rel)
}
fn path_for(root: &Path, rel: &str) -> Result<PathBuf> {
    portable(rel)?;
    let mut out = root.to_path_buf();
    for p in rel.split('/') { out.push(p); }
    check_ancestors(&out)?;
    Ok(out)
}
fn is_excluded(rel: &str) -> bool {
    EXCLUDES.iter().any(|x| rel.eq_ignore_ascii_case(x)
        || rel.to_ascii_lowercase().starts_with(&format!("{x}/")))
}
fn check_ancestors(path: &Path) -> Result<()> {
    // read_link also recognizes Windows directory junctions. Non-redirection cloud
    // placeholders are allowed on the source; opening them can cause hydration.
    let mut cursor = PathBuf::new();
    for part in path.components() {
        ensure!(!matches!(part, Component::ParentDir), "Parent traversal is forbidden");
        cursor.push(part.as_os_str());
        if matches!(part, Component::Prefix(_)) { continue; }
        match fs::symlink_metadata(&cursor) {
            Ok(meta) => {
                ensure!(!meta.file_type().is_symlink() && fs::read_link(&cursor).is_err(),
                    "Symlink/junction rejected: {}", cursor.display());
            }
            Err(e) if e.kind() == std::io::ErrorKind::NotFound => {}
            Err(e) => return Err(e).with_context(|| format!("Cannot inspect {}", cursor.display())),
        }
    }
    Ok(())
}
fn absolute(path: &Path) -> Result<PathBuf> {
    let full = if path.is_absolute() { path.to_path_buf() } else { std::env::current_dir()?.join(path) };
    check_ancestors(&full)?;
    Ok(full)
}
fn canonical_existing(path: &Path) -> Result<PathBuf> {
    let canonical = fs::canonicalize(path)?;
    // Match Nu's ordinary drive/UNC paths; std canonicalize adds a verbatim
    // prefix on Windows, which otherwise breaks wrapper/plan identity checks.
    #[cfg(windows)] {
        let text = canonical.to_str().context("Non-UTF-8 canonical path")?;
        if let Some(unc) = text.strip_prefix(r"\\?\UNC\") {
            return Ok(PathBuf::from(format!(r"\\{}", unc)));
        }
        if let Some(drive) = text.strip_prefix(r"\\?\") {
            if drive.as_bytes().get(1) == Some(&b':') { return Ok(PathBuf::from(drive)); }
        }
    }
    Ok(canonical)
}
fn directory(path: &Path) -> Result<PathBuf> {
    let full = absolute(path)?;
    ensure!(full.is_dir(), "Directory must already exist: {}", full.display());
    let canon = canonical_existing(&full)?;
    check_ancestors(&canon)?;
    Ok(canon)
}
fn prospective(path: &Path) -> Result<PathBuf> {
    let full = absolute(path)?;
    if full.exists() { return directory(&full); }
    let parent = full.parent().context("Path has no parent")?;
    let leaf = full.file_name().context("Path has no final component")?;
    Ok(prospective(parent)?.join(leaf))
}
fn overlap(a: &Path, b: &Path) -> bool {
    let norm = |p: &Path| {
        let s = p.to_string_lossy().replace('\\', "/").trim_end_matches('/').to_string();
        if cfg!(windows) { s.to_lowercase() } else { s }
    };
    let a = norm(a);
    let b = norm(b);
    a == b || a.starts_with(&(b.clone() + "/")) || b.starts_with(&(a + "/"))
}
fn roots(args: &Roots) -> Result<(PathBuf, PathBuf, PathBuf)> {
    let source = directory(&args.source)?;
    let target = directory(&args.target)?;
    let state = prospective(&args.state_dir)?;
    ensure!(!overlap(&source, &target), "Source and target must be disjoint");
    ensure!(!overlap(&state, &source) && !overlap(&state, &target), "State/backups must be outside source AND target");
    ensure!(args.settle_ms <= 60_000, "settle-ms must be at most 60000");
    Ok((source, target, state))
}
fn same_observation(a: &fs::Metadata, b: &fs::Metadata) -> bool {
    if !a.is_file() || !b.is_file() || a.len() != b.len() || a.modified().ok() != b.modified().ok() {
        return false;
    }
    #[cfg(unix)] {
        use std::os::unix::fs::MetadataExt;
        if a.dev() != b.dev() || a.ino() != b.ino() { return false; }
    }
    true
}
fn fingerprint(path: &Path) -> Result<Fingerprint> {
    check_ancestors(path)?;
    let meta = fs::symlink_metadata(path)?;
    ensure!(meta.is_file(), "Not a regular file: {}", path.display());
    let mut file = BufReader::with_capacity(1024 * 1024, File::open(path)?);
    let opened = file.get_ref().metadata()?;
    ensure!(same_observation(&meta, &opened), "File changed while opening: {}", path.display());
    let mut hasher = Sha256::new();
    let mut buffer = vec![0u8; 1024 * 1024];
    let mut count = 0u64;
    loop {
        let n = file.read(&mut buffer)?;
        if n == 0 { break; }
        count += n as u64;
        hasher.update(&buffer[..n]);
    }
    let after_open_file = file.get_ref().metadata()?;
    let after_path = fs::symlink_metadata(path)?;
    ensure!(count == opened.len() && same_observation(&opened, &after_open_file)
        && same_observation(&opened, &after_path),
        "File changed while reading (size, metadata or identity): {}", path.display());
    Ok(Fingerprint { bytes: count, sha256: format!("{:x}", hasher.finalize()) })
}
fn maybe_fingerprint(path: &Path) -> Result<Option<Fingerprint>> {
    check_ancestors(path)?;
    match fs::symlink_metadata(path) {
        Ok(_) => Ok(Some(fingerprint(path)?)),
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => Ok(None),
        Err(e) => Err(e.into()),
    }
}
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum NodeKind { Directory, File }
fn layout(root: &Path) -> Result<BTreeMap<String, NodeKind>> {
    directory(root)?;
    let mut result = BTreeMap::new();
    let mut seen = BTreeSet::new();
    let walker = WalkDir::new(root).follow_links(false).sort_by_file_name().into_iter()
        .filter_entry(|entry| entry.depth() == 0 || entry.path().strip_prefix(root)
            .ok().and_then(|path| relative(path).ok()).map(|name| !is_excluded(&name)).unwrap_or(true));
    for entry in walker {
        let entry = entry?;
        if entry.depth() == 0 { continue; }
        let name = relative(entry.path().strip_prefix(root)?)?;
        if is_excluded(&name) { continue; }
        check_ancestors(entry.path())?;
        ensure!(!entry.file_type().is_symlink(), "Symlink rejected: {name}");
        ensure!(seen.insert(name.to_lowercase()), "Case-colliding path: {name}");
        let kind = if entry.file_type().is_dir() { NodeKind::Directory } else {
            ensure!(entry.file_type().is_file(), "Special file rejected: {name}");
            NodeKind::File
        };
        result.insert(name, kind);
    }
    Ok(result)
}
fn compatible_layouts(source: &Path, target: &Path) -> Result<()> {
    // Include EMPTY directories. File manifests alone lose this information.
    let mut names = BTreeMap::<String, (String, NodeKind)>::new();
    for (name, kind) in layout(source)?.into_iter().chain(layout(target)?) {
        if let Some((old, old_kind)) = names.insert(name.to_lowercase(), (name.clone(), kind)) {
            ensure!(old == name, "Source/target case collision: {old} / {name}");
            ensure!(old_kind == kind, "Source/target file-directory conflict: {name}");
        }
    }
    Ok(())
}
fn tree(root: &Path) -> Result<Tree> {
    let mut result = Tree::new();
    for (name, kind) in layout(root)? {
        if kind == NodeKind::File {
            let value = fingerprint(&path_for(root, &name)?)?;
            result.insert(name, value);
        }
    }
    Ok(result)
}
fn stable(root: &Path, settle_ms: u64) -> Result<Tree> {
    let a = tree(root)?;
    thread::sleep(Duration::from_millis(settle_ms));
    let b = tree(root)?;
    ensure!(a == b, "Source changed during stability check; finish cloud-client sync and re-plan");
    ensure!(!b.is_empty(), "Empty source rejected; check the selected mirror path");
    Ok(b)
}
fn private_dir(path: &Path) -> Result<()> {
    check_ancestors(path)?;
    fs::create_dir_all(path)?;
    #[cfg(unix)] {
        use std::os::unix::fs::PermissionsExt;
        fs::set_permissions(path, fs::Permissions::from_mode(0o700))?;
    }
    Ok(())
}
fn sync_parent(path: &Path) -> Result<()> {
    #[cfg(unix)] File::open(path)?.sync_all()?;
    #[cfg(not(unix))] let _ = path;
    Ok(())
}
struct TempFile(PathBuf);
impl Drop for TempFile {
    fn drop(&mut self) { let _ = fs::remove_file(&self.0); }
}
fn temporary(parent: &Path) -> Result<(TempFile, File)> {
    check_ancestors(parent)?;
    let path = parent.join(format!(".cloudwins-{}.tmp", nonce()));
    let mut options = OpenOptions::new();
    options.write(true).create_new(true);
    #[cfg(unix)] {
        use std::os::unix::fs::OpenOptionsExt;
        options.mode(0o600);
    }
    let file = options.open(&path)?;
    Ok((TempFile(path), file))
}
fn atomic_json<T: Serialize>(path: &Path, value: &T, replace: bool) -> Result<()> {
    check_ancestors(path)?;
    let parent = path.parent().context("Missing JSON parent")?;
    private_dir(parent)?;
    let (tmp, mut file) = temporary(parent)?;
    serde_json::to_writer_pretty(&mut file, value)?;
    file.write_all(b"\n")?;
    file.sync_all()?;
    drop(file);
    if replace {
        // Never remove the old record before rename.
        fs::rename(&tmp.0, path)?;
    } else {
        fs::hard_link(&tmp.0, path).context("Exclusive record creation failed (hard-link capable filesystem required)")?;
    }
    sync_parent(parent)?;
    Ok(())
}
fn read_json<T: for<'de> Deserialize<'de>>(path: &Path) -> Result<T> {
    check_ancestors(path)?;
    let file = File::open(path)?;
    let meta = file.metadata()?;
    ensure!(meta.is_file(), "Not a JSON file: {}", path.display());
    const LIMIT: u64 = 64 * 1024 * 1024;
    ensure!(meta.len() <= LIMIT, "JSON record exceeds 64 MiB safety limit");
    let mut bytes = Vec::new();
    file.take(LIMIT + 1).read_to_end(&mut bytes)?;
    ensure!(bytes.len() as u64 <= LIMIT, "JSON record grew beyond 64 MiB safety limit");
    serde_json::from_slice(&bytes).with_context(|| format!("Invalid JSON: {}", path.display()))
}
fn copy_temp(source: &Path, parent: &Path, expected: &Fingerprint) -> Result<TempFile> {
    ensure!(fingerprint(source)? == *expected, "Copy source changed: {}", source.display());
    let (tmp, mut out) = temporary(parent)?;
    std::io::copy(&mut File::open(source)?, &mut out)?;
    out.sync_all()?;
    drop(out);
    ensure!(fingerprint(&tmp.0)? == *expected, "Copied bytes differ: {}", source.display());
    Ok(tmp)
}
fn copy_new(source: &Path, dest: &Path, expected: &Fingerprint) -> Result<()> {
    let parent = dest.parent().context("Missing destination parent")?;
    private_dir(parent)?;
    let tmp = copy_temp(source, parent, expected)?;
    fs::hard_link(&tmp.0, dest).context("Exclusive backup/stage creation failed")?;
    sync_parent(parent)?;
    Ok(())
}
fn install(source: &Path, target: &Path, before: &Option<Fingerprint>, after: &Fingerprint) -> Result<()> {
    check_ancestors(target)?;
    let parent = target.parent().context("Missing target parent")?;
    fs::create_dir_all(parent)?;
    check_ancestors(parent)?;
    let tmp = copy_temp(source, parent, after)?;
    ensure!(maybe_fingerprint(target)? == *before, "Target changed immediately before install: {}", target.display());
    // Preserve the destination's basic permissions on replacement. This is not
    // a complete ACL/xattr/ownership replication tool.
    if before.is_some() { fs::set_permissions(&tmp.0, fs::metadata(target)?.permissions())?; }
    if before.is_some() {
        fs::rename(&tmp.0, target).context("Atomic file replacement failed; original backup retained")?;
    } else {
        fs::hard_link(&tmp.0, target).context("No-clobber install failed (hard-link capable filesystem required)")?;
    }
    sync_parent(parent)?;
    ensure!(fingerprint(target)? == *after, "Post-install verification failed");
    Ok(())
}
fn check_target_storage(target: &Path, needs_create: bool) -> Result<()> {
    let (first, mut handle) = temporary(target)?;
    handle.write_all(b"cloudwins storage preflight")?;
    handle.sync_all()?;
    drop(handle);
    if needs_create {
        let alias = TempFile(target.join(format!(".cloudwins-{}.link-test", nonce())));
        fs::hard_link(&first.0, &alias.0)
            .context("Target filesystem cannot perform no-clobber hard-link installs. Use a compatible local workspace; no payload files were changed")?;
    }
    let (second, handle) = temporary(target)?;
    drop(handle);
    fs::rename(&first.0, &second.0)
        .context("Target filesystem cannot replace a closed file atomically; no payload files were changed")?;
    sync_parent(target)?;
    Ok(())
}
struct Lock(File);
impl Drop for Lock {
    fn drop(&mut self) { let _ = self.0.unlock(); }
}
fn lock(target: &Path) -> Result<Lock> {
    let folder = target.join(".initial-setup-state");
    private_dir(&folder)?;
    let path = folder.join("cloud-wins.lock");
    check_ancestors(&path)?;
    let file = OpenOptions::new().read(true).write(true).create(true).truncate(false).open(path)?;
    if let Err(e) = file.try_lock() { bail!("cloud-wins target lock unavailable: {e:?}"); }
    // Leave the lock file in place: unlinking an OS-locked file permits inode races.
    Ok(Lock(file))
}
fn load_baseline(state: &Path, source: &Path, target: &Path) -> Result<Option<Baseline>> {
    let path = state.join("baseline.json");
    if !path.exists() { return Ok(None); }
    let b: Baseline = read_json(&path)?;
    ensure!(b.format_version == FORMAT && b.source == source && b.target == target, "Baseline belongs to a different root/format");
    Ok(Some(b))
}
fn plan_hash(plan: &Plan) -> Result<String> {
    let mut p = plan.clone();
    p.plan_id.clear();
    digest(&p)
}
fn validate_fingerprint(value: &Fingerprint) -> Result<()> {
    ensure!(value.sha256.len() == 64 && value.sha256.bytes()
        .all(|byte| byte.is_ascii_digit() || (b'a'..=b'f').contains(&byte)),
        "Invalid SHA-256 fingerprint");
    Ok(())
}
fn manifest_namespace(source: &Tree, target: &Tree) -> Result<()> {
    let mut nodes = BTreeMap::<String, (String, NodeKind)>::new();
    for name in source.keys().chain(target.keys()) {
        portable(name)?;
        let parts: Vec<&str> = name.split('/').collect();
        let mut prefix = String::new();
        for (index, part) in parts.iter().enumerate() {
            if !prefix.is_empty() { prefix.push('/'); }
            prefix.push_str(part);
            let kind = if index + 1 == parts.len() { NodeKind::File } else { NodeKind::Directory };
            if let Some((old, old_kind)) = nodes.insert(prefix.to_lowercase(), (prefix.clone(), kind)) {
                ensure!(old == prefix && old_kind == kind, "Manifest namespace collision: {old} / {prefix}");
            }
        }
    }
    Ok(())
}
fn validate_plan(plan: &Plan) -> Result<()> {
    ensure!(plan.format_version == FORMAT && supported_writer(&plan.tool_version),
        "Unsupported plan/journal format or writer version; do not edit historical records");
    ensure!(plan.plan_id == plan_hash(plan)?, "Plan content/ID mismatch; regenerate instead of editing JSON");
    ensure!(plan.excludes == EXCLUDES.iter().map(|s| s.to_string()).collect::<Vec<_>>(), "Invalid exclusion rules");
    // Recovery must work even when the cloud mirror is offline/missing.
    let s = prospective(&plan.source)?;
    let t = directory(&plan.target)?;
    let d = prospective(&plan.state_dir)?;
    ensure!(!overlap(&s, &t) && !overlap(&d, &s) && !overlap(&d, &t), "Unsafe plan roots");
    ensure!(s == plan.source && t == plan.target && d == plan.state_dir, "Plan paths changed/redirected");
    let mut seen = BTreeSet::new();
    let mut source = Tree::new();
    let mut target = plan.target_only_files.clone();
    for entry in &plan.entries {
        portable(&entry.path)?;
        validate_fingerprint(&entry.after)?;
        if let Some(before) = &entry.before { validate_fingerprint(before)?; }
        ensure!(!is_excluded(&entry.path) && seen.insert(entry.path.to_lowercase()), "Unsafe/duplicate plan path");
        let expected_action = match &entry.before {
            None => Action::Create,
            Some(b) if b == &entry.after => Action::Same,
            _ => Action::Replace,
        };
        ensure!(entry.action == expected_action, "Inconsistent plan action");
        source.insert(entry.path.clone(), entry.after.clone());
        if let Some(b) = &entry.before { ensure!(target.insert(entry.path.clone(), b.clone()).is_none(), "Overlapping target-only path"); }
    }
    for (name, value) in &plan.target_only_files {
        validate_fingerprint(value)?;
        portable(name)?;
        ensure!(!is_excluded(name) && seen.insert(name.to_lowercase()), "Invalid target-only path");
    }
    manifest_namespace(&source, &target)?;
    ensure!(!source.is_empty() && digest(&source)? == plan.source_digest && digest(&target)? == plan.target_digest, "Inconsistent manifest digests");
    Ok(())
}
fn verify_preconditions(plan: &Plan) -> Result<()> {
    validate_plan(plan)?;
    compatible_layouts(&plan.source, &plan.target)?;
    ensure!(digest(&tree(&plan.source)?)? == plan.source_digest, "Source changed after plan; re-plan");
    ensure!(digest(&tree(&plan.target)?)? == plan.target_digest, "Target changed after plan; re-plan");
    for e in &plan.entries {
        let dest = path_for(&plan.target, &e.path)?;
        ensure!(maybe_fingerprint(&dest)? == e.before, "Target path/type changed: {}", e.path);
    }
    Ok(())
}
fn make_plan(args: &Roots) -> Result<(Plan, PathBuf)> {
    let (source, target, state) = roots(args)?;
    let src = stable(&source, args.settle_ms)?;
    let dst = tree(&target)?;
    let baseline = load_baseline(&state, &source, &target)?;
    let mut entries = Vec::new();
    compatible_layouts(&source, &target)?;
    for (path, after) in &src {
        let before = dst.get(path).cloned();
        // Detect file-vs-directory/ancestor conflicts before creating a plan.
        ensure!(maybe_fingerprint(&path_for(&target, path)?)? == before, "Target path conflict: {path}");
        let action = match &before { None => Action::Create, Some(b) if b == after => Action::Same, _ => Action::Replace };
        let old = baseline.as_ref().and_then(|b| b.files.get(path));
        let local_changed = match (old, before.as_ref()) {
            (Some(a), Some(b)) => a != b,
            (Some(_), None) | (None, Some(_)) => true,
            (None, None) => false,
        };
        entries.push(Entry { path: path.clone(), action, before, after: after.clone(), local_changed_since_baseline: local_changed });
    }
    let target_only_files = dst.iter().filter(|(p, _)| !src.contains_key(*p)).map(|(p, f)| (p.clone(), f.clone())).collect();
    let mut plan = Plan { format_version: FORMAT, tool_version: VERSION.into(), plan_id: String::new(), nonce: nonce(), source, target,
        state_dir: state.clone(), source_digest: digest(&src)?, target_digest: digest(&dst)?,
        excludes: EXCLUDES.iter().map(|x| x.to_string()).collect(), entries, target_only_files };
    plan.plan_id = plan_hash(&plan)?;
    validate_plan(&plan)?;
    let file = state.join("plans").join(format!("{}.json", plan.plan_id));
    atomic_json(&file, &plan, false)?;
    Ok((plan, file))
}
fn summary(plan: &Plan, file: &Path) -> serde_json::Value {
    serde_json::json!({"plan_id": plan.plan_id, "plan_file": file, "source": plan.source, "target": plan.target,
        "create": plan.entries.iter().filter(|e| e.action == Action::Create).count(),
        "replace": plan.entries.iter().filter(|e| e.action == Action::Replace).count(),
        "same": plan.entries.iter().filter(|e| e.action == Action::Same).count(),
        "local_changes_that_will_be_overwritten": plan.entries.iter().filter(|e| e.action != Action::Same && e.local_changed_since_baseline).count(),
        "target_only_files_ignored": plan.target_only_files.len(), "source_latest_on_server": "not_verified"})
}
fn run_name(name: &str) -> Result<()> {
    ensure!(!name.is_empty() && name.len() <= 160 && name.bytes().all(|b| b.is_ascii_alphanumeric() || b == b'-'), "Invalid run ID");
    Ok(())
}
fn journal_path(state: &Path, id: &str) -> Result<PathBuf> {
    run_name(id)?;
    path_for(state, &format!("runs/{id}/journal.json"))
}
fn journals(state: &Path) -> Result<Vec<Journal>> {
    let dir = state.join("runs");
    if !dir.exists() { return Ok(Vec::new()); }
    check_ancestors(&dir)?;
    let mut items = Vec::new();
    for entry in fs::read_dir(dir)? {
        let entry = entry?;
        check_ancestors(&entry.path())?;
        ensure!(entry.file_type()?.is_dir(), "Invalid item in runs directory");
        let path = entry.path().join("journal.json");
        // An interrupted stage before the write-ahead journal touches no payload.
        if path.exists() {
            let j: Journal = read_json(&path)?;
            ensure!(j.format_version == FORMAT, "Unsupported journal format");
            validate_plan(&j.plan)?;
            run_name(&j.run_id)?;
            ensure!(entry.file_name().to_str() == Some(j.run_id.as_str()) && j.plan.state_dir == state, "Journal location mismatch");
            items.push(j);
        }
    }
    items.sort_by_key(|j| j.order);
    Ok(items)
}
fn assert_no_pending(state: &Path) -> Result<()> {
    for j in journals(state)? {
        ensure!(matches!(j.phase, Phase::Applied | Phase::RolledBack), "Unfinished run {}; review rollback before another apply", j.run_id);
    }
    Ok(())
}
fn apply(args: &ApplyArgs) -> Result<()> {
    let plan: Plan = read_json(&args.plan)?;
    validate_plan(&plan)?;
    ensure!(plan.tool_version == VERSION,
        "This plan was produced by an older tool. Generate/review a new plan before applying; historical rollback remains supported");
    let official = plan.state_dir.join("plans").join(format!("{}.json", plan.plan_id));
    ensure!(fs::canonicalize(&args.plan)? == fs::canonicalize(&official)?, "Use the plan in its recorded local state directory");
    if args.execute { ensure!(args.confirm.as_deref() == Some(plan.plan_id.as_str()), "Explicit --execute --confirm <plan-id> required"); }
    let _lock = if args.execute { Some(lock(&plan.target)?) } else { None };
    assert_no_pending(&plan.state_dir)?;
    verify_preconditions(&plan)?; // Dry-run checks actual freshness too.
    if !args.execute {
        let mut output = summary(&plan, &args.plan);
        output["dry_run"] = true.into();
        return emit(output);
    }
    check_target_storage(&plan.target, plan.entries.iter().any(|entry| entry.action == Action::Create))?;
    let run_id = format!("{}-{}", nonce(), &plan.plan_id[..12]);
    let run = plan.state_dir.join("runs").join(&run_id);
    private_dir(&run)?;
    let file = journal_path(&plan.state_dir, &run_id)?;
    // Stage *all* new bytes and verify *all* backups before changing any payload.
    for e in plan.entries.iter().filter(|e| e.action != Action::Same) {
        copy_new(&path_for(&plan.source, &e.path)?, &path_for(&run.join("staged"), &e.path)?, &e.after)?;
        if let Some(old) = &e.before {
            copy_new(&path_for(&plan.target, &e.path)?, &path_for(&run.join("backups"), &e.path)?, old)?;
        }
    }
    verify_preconditions(&plan)?;
    let order = journals(&plan.state_dir)?.iter().map(|j| j.order).max().unwrap_or(0).checked_add(1).context("Run sequence overflow")?;
    let mut j = Journal { format_version: FORMAT, run_id: run_id.clone(), order, phase: Phase::Prepared, plan: plan.clone(), completed_paths: Vec::new(), previous_baseline: load_baseline(&plan.state_dir, &plan.source, &plan.target)? };
    atomic_json(&file, &j, false)?;
    eprintln!("[cloud-wins] run_id: {run_id}; journal: {}", file.display());
    // A failure after this write leaves a recoverable, write-ahead journal. Do not
    // silently call the overall transaction atomic or delete evidence on failure.
    j.phase = Phase::Applying;
    atomic_json(&file, &j, true)?;
    for e in plan.entries.iter().filter(|e| e.action != Action::Same) {
        install(&path_for(&run.join("staged"), &e.path)?, &path_for(&plan.target, &e.path)?, &e.before, &e.after)?;
        j.completed_paths.push(e.path.clone());
        atomic_json(&file, &j, true)?;
    }
    ensure!(digest(&tree(&plan.source)?)? == plan.source_digest, "Source changed during apply; journal retained for rollback");
    let expected: Tree = plan.target_only_files.iter().map(|(p, f)| (p.clone(), f.clone()))
        .chain(plan.entries.iter().map(|e| (e.path.clone(), e.after.clone()))).collect();
    ensure!(tree(&plan.target)? == expected, "Post-apply target differs; journal retained for rollback");
    let baseline = Baseline { format_version: FORMAT, source: plan.source.clone(), target: plan.target.clone(), run_id: run_id.clone(),
        files: plan.entries.iter().map(|e| (e.path.clone(), e.after.clone())).collect(), workspace_files: expected };
    atomic_json(&plan.state_dir.join("baseline.json"), &baseline, true)?;
    j.phase = Phase::Applied;
    atomic_json(&file, &j, true)?;
    emit(serde_json::json!({"applied": true, "run_id": run_id, "journal": file, "backup_root": run.join("backups"), "live_configuration_applied": false}))
}
fn rollback(args: &RollbackArgs) -> Result<()> {
    let target = directory(&args.state.target)?;
    let state = directory(&args.state.state_dir)?;
    ensure!(!overlap(&target, &state), "State and target overlap");
    let file = journal_path(&state, &args.run)?;
    let mut j: Journal = read_json(&file)?;
    validate_plan(&j.plan)?;
    ensure!(j.format_version == FORMAT && j.run_id == args.run && j.plan.target == target && j.plan.state_dir == state, "Journal identity mismatch");
    if args.execute { ensure!(args.confirm.as_deref() == Some(j.run_id.as_str()), "Explicit --execute --confirm <run-id> required"); }
    let _lock = if args.execute { Some(lock(&target)?) } else { None };
    ensure!(j.phase != Phase::RolledBack, "Run is already rolled back");
    let latest = journals(&state)?.into_iter().filter(|r| r.phase != Phase::RolledBack).max_by_key(|r| r.order);
    ensure!(latest.as_ref().map(|r| &r.run_id) == Some(&j.run_id), "Only the latest unrolled run may be rolled back");
    if let Some(previous) = &j.previous_baseline {
        ensure!(previous.format_version == FORMAT && previous.target == target && previous.source == j.plan.source, "Previous baseline identity mismatch");
    }
    let run = state.join("runs").join(&j.run_id);
    let changes: Vec<Entry> = j.plan.entries.iter().filter(|e| e.action != Action::Same).cloned().collect();
    // Infer progress from old/new hashes, not just completed_paths: a process can
    // stop after rename but before its next journal write. This also makes a
    // partially completed rollback retryable.
    for e in &changes {
        let current = maybe_fingerprint(&path_for(&target, &e.path)?)?;
        ensure!(current == e.before || current.as_ref() == Some(&e.after), "Rollback would overwrite a later edit: {}", e.path);
        if let Some(old) = &e.before {
            ensure!(fingerprint(&path_for(&run.join("backups"), &e.path)?)? == *old, "Backup missing/corrupted: {}", e.path);
        }
    }
    if !args.execute { return emit(serde_json::json!({"dry_run": true, "run_id": j.run_id, "validated_entries": changes.len()})); }
    j.phase = Phase::RollingBack;
    atomic_json(&file, &j, true)?;
    for e in changes.iter().rev() {
        let dest = path_for(&target, &e.path)?;
        let current = maybe_fingerprint(&dest)?;
        if current == e.before { continue; }
        ensure!(current.as_ref() == Some(&e.after), "Target changed during rollback: {}", e.path);
        if let Some(old) = &e.before {
            install(&path_for(&run.join("backups"), &e.path)?, &dest, &Some(e.after.clone()), old)?;
        } else {
            fs::remove_file(&dest)?; // Only removes a file this run created, with matching hash.
            sync_parent(dest.parent().context("Missing rollback parent")?)?;
        }
    }
    let baseline = state.join("baseline.json");
    check_ancestors(&baseline)?;
    if let Some(previous) = &j.previous_baseline {
        atomic_json(&baseline, previous, true)?;
    } else if baseline.exists() {
        fs::remove_file(&baseline)?;
        sync_parent(&state)?;
    }
    j.phase = Phase::RolledBack;
    atomic_json(&file, &j, true)?;
    emit(serde_json::json!({"rolled_back": true, "run_id": j.run_id, "previous_baseline_restored": j.previous_baseline.is_some(), "live_configuration_restored": false}))
}
fn verify(args: &Roots) -> Result<()> {
    let (source, target, state) = roots(args)?;
    assert_no_pending(&state)?;
    let b = load_baseline(&state, &source, &target)?.context("No successful apply baseline; plan and apply first")?;
    let src = stable(&source, args.settle_ms)?;
    ensure!(src == b.files, "Mirror changed since the approved apply; generate/apply a new plan");
    let dst = tree(&target)?;
    ensure!(dst == b.workspace_files, "Workspace inventory changed since apply");
    for (name, expected) in &b.files {
        ensure!(dst.get(name) == Some(expected), "Workspace changed since apply: {name}");
    }
    emit(serde_json::json!({"verified": true, "run_id": b.run_id, "source": source, "target": target,
        "files": b.files.len(), "source_latest_on_server": "not_verified"}))
}
fn ready(args: &StateArgs) -> Result<()> {
    let target = directory(&args.target)?;
    let state = directory(&args.state_dir)?;
    ensure!(!overlap(&target, &state), "State and target overlap");
    assert_no_pending(&state)?;
    let b: Baseline = read_json(&state.join("baseline.json"))?;
    ensure!(b.format_version == FORMAT && b.target == target, "Baseline mismatch");
    let current = tree(&target)?;
    ensure!(current == b.workspace_files, "Approved workspace inventory changed");
    for (name, expected) in &b.files {
        ensure!(current.get(name) == Some(expected), "Approved workspace was edited: {name}");
    }
    let all = journals(&state)?;
    ensure!(all.iter().any(|j| j.run_id == b.run_id && j.phase == Phase::Applied), "Baseline has no completed run");
    emit(serde_json::json!({"ready": true, "run_id": b.run_id, "server_freshness": "not_checked"}))
}
fn execute(cli: Cli) -> Result<()> {
    match cli.command {
        Command::Probe(args) => {
            let (source, target, _) = roots(&args)?;
            let files = stable(&source, args.settle_ms)?;
            emit(serde_json::json!({"source_stable": true, "source": source, "target": target,
                "files": files.len(), "digest": digest(&files)?, "source_latest_on_server": "not_verified"}))
        }
        Command::Plan(args) => { let (p, file) = make_plan(&args)?; emit(summary(&p, &file)) }
        Command::Apply(args) => apply(&args),
        Command::Verify(args) => verify(&args),
        Command::Ready(args) => ready(&args),
        Command::Rollback(args) => rollback(&args),
        Command::Status(args) => {
            let target = directory(&args.target)?;
            let state = prospective(&args.state_dir)?;
            ensure!(!overlap(&target, &state), "State and target overlap");
            let baseline = if state.join("baseline.json").exists() { Some(read_json::<Baseline>(&state.join("baseline.json"))?) } else { None };
            let runs = journals(&state)?;
            emit(serde_json::json!({"target": target, "state_dir": state, "baseline": baseline,
                "runs": runs.iter().map(|j| serde_json::json!({"run_id": j.run_id, "phase": j.phase})).collect::<Vec<_>>()}))
        }
    }
}
fn main() {
    if let Err(e) = execute(Cli::parse()) {
        eprintln!("[cloud-wins] {e:#}\nNo source writes are performed. If a run_id was printed, inspect status/rollback before retrying apply.");
        std::process::exit(1);
    }
}

#[cfg(test)]
mod tests;
