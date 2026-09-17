use super::*;

struct Fixture { base: PathBuf, args: Roots }
impl Fixture {
    fn new() -> Self {
        let base = canonical_existing(&std::env::temp_dir()).unwrap().join(format!("cloudwins-tests-{}", nonce()));
        let args = Roots { source: base.join("cloud source 한글"), target: base.join("local target"), state_dir: base.join("state"), settle_ms: 0 };
        fs::create_dir_all(&args.source).unwrap();
        fs::create_dir_all(&args.target).unwrap();
        fs::write(args.source.join("config.nu"), b"new configuration").unwrap();
        fs::write(args.target.join("config.nu"), b"old configuration").unwrap();
        Self { base, args }
    }
    fn plan(&self) -> (Plan, PathBuf) { make_plan(&self.args).unwrap() }
    fn apply(&self, p: &Plan, path: &Path) -> Result<()> {
        apply(&ApplyArgs { plan: path.into(), execute: true, confirm: Some(p.plan_id.clone()) })
    }
    fn run_id(&self) -> String {
        journals(&self.args.state_dir).unwrap().last().unwrap().run_id.clone()
    }
    fn rollback(&self, id: &str, execute: bool) -> Result<()> {
        rollback(&RollbackArgs { state: StateArgs { target: self.args.target.clone(), state_dir: self.args.state_dir.clone() }, run: id.into(), execute, confirm: Some(id.into()) })
    }
}
impl Drop for Fixture { fn drop(&mut self) { let _ = fs::remove_dir_all(&self.base); } }

#[test]
fn sha256_vector() {
    let f = Fixture::new();
    fs::write(f.args.source.join("abc"), b"abc").unwrap();
    assert_eq!(fingerprint(&f.args.source.join("abc")).unwrap().sha256, "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad");
}
#[test]
fn path_traversal_and_windows_names_rejected() {
    for s in ["", "../x", "/root", "x//y", "x/./y", "x\\y", "C:x", "NUL.txt", "a/COM1", "a.", "a ", "x\ny"] { assert!(portable(s).is_err(), "{s:?}"); }
    for s in ["home/config.nu", "한국어/자료.toml", ".chezmoiroot", "COM10"] { assert!(portable(s).is_ok()); }
}
#[test]
fn read_only_probe_does_not_create_target_or_state() {
    let f = Fixture::new();
    let mut a = f.args.clone();
    a.target = f.base.join("absent");
    assert!(roots(&a).is_err());
    assert!(!a.target.exists());
    assert!(!a.state_dir.exists());
    roots(&f.args).unwrap();
    stable(&f.args.source, 0).unwrap();
    assert!(!f.args.state_dir.exists());
}
#[test]
fn roots_and_state_must_be_disjoint() {
    let f = Fixture::new();
    let mut a = f.args.clone();
    a.target = a.source.clone();
    assert!(roots(&a).is_err());
    a = f.args.clone();
    a.state_dir = a.source.join("state");
    assert!(roots(&a).is_err());
    assert!(!a.state_dir.exists());
    a.state_dir = a.target.join("state");
    assert!(roots(&a).is_err());
}
#[test]
fn empty_source_rejected() {
    let f = Fixture::new();
    fs::remove_file(f.args.source.join("config.nu")).unwrap();
    assert!(make_plan(&f.args).is_err());
}
#[test]
fn plan_does_not_change_payloads() {
    let f = Fixture::new();
    let source = tree(&f.args.source).unwrap();
    let target = tree(&f.args.target).unwrap();
    let (p, _) = f.plan();
    assert_eq!(p.entries[0].action, Action::Replace);
    assert_eq!(source, tree(&f.args.source).unwrap());
    assert_eq!(target, tree(&f.args.target).unwrap());
    assert!(!f.args.target.join(".initial-setup-state").exists());
}
#[test]
fn source_authoritative_and_target_only_retained() {
    let f = Fixture::new();
    fs::write(f.args.source.join("new.txt"), b"new").unwrap();
    fs::write(f.args.target.join("local-only"), b"do not delete").unwrap();
    let original = tree(&f.args.source).unwrap();
    let (p, path) = f.plan();
    f.apply(&p, &path).unwrap();
    assert_eq!(tree(&f.args.source).unwrap(), original);
    assert_eq!(fs::read(f.args.target.join("new.txt")).unwrap(), b"new");
    assert_eq!(fs::read(f.args.target.join("local-only")).unwrap(), b"do not delete");
    verify(&f.args).unwrap();
}
#[test]
fn explicit_confirmation_required() {
    let f = Fixture::new();
    let (p, path) = f.plan();
    assert!(apply(&ApplyArgs { plan: path.clone(), execute: true, confirm: None }).is_err());
    assert!(apply(&ApplyArgs { plan: path.clone(), execute: true, confirm: Some("wrong".into()) }).is_err());
    apply(&ApplyArgs { plan: path, execute: false, confirm: None }).unwrap();
    assert_eq!(fs::read(f.args.target.join("config.nu")).unwrap(), b"old configuration");
    assert_eq!(p.entries.len(), 1);
}
#[test]
fn changed_source_rejects_apply_and_preview() {
    let f = Fixture::new();
    let (p, path) = f.plan();
    fs::write(f.args.source.join("config.nu"), b"changed").unwrap();
    assert!(f.apply(&p, &path).is_err());
    assert!(apply(&ApplyArgs { plan: path, execute: false, confirm: None }).is_err());
    assert_eq!(fs::read(f.args.target.join("config.nu")).unwrap(), b"old configuration");
}
#[test]
fn changed_same_file_is_detected() {
    let f = Fixture::new();
    fs::copy(f.args.source.join("config.nu"), f.args.target.join("config.nu")).unwrap();
    let (p, path) = f.plan();
    assert_eq!(p.entries[0].action, Action::Same);
    fs::write(f.args.target.join("config.nu"), b"edited after plan").unwrap();
    assert!(f.apply(&p, &path).is_err());
}
#[test]
fn target_only_edit_invalidates_plan() {
    let f = Fixture::new();
    fs::write(f.args.target.join("local"), b"one").unwrap();
    let (p, path) = f.plan();
    fs::write(f.args.target.join("local"), b"two").unwrap();
    assert!(f.apply(&p, &path).is_err());
}
#[test]
fn edited_plan_is_rejected() {
    let f = Fixture::new();
    let (mut p, path) = f.plan();
    p.entries[0].path = "../escape".into();
    atomic_json(&path, &p, true).unwrap();
    assert!(f.apply(&p, &path).is_err());
    p.plan_id = plan_hash(&p).unwrap();
    assert!(validate_plan(&p).is_err());
}
#[test]
fn file_directory_conflict_fails_at_plan() {
    let f = Fixture::new();
    fs::remove_file(f.args.target.join("config.nu")).unwrap();
    fs::create_dir(f.args.target.join("config.nu")).unwrap();
    assert!(make_plan(&f.args).is_err());
}
#[test]
fn case_collision_across_trees_is_rejected() {
    let f = Fixture::new();
    fs::remove_file(f.args.target.join("config.nu")).unwrap();
    fs::write(f.args.target.join("Config.nu"), b"keep").unwrap();
    assert!(make_plan(&f.args).is_err());
}
#[test]
fn rollback_restores_replacements_and_removes_only_created_files() {
    let f = Fixture::new();
    fs::write(f.args.source.join("new"), b"new").unwrap();
    fs::write(f.args.target.join("local"), b"keep").unwrap();
    let before = tree(&f.args.target).unwrap();
    let (p, path) = f.plan();
    f.apply(&p, &path).unwrap();
    let id = f.run_id();
    f.rollback(&id, false).unwrap();
    assert!(f.args.target.join("new").exists());
    f.rollback(&id, true).unwrap();
    assert_eq!(tree(&f.args.target).unwrap(), before);
    assert!(f.rollback(&id, true).is_err());
}
#[test]
fn rollback_preserves_later_edits() {
    let f = Fixture::new();
    let (p, path) = f.plan();
    f.apply(&p, &path).unwrap();
    fs::write(f.args.target.join("config.nu"), b"later edit").unwrap();
    assert!(f.rollback(&f.run_id(), false).is_err());
    assert!(f.rollback(&f.run_id(), true).is_err());
    assert_eq!(fs::read(f.args.target.join("config.nu")).unwrap(), b"later edit");
}
#[test]
fn corrupted_backup_stops_rollback_before_any_change() {
    let f = Fixture::new();
    let (p, path) = f.plan();
    f.apply(&p, &path).unwrap();
    let id = f.run_id();
    let backup = f.args.state_dir.join("runs").join(&id).join("backups/config.nu");
    fs::write(backup, b"corruption").unwrap();
    assert!(f.rollback(&id, false).is_err());
    assert_eq!(fs::read(f.args.target.join("config.nu")).unwrap(), b"new configuration");
}
#[test]
fn rollback_works_when_cloud_is_offline() {
    let f = Fixture::new();
    let (p, path) = f.plan();
    f.apply(&p, &path).unwrap();
    let id = f.run_id();
    fs::rename(&f.args.source, f.base.join("offline-source")).unwrap();
    f.rollback(&id, true).unwrap();
    assert_eq!(fs::read(f.args.target.join("config.nu")).unwrap(), b"old configuration");
}
#[test]
fn write_ahead_journal_recovers_missing_progress_marker() {
    let f = Fixture::new();
    let (p, path) = f.plan();
    f.apply(&p, &path).unwrap();
    let id = f.run_id();
    let jp = journal_path(&f.args.state_dir, &id).unwrap();
    let mut j: Journal = read_json(&jp).unwrap();
    j.phase = Phase::Applying;
    j.completed_paths.clear();
    atomic_json(&jp, &j, true).unwrap();
    assert!(assert_no_pending(&f.args.state_dir).is_err());
    f.rollback(&id, true).unwrap();
    assert_eq!(fs::read(f.args.target.join("config.nu")).unwrap(), b"old configuration");
}
#[test]
fn rollback_can_resume_from_partially_restored_files() {
    let f = Fixture::new();
    fs::write(f.args.source.join("new"), b"new").unwrap();
    let (p, path) = f.plan();
    f.apply(&p, &path).unwrap();
    let id = f.run_id();
    let jp = journal_path(&f.args.state_dir, &id).unwrap();
    let mut j: Journal = read_json(&jp).unwrap();
    j.phase = Phase::RollingBack;
    atomic_json(&jp, &j, true).unwrap();
    fs::remove_file(f.args.target.join("new")).unwrap();
    f.rollback(&id, true).unwrap();
    assert_eq!(fs::read(f.args.target.join("config.nu")).unwrap(), b"old configuration");
}
#[test]
fn old_run_cannot_be_rolled_back_over_new_run() {
    let f = Fixture::new();
    let (p, path) = f.plan();
    f.apply(&p, &path).unwrap();
    let old = f.run_id();
    fs::write(f.args.source.join("config.nu"), b"third version").unwrap();
    let (p, path) = f.plan();
    f.apply(&p, &path).unwrap();
    assert!(f.rollback(&old, true).is_err());
}
#[test]
fn os_lock_excludes_a_second_writer() {
    let f = Fixture::new();
    let guard = lock(&f.args.target).unwrap();
    assert!(lock(&f.args.target).is_err());
    drop(guard);
    assert!(lock(&f.args.target).is_ok());
}
#[test]
fn excludes_are_pruned_before_traversal() {
    let f = Fixture::new();
    fs::create_dir_all(f.args.source.join(".git")).unwrap();
    fs::write(f.args.source.join(".git/HEAD"), b"excluded").unwrap();
    assert_eq!(tree(&f.args.source).unwrap().len(), 1);
}
#[cfg(unix)]
#[test]
fn symlink_source_target_and_state_rejected() {
    use std::os::unix::fs::symlink;
    let f = Fixture::new();
    symlink(f.args.source.join("config.nu"), f.args.source.join("link")).unwrap();
    assert!(make_plan(&f.args).is_err());
    fs::remove_file(f.args.source.join("link")).unwrap();
    let (p, path) = f.plan();
    fs::remove_file(f.args.target.join("config.nu")).unwrap();
    symlink(f.args.source.join("config.nu"), f.args.target.join("config.nu")).unwrap();
    assert!(f.apply(&p, &path).is_err());
    assert_eq!(fs::read(f.args.source.join("config.nu")).unwrap(), b"new configuration");
}
#[test]
fn live_apply_readiness_rejects_unreviewed_extra_files() {
    let f = Fixture::new();
    let (p, path) = f.plan();
    f.apply(&p, &path).unwrap();
    let args = StateArgs { target: f.args.target.clone(), state_dir: f.args.state_dir.clone() };
    ready(&args).unwrap();
    fs::write(f.args.target.join("unreviewed"), b"extra").unwrap();
    assert!(ready(&args).is_err());
}
#[test]
fn rollback_restores_previous_baseline() {
    let f = Fixture::new();
    let (p, path) = f.plan();
    f.apply(&p, &path).unwrap();
    let first = f.run_id();
    fs::write(f.args.source.join("config.nu"), b"third version").unwrap();
    let (p, path) = f.plan();
    f.apply(&p, &path).unwrap();
    f.rollback(&f.run_id(), true).unwrap();
    let b = load_baseline(&f.args.state_dir, &f.args.source, &f.args.target).unwrap().unwrap();
    assert_eq!(b.run_id, first);
    ready(&StateArgs { target: f.args.target.clone(), state_dir: f.args.state_dir.clone() }).unwrap();
}

#[test]
fn stable_writer_versions_are_bounded() {
    assert!(supported_writer("0.13.2"));
    assert!(supported_writer(VERSION));
    for value in ["0.13.1", "0.13.3-rc.1", "00.13.3", "0.13", "invalid"] {
        assert!(!supported_writer(value), "{value}");
    }
    let (major, minor, patch) = stable_version(VERSION).unwrap();
    assert!(!supported_writer(&format!("{major}.{minor}.{}", patch + 1)));
}
#[test]
fn empty_directory_case_collision_is_rejected() {
    let f = Fixture::new();
    fs::create_dir(f.args.source.join("Settings")).unwrap();
    fs::write(f.args.source.join("Settings/value"), b"cloud").unwrap();
    fs::create_dir(f.args.target.join("settings")).unwrap();
    assert!(make_plan(&f.args).is_err());
}
#[test]
fn late_empty_directory_collision_stops_apply() {
    let f = Fixture::new();
    fs::create_dir(f.args.source.join("Settings")).unwrap();
    fs::write(f.args.source.join("Settings/value"), b"cloud").unwrap();
    let (p, path) = f.plan();
    fs::create_dir(f.args.target.join("settings")).unwrap();
    assert!(f.apply(&p, &path).is_err());
    assert_eq!(fs::read(f.args.target.join("config.nu")).unwrap(), b"old configuration");
}
#[test]
fn source_empty_directory_cannot_alias_a_target_file() {
    let f = Fixture::new();
    fs::create_dir(f.args.source.join("local")).unwrap();
    fs::write(f.args.target.join("local"), b"keep").unwrap();
    assert!(make_plan(&f.args).is_err());
    assert_eq!(fs::read(f.args.target.join("local")).unwrap(), b"keep");
}
#[test]
fn serialized_manifest_detects_ancestor_namespace_conflicts() {
    let value = Fingerprint { bytes: 0, sha256: "0".repeat(64) };
    let mut source = Tree::new();
    let mut target = Tree::new();
    source.insert("A/file".into(), value.clone());
    target.insert("a/other".into(), value.clone());
    assert!(manifest_namespace(&source, &target).is_err());
    target.clear();
    target.insert("A".into(), value);
    assert!(manifest_namespace(&source, &target).is_err());
}
#[test]
fn fingerprints_require_lowercase_sha256_hex() {
    let invalid = [String::new(), "xyz".to_owned(), "G".repeat(64), "F".repeat(64), "a".repeat(63)];
    for value in invalid {
        assert!(validate_fingerprint(&Fingerprint { bytes: 0, sha256: value }).is_err());
    }
    assert!(validate_fingerprint(&Fingerprint { bytes: 0, sha256: "a".repeat(64) }).is_ok());
}
#[test]
fn older_writer_journal_remains_readable_and_recoverable() {
    let f = Fixture::new();
    let (p, path) = f.plan();
    f.apply(&p, &path).unwrap();
    let id = f.run_id();
    let jp = journal_path(&f.args.state_dir, &id).unwrap();
    let mut j: Journal = read_json(&jp).unwrap();
    j.plan.tool_version = "0.13.2".into();
    j.plan.plan_id = plan_hash(&j.plan).unwrap();
    atomic_json(&jp, &j, true).unwrap();
    assert_no_pending(&f.args.state_dir).unwrap();
    assert_eq!(journals(&f.args.state_dir).unwrap().len(), 1);
    fs::rename(&f.args.source, f.base.join("cloud-offline")).unwrap();
    f.rollback(&id, true).unwrap();
    assert_eq!(fs::read(f.args.target.join("config.nu")).unwrap(), b"old configuration");
}
#[test]
fn older_writer_plan_requires_regeneration_before_apply() {
    let f = Fixture::new();
    let (mut p, _) = f.plan();
    p.tool_version = "0.13.2".into();
    p.plan_id = plan_hash(&p).unwrap();
    let path = f.args.state_dir.join("plans").join(format!("{}.json", p.plan_id));
    atomic_json(&path, &p, false).unwrap();
    validate_plan(&p).unwrap();
    let error = f.apply(&p, &path).unwrap_err().to_string();
    assert!(error.contains("Generate/review a new plan"), "{error}");
    assert_eq!(fs::read(f.args.target.join("config.nu")).unwrap(), b"old configuration");
}
#[test]
fn storage_preflight_cleans_its_temporary_files() {
    let f = Fixture::new();
    let before = layout(&f.args.target).unwrap();
    check_target_storage(&f.args.target, true).unwrap();
    assert_eq!(layout(&f.args.target).unwrap(), before);
    check_target_storage(&f.args.target, false).unwrap();
    assert_eq!(layout(&f.args.target).unwrap(), before);
}
#[test]
fn oversized_json_is_rejected_before_deserialization() {
    let f = Fixture::new();
    let path = f.base.join("oversized.json");
    let file = File::create(&path).unwrap();
    file.set_len(64 * 1024 * 1024 + 1).unwrap();
    drop(file);
    assert!(read_json::<serde_json::Value>(&path).is_err());
}
