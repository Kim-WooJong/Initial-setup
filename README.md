# Initial-setup v0.7.3

Windows, macOS, Linux에서 개인 개발 환경을 빠르게 구성하고, 여러 컴퓨터의 설정을 자동으로 동기화하기 위한 크로스플랫폼 환경 관리 도구입니다.

`Initial-setup`의 목표는 다음과 같습니다.

```text
새 컴퓨터
   ↓
setup.nu 실행
   ↓
개발 도구 / 설정 구성
   ↓
Private Cloud에서 개인 설정 복원
   ↓
이후 설정 변경은 자동 동기화
```

공개 Git 저장소에는 **설치 및 관리 스크립트만** 저장하고, 실제 개인 설정은 저장소 바깥의 Private Cloud 폴더에서 관리합니다.

---

## 주요 기능

- Windows / macOS / Linux 지원
- Nushell 중심의 단일 setup workflow
- chezmoi 기반 dotfiles 관리
- 여러 PC 간 양방향 자동 설정 동기화
- SHA-256 기반 local/cloud 변경 감지
- 동시 수정 시 conflict-safe 동작
- Neovim 전체 설정 동기화
- Nushell 설정 동기화
- WezTerm / Starship 설정 동기화
- VS Code 설정 및 확장 프로그램 동기화
- Git / SSH 공통 설정과 머신별 설정 분리
- Rust / Julia 개발 환경 구성
- CLI 도구 manifest 기반 설치
- Snapshot / Rollback
- 환경 검사 및 자동 복구
- 개발 환경 업데이트
- 동기화 로그 / 환경 리포트
- 머신별 secret 분리
- Rust / Julia / Python 프로젝트 bootstrap
- Workstation / Laptop / Server / Minimal profile

---

# 1. 기본 구조

권장 디렉터리 구조는 다음과 같습니다.

```text
PRIVATE-CLOUD-FOLDER/
├─ Initial-setup/               # GitHub 저장소
│  ├─ VERSION
│  ├─ setup.nu
│  ├─ bootstrap.ps1
│  ├─ bootstrap.sh
│  │
│  ├─ defaults/
│  │  ├─ wezterm.lua
│  │  └─ starship.toml
│  │
│  ├─ packages/
│  │  ├─ common.txt
│  │  ├─ windows.txt
│  │  ├─ macos.txt
│  │  └─ linux.txt
│  │
│  ├─ scripts/
│  │  ├─ auto-sync.nu
│  │  ├─ sync-up.nu
│  │  ├─ sync-down.nu
│  │  ├─ sync-fingerprint.nu
│  │  ├─ update-sync-state.nu
│  │  ├─ write-sync-meta.nu
│  │  │
│  │  ├─ create-snapshot.nu
│  │  ├─ rollback.nu
│  │  ├─ doctor.nu
│  │  ├─ update.nu
│  │  ├─ report.nu
│  │  ├─ log-event.nu
│  │  │
│  │  ├─ setup-platform-shims.nu
│  │  ├─ setup-local-overrides.nu
│  │  ├─ setup-secrets.nu
│  │  │
│  │  ├─ install-cli-tools.nu
│  │  ├─ install-language-tools.nu
│  │  ├─ install-starship.nu
│  │  ├─ install-wezterm.nu
│  │  ├─ install-vscode.nu
│  │  │
│  │  ├─ capture-vscode-config.nu
│  │  ├─ apply-vscode-config.nu
│  │  ├─ capture-vscode-extensions.nu
│  │  ├─ install-vscode-extensions.nu
│  │  │
│  │  ├─ new-project.nu
│  │  └─ modules/
│  │     └─ dotfiles.nu
│  │
│  ├─ README.md
│  └─ CHANGELOG.md
│
├─ .chezmoiroot                # Private
│
├─ home/                       # Private chezmoi source
│  ├─ dot_config/
│  │  ├─ nvim/
│  │  ├─ nushell/
│  │  ├─ wezterm/
│  │  └─ starship.toml
│  │
│  ├─ dot_cargo/
│  │  └─ config.toml
│  │
│  ├─ dot_julia/
│  │  └─ config/
│  │     └─ startup.jl
│  │
│  ├─ dot_gitconfig
│  └─ private_dot_ssh/
│
└─ vscode/                     # Private
   ├─ extensions.txt
   ├─ settings.json
   ├─ keybindings.json
   └─ snippets/
```

`home/`, `vscode/`, `.chezmoiroot`는 `Initial-setup` Git 저장소 밖에 있기 때문에 개인 설정이 실수로 GitHub에 올라가는 것을 방지합니다.

---

# 2. 설치

## 이미 Nushell / Git / Neovim / chezmoi가 설치되어 있는 경우

저장소 루트에서:

```nu
nu setup.nu
```

를 실행하면 됩니다.

첫 번째 기준 컴퓨터라면:

```nu
nu setup.nu --mode initial
```

다른 컴퓨터에서 Private Cloud의 설정을 내려받아 구성하는 경우:

```nu
nu setup.nu --mode existing
```

`auto`가 기본값이므로 일반적으로는:

```nu
nu setup.nu
```

만 실행하면 기존 private source 존재 여부를 기준으로 자동 판단합니다.

---

## 완전히 새로운 Windows PC

PowerShell에서:

```powershell
.\bootstrap.ps1
```

또는:

```powershell
.\bootstrap.ps1 -Mode initial
```

추가 컴퓨터:

```powershell
.\bootstrap.ps1 -Mode existing
```

`bootstrap.ps1`은 setup을 실행하기 위한 핵심 prerequisite를 먼저 설치합니다.

대표적으로:

- Git
- Nushell
- Neovim
- chezmoi
- VS Code

를 준비한 뒤 `setup.nu`를 실행합니다.

---

## macOS / Linux

```sh
chmod +x bootstrap.sh
./bootstrap.sh
```

첫 컴퓨터:

```sh
./bootstrap.sh --mode initial
```

추가 컴퓨터:

```sh
./bootstrap.sh --mode existing
```

---

# 3. Machine Profile

V0.7.x부터 profile을 실제 기능 설정과 연결합니다.

지원 profile:

```text
workstation
laptop
server
minimal
```

예:

```nu
nu setup.nu --profile workstation
```

```nu
nu setup.nu --profile server
```

## workstation

GUI 개발 환경 전체를 구성합니다.

```text
VS Code
WezTerm
Starship
Rust
Julia
CLI tools
Git
SSH
```

## laptop

기본적으로 workstation과 비슷한 구성을 사용하며, 필요에 따라 머신별 `config.nuon`에서 기능을 조절할 수 있습니다.

## server

GUI 프로그램을 제외한 서버 작업 환경을 구성합니다.

```text
Nushell
Neovim
Git
SSH
CLI tools
Starship
Rust
Julia
```

## minimal

최소한의 CLI 작업 환경을 구성합니다.

---

# 4. Dry Run

실제 변경 전에 setup이 무엇을 수행할지 확인할 수 있습니다.

```nu
nu setup.nu --dry-run
```

예:

```nu
nu setup.nu --profile server --dry-run
```

Dry-run에서는 파일, 패키지, scheduler를 변경하지 않습니다.

---

# 5. Machine-local 설정

각 컴퓨터에는 다음 파일이 생성됩니다.

```text
~/.config/dotfiles/config.nuon
```

예:

```nu
{
    version: "0.7.3"

    data_root: "..."
    tools_root: "..."

    machine: {
        name: "MY-PC"
        profile: "workstation"
        install_gui_apps: true
    }

    sync: {
        enabled: true
        interval_minutes: 1
        auto_push: true
        auto_pull: true
        conflict_policy: "stop"
        stability_delay_seconds: 3
    }

    maintenance: {
        snapshots_enabled: true
        snapshot_keep: 20
        log_keep_lines: 2000
    }

    features: {
        cli_tools: true
        vscode: true
        wezterm: true
        starship: true
        rust: true
        julia: true
        git_config: true
        ssh_config: true
    }
}
```

편집:

```nu
dotconfig
```

scheduler interval이나 profile, feature 설정을 변경한 경우:

```nu
nu setup.nu
```

를 다시 실행하는 것을 권장합니다.

---

# 6. 자동 동기화

자동 동기화의 기본 구조:

```text
PC A에서 config 수정
        ↓
Local fingerprint 변경
        ↓
auto-sync
        ↓
chezmoi re-add
        ↓
Private Cloud source
        ↓
Cloud client
        ↓
PC B / PC C
        ↓
Cloud fingerprint 변경
        ↓
chezmoi apply
        ↓
최신 config 반영
```

기본 주기:

```nu
interval_minutes: 1
```

운영체제별 scheduler:

- Windows: Task Scheduler
- Linux: systemd user timer
- macOS: LaunchAgent

---

# 7. Conflict 처리

마지막 정상 동기화 이후 Local과 Cloud가 모두 변경된 경우 자동으로 어느 한쪽을 덮어쓰지 않습니다.

기본값:

```nu
conflict_policy: "stop"
```

Conflict가 발생하면:

```text
~/.config/dotfiles/SYNC-CONFLICT.txt
```

가 생성됩니다.

Local 설정을 기준으로 해결:

```nu
dotpush
```

Cloud 설정을 기준으로 해결:

```nu
dotpull
```

지원 정책:

```text
stop
prefer_local
prefer_cloud
```

일반적인 사용에서는 `stop`을 권장합니다.

---

# 8. 동기화 상태

```nu
dotstatus
```

예:

```text
Automatic Sync
────────────────────────────────
Machine       : MacStudio
Profile       : workstation
Enabled       : true
Interval      : 1 minute(s)
Auto push     : true
Auto pull     : true
Conflict mode : stop
Last sync     : 2026-09-12 ...
Last writer   : MacStudio
Writer time   : 2026-09-12 ...
Last action   : push
Local         : clean
Cloud         : clean
Conflict      : none
```

즉시 자동 동기화 cycle 실행:

```nu
dotsync
```

현재 Local을 기준으로 강제 push:

```nu
dotpush
```

Cloud를 기준으로 강제 pull:

```nu
dotpull
```

chezmoi diff:

```nu
dotdiff
```

---

# 9. 동기화 대상

## Nushell

```text
config.nu
env.nu
modules/
autoload/
```

## Neovim

전체 config directory를 관리합니다.

예:

```text
~/.config/nvim/
├─ init.lua
├─ lua/
└─ lazy-lock.json
```

Windows에서는 실제 Neovim config 경로와 canonical config 경로가 다른 경우 platform shim을 사용합니다.

Lua shim 안의 Windows 경로는:

```lua
C:/Users/name/.config/nvim
```

처럼 `/`를 사용합니다.

## WezTerm

```text
~/.config/wezterm/wezterm.lua
```

## Starship

```text
~/.config/starship.toml
```

## Git

공통 설정:

```text
~/.gitconfig
```

머신별 설정:

```text
~/.gitconfig.local
```

편집:

```nu
dotgitlocal
```

공통 `.gitconfig`에서 local config를 include합니다.

## SSH

공통:

```text
~/.ssh/config
```

머신별:

```text
~/.ssh/config.local
```

편집:

```nu
dotsshlocal
```

SSH private key는 동기화하지 않습니다.

## Rust

```text
~/.cargo/config.toml
```

## Julia

```text
~/.julia/config/startup.jl
```

## VS Code

동기화 항목:

```text
settings.json
keybindings.json
snippets/
extensions.txt
```

확장 프로그램은 단순 추가가 아니라 authoritative machine의 목록과 동일하게 맞춥니다.

---

# 10. Package Manifest

CLI package 목록은 installer와 분리되어 있습니다.

```text
packages/
├─ common.txt
├─ windows.txt
├─ macos.txt
└─ linux.txt
```

기본 공통 도구:

```text
ripgrep
fd
fzf
bat
zoxide
direnv
git-delta
lazygit
```

새 CLI 프로그램을 공통 환경에 추가하려면 manifest를 수정하는 방식이 권장됩니다.

---

# 11. Snapshot

수동 snapshot:

```nu
dotsnapshot
```

이름 지정:

```nu
dotsnapshot --label before-nvim-change
```

기본 저장 위치:

```text
~/.config/dotfiles/snapshots/
```

Snapshot은 머신 로컬에 보관합니다.

기본 보존 개수:

```nu
snapshot_keep: 20
```

`dotpush` 실행 전에도 자동으로 `pre-push` snapshot을 생성합니다.

---

# 12. Rollback

Snapshot 목록:

```nu
dotrollback --list
```

가장 최근 snapshot 복원:

```nu
dotrollback
```

특정 snapshot:

```nu
dotrollback --snapshot 20260912-031500-before-nvim-change
```

Rollback 전에도 현재 상태를 `pre-rollback` snapshot으로 보존합니다.

---

# 13. Doctor

환경 검사:

```nu
dotdoctor
```

자동 복구:

```nu
dotdoctor --fix
```

복구 대상에는 다음이 포함됩니다.

- private source 구조
- Neovim / Nushell platform shim
- Nushell 관리 module
- Git / SSH local override
- machine-local secrets
- CLI tools
- Starship
- WezTerm
- sync baseline
- auto-sync scheduler

---

# 14. Update

전체 개발 환경 업데이트:

```nu
dotupdate
```

세부 옵션:

```nu
dotupdate --repo
dotupdate --tools
dotupdate --config
dotupdate --all
```

대상에는 환경에 따라 다음이 포함됩니다.

- Initial-setup Git repository
- Winget / Homebrew / Linux package manager 도구
- rustup
- juliaup
- Neovim Lazy plugins
- private config apply
- doctor

업데이트 전에는 snapshot을 생성합니다.

---

# 15. 동기화 Log

자동 sync 관련 이벤트는 다음 위치에 기록됩니다.

```text
~/.config/dotfiles/logs/sync.log
```

최근 로그:

```nu
dotlog
```

200줄:

```nu
dotlog --lines 200
```

로그 초기화:

```nu
dotlog --clear
```

기본 최대 보존 줄 수:

```nu
log_keep_lines: 2000
```

---

# 16. Environment Report

현재 머신의 환경을 정리해서 출력:

```nu
dotreport
```

파일로 저장:

```nu
dotreport --save
```

대표적으로 다음 정보를 포함합니다.

- Initial-setup version
- OS
- machine profile
- Nushell
- Git
- Neovim
- chezmoi
- Starship
- WezTerm
- Rust
- Cargo
- Julia
- git-delta
- lazygit
- sync 상태
- 마지막 writer
- conflict 상태

문제가 발생했을 때 `dotreport` 결과를 이용하면 환경 비교가 쉽습니다.

---

# 17. Machine-local Secrets

Secret은 Private Cloud에 동기화하지 않습니다.

Initial-setup은 Nushell의 machine-local autoload를 사용합니다.

```text
$nu.data-dir/vendor/autoload/dotfiles-secrets.nu
```

편집:

```nu
dotsecrets
```

예:

```nu
$env.MY_API_KEY = "..."
```

공용 `env.nu`에 API key나 token을 직접 넣지 않는 것을 권장합니다.

---

# 18. Project Bootstrap

## Rust

```nu
newproj rust my-tool
```

## Julia

```nu
newproj julia detector-analysis
```

## Python

```nu
newproj python quick-analysis
```

## Generic

```nu
newproj generic my-project
```

특정 위치:

```nu
newproj rust my-tool --path D:/Projects
```

---

# 19. 주요 명령어

## Sync

```text
dotstatus
dotdiff
dotsync
dotpush
dotpull
```

## Recovery

```text
dotsnapshot
dotrollback
dotdoctor
```

## Maintenance

```text
dotupdate
dotreport
dotlog
```

## Machine-local

```text
dotconfig
dotsecrets
dotgitlocal
dotsshlocal
```

## Managed configuration

```text
dotnvim
dotnu
dotenv
dotwezterm
dotstarship
```

## Project

```text
newproj
```

## Directory

```text
dotdata
dottools
```

---

# 20. Version

프로젝트 버전은 저장소 루트의:

```text
VERSION
```

파일을 기준으로 관리합니다.

V0.7.2:

```text
0.7.2
```

Nushell에서 버전을 읽을 때는 UTF-8 문자열로 변환하여 사용하는 것이 안전합니다.

```nu
def app-version [] {
    let version_file = ($TOOLS_ROOT | path join "VERSION")
    open $version_file --raw | decode utf-8 | str trim
}
```

프로젝트 내 표시용 버전은 가능한 한 `VERSION` 파일을 기준으로 읽고, 여러 파일에 동일 버전 문자열을 중복 하드코딩하지 않는 구조를 권장합니다.

Git tag / 자동 release workflow는 별도 릴리스 관리 기능으로 확장할 수 있습니다.

---

# 21. Nushell 작성 규칙

이 프로젝트는 Nushell 0.109 계열에서 실제로 발생한 parser 차이를 고려합니다.

특히 custom command의 positional argument는 다음처럼 한 줄로 작성하는 방식을 권장합니다.

권장:

```nu
run-program ("Install " + $name) "winget" $args
```

피해야 하는 형태:

```nu
run-program
    ("Install " + $name)
    "winget"
    $args
```

Boolean expression도 가능한 한 한 물리적 줄에 유지합니다.

권장:

```nu
| where { |line| not ($line | is-empty) and not ($line | str starts-with "#") }
```

Custom command가 positional argument를 받도록 정의되어 있다면 pipeline input으로 암묵적으로 전달하지 않습니다.

예:

```nu
def xml-escape [value: string] {
    $value
    | str replace --all '&' '&amp;'
}
```

호출:

```nu
let value = (xml-escape ($path | into string))
```

Windows CLI의 binary output 문제를 피하기 위해 `winget` 등의 installer command에서는 `complete | str trim` 패턴을 사용하지 않습니다.

---

# 22. 권장 운영 방식

평소에는 config 파일을 일반적으로 수정하면 됩니다.

예:

```nu
nvim ~/.config/nushell/config.nu
```

또는:

```nu
nvim ~/.config/nvim/init.lua
```

자동 sync가 변경을 감지합니다.

일반적인 운영 흐름:

```text
config 수정
   ↓
1분 이내 local 변경 감지
   ↓
private source update
   ↓
cloud client sync
   ↓
다른 PC에서 cloud 변경 감지
   ↓
자동 apply
```

따라서 정상적인 환경에서는 `dotpush`와 `dotpull`을 자주 사용할 필요가 없습니다.

이 두 명령은 주로 conflict 해결이나 강제 동기화에 사용합니다.

---

# 23. 현재 단계

V0.7.2는 기본적인 개인 작업환경 동기화 기능이 갖춰진 단계입니다.

현재 핵심 범위:

```text
Bootstrap
Configuration management
Cross-machine sync
Conflict protection
Recovery
Maintenance
Diagnostics
Machine profiles
Local secrets
Project bootstrap
```

향후에는 기능 추가보다 다음 항목을 우선하는 것이 권장됩니다.

- Windows / macOS / Linux 실제 통합 테스트
- Nushell parser compatibility 안정화
- Git 기반 release workflow
- VERSION 단일 원본화
- CI 기반 syntax / regression 검사
- V1.0 release 후보 안정화

---

# Nushell Home Directory Compatibility

Different Nushell releases may expose the user's home directory as either:

```nu
$nu.home-path
```

or:

```nu
$nu.home-dir
```

Initial-setup v0.7.3 no longer accesses either field directly.

Every Nushell script that requires the home directory uses the same resolver:

```nu
def nu-home [] {
    let home_path = ($nu | get --optional home-path)

    if $home_path != null {
        return $home_path
    }

    let home_dir = ($nu | get --optional home-dir)

    if $home_dir != null {
        return $home_dir
    }

    error make {
        msg: "Unable to determine the Nushell home directory."
    }
}
```

This allows the same scripts to work with Nushell versions that provide
`home-path` as well as versions that provide `home-dir`.

Direct references to `$nu.home-path` and `$nu.home-dir` are prohibited by the
release audit so that new scripts do not accidentally reintroduce a
version-specific dependency.

