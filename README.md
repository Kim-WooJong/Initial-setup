# Initial-setup v0.12.25

Windows, macOS, Linux 작업환경을 Nushell + chezmoi 기반으로 설치·동기화·복구하는 개인 환경 관리 프로젝트입니다.

## Quick start

### Windows

Nushell이 이미 있다면:

```powershell
cd C:\path\to\Initial-setup
nu --no-config-file .\setup.nu
```

새 PC라면 bootstrap부터:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\bootstrap.ps1
```

### macOS / Linux

```bash
chmod +x bootstrap.sh
./bootstrap.sh
```

Nushell이 이미 있다면:

```bash
nu --no-config-file setup.nu
```

## First setup

`setup.nu`가 profile과 설정 동기화 방향을 안내합니다.

Profiles:

- `workstation` — 일반 개발 PC
- `laptop` — 노트북
- `server` — GUI가 적은 서버 환경
- `minimal` — 최소 CLI 환경

설정 충돌 시 로컬을 private source에 저장하거나, private 설정을 로컬에 적용하거나, diff/backup 후 결정할 수 있습니다.

## 자주 쓰는 명령

| 명령 | 용도 |
|---|---|
| `dotpreflight --diff` | 로컬과 private 설정 차이 확인 |
| `dotpush` | 현재 설정을 private source에 저장 |
| `dotpull` | private 설정을 현재 PC에 적용 |
| `dotresolve` | 충돌/3-way merge 처리 |
| `dotdoctor` | 환경 상태 검사 |
| `dotaudit` | 관리 대상 전체 점검 |
| `dotlocalbackup` | 로컬 설정 백업 |
| `dotrollback` | snapshot 복구 |
| `dotrun --list` | setup 실행 기록 확인 |
| `dotsshkeys` | SSH key 상태 확인 |
| `dotvault status` | 암호화 secret 상태 확인 |
| `dotbackend status` | 동기화 backend 상태 확인 |

## Sync providers

세 가지 backend를 지원합니다.

- `directory` — OneDrive/Proton Drive 같은 로컬 동기화 폴더. 현재 기본 방식.
- `local` — NAS/공유 파일시스템.
- `rclone` — rclone remote를 직접 사용한 revision 기반 동기화.

`directory` backend는 같은 PC에서 `operation.lock`만 사용하고, 다른 PC의 변경은 revision/tree hash로 감지합니다.

rclone을 장기적으로 주 backend로 사용하는 계획은 [`ROADMAP.md`](ROADMAP.md)에 정리되어 있습니다.

## Backup / recovery

설정 변경 전에는:

```nu
dotlocalbackup
```

setup이 중단됐으면:

```nu
dotrun --list
nu setup.nu --resume --run-id <RUN_ID>
```

snapshot 복구:

```nu
dotrollback
```

## Validation

일반 setup에서는 전체 소스 검사를 자동 실행하지 않습니다.

개발·디버깅할 때만:

```nu
dotvalidate
dottest --sandbox
```

setup 전에 강제 검사하려면:

```nu
nu setup.nu --validate
```

## Troubleshooting

### Lock 오류

먼저 상태만 확인합니다.

```nu
nu --no-config-file scripts/lock-status.nu
```

실행 중인 setup/sync 작업이 있는 동안 lock을 삭제하지 마세요.

### 예상하지 못한 설정 변경

```nu
dotpreflight --diff
dotresolve
```

### rclone / private source

```nu
dotbackend status
rclone listremotes
```

## More

- 변경 이력: [`CHANGELOG.md`](CHANGELOG.md)
- 향후 계획: [`ROADMAP.md`](ROADMAP.md)

대부분의 경우 **`nu setup.nu` → `dotpreflight --diff` → `dotaudit`** 정도만 기억하면 됩니다.
