# Initial-setup Roadmap

## 현재 목표: 0.12.x 안정화

새 기능을 빠르게 늘리기보다 다음을 우선합니다.

- Windows/macOS/Linux 반복 실행 안정성
- setup 재실행 시 idempotent 동작
- resume / rollback 신뢰성
- lock 및 conflict 진단 개선
- 문서와 실제 명령의 일치 유지

## rclone provider 전환 계획

`directory` backend는 사용하기 쉽지만, Initial-setup이 클라우드 클라이언트의 실제 서버 업로드 완료까지 확인할 수 없습니다.

장기 목표는 rclone backend를 충분히 검증한 뒤 기본 선택지로 승격하는 것입니다.

### Phase 1 — Probe

기존 `directory` backend를 유지한 채 rclone remote를 읽기 전용으로 검증합니다.

검증 항목:

- remote 연결/인증
- 읽기·쓰기 가능 여부
- 한글/공백 경로
- SHA-256 readback

### Phase 2 — Shadow sync

기존 directory sync를 source of truth로 유지하고 별도 rclone 테스트 경로에 동일 데이터를 복제합니다.

```text
directory source
    ├─ 기존 cloud mirror
    └─ rclone shadow store
```

두 저장소의 manifest/hash가 일치하는지 비교합니다.

### Phase 3 — Primary rclone

충분히 안정화되면 rclone을 primary provider로 사용합니다.

목표 흐름:

```text
dotpush
  → revision 생성
  → rclone upload
  → remote readback
  → hash 검증
  → HEAD 갱신
```

반드시 검증할 항목:

- 네트워크 중단 시 기존 HEAD 보존
- 업로드 중 프로세스 종료 복구
- PC A/B 동시 push 충돌 차단
- 오래된 baseline push 거부
- Windows/macOS/Linux 동일 동작
- rclone.conf / secret 평문 노출 방지

### Phase 4 — Directory fallback

최종 구조 목표:

```text
Primary   : rclone
Fallback  : directory
Optional  : local/NAS
```

`directory` backend는 삭제하지 않고 GUI cloud client를 선호하는 환경의 fallback으로 유지합니다.

## 1.0 기준

다음 조건이 반복해서 성공하면 1.0 후보로 봅니다.

1. 새 Windows/macOS/Linux 환경에서 bootstrap → setup 성공
2. 같은 PC에서 setup을 다시 실행해도 불필요한 변경 없음
3. 다른 PC의 private-source 변경을 안전하게 감지
4. 실패한 setup을 resume 또는 rollback 가능
5. secret/private key가 평문으로 유출되지 않음
6. `dotvalidate`와 `dottest --sandbox` 통과

그 전까지 0.12.x는 기능 추가보다 버그 수정과 안정화를 우선합니다.
