# Just Three 배포 계획

## 배포 환경 구조

| 환경 | 브랜치 | 역할 |
|------|--------|------|
| **개발** | `feature/*` | 기능 단위 개발 |
| **스테이징 (베타)** | `develop` | 개발 완료 후 통합 테스트 · 베타 검증 |
| **프로덕션** | `main` | 릴리즈 태그(`vX.Y.Z`)가 찍히는 배포 기준 브랜치 |

```
feature/* ──PR──► develop (베타) ──/release──► main (프로덕션, vX.Y.Z)
                                               ▲
                         main ──/hotfix──► main (긴급 패치, vX.Y.(Z+1))
```

---

## 버전 태그 규칙 (`vX.Y.Z`)

> 일반 SemVer 와 정의가 다르므로 주의.

### 최초 릴리즈

- PR 내용·커밋 prefix 에 상관없이 **`v1.0.0` 으로 고정**.
- `pubspec.yaml` 초기값: `1.0.0+1`.

### 두 번째 릴리즈부터 (PR 알고리즘 적용)

| 자리 | 의미 | 트리거 커밋 prefix |
|------|------|-------------------|
| **X** | Breaking 변경 & 앱 전면 개편 | `breaking:` 이 1개라도 포함 |
| **Y** | 기능 변경사항 반영 & 일부 서비스 UI 변경 | `feat:` 이 1개라도 포함 (breaking 없을 때) |
| **Z** | 버그 개선 & 리팩터링 | `fix:` / `refactor:` / `perf:` / `style:` / `ci:` 가 1개라도 포함 (breaking·feat 없을 때) |

### 결정 알고리즘

```text
if   (breaking: 커밋 1개 이상)              → X += 1, Y = 0, Z = 0
elif (feat: 커밋 1개 이상)                  → Y += 1, Z = 0
elif (fix/refactor/perf/style/ci 1개 이상)  → Z += 1
else                                        → 릴리즈 불가 (중단)
```

### 릴리즈 불가 조건

`feat` / `fix` / `refactor` / `perf` / `style` / `ci` / `breaking` 이 **단 하나도 없으면** 릴리즈 진행 불가. `chore` / `docs` / `test` / `remove` 만 있는 경우 해당.

### 버전 예시

| 현재 버전 | 포함 커밋 | 다음 버전 |
|-----------|----------|-----------|
| `v1.0.0` | `feat:` 포함 | `v1.1.0` |
| `v1.0.0` | `fix:` 만 포함 | `v1.0.1` |
| `v1.0.0` | `breaking:` 포함 | `v2.0.0` |
| `v1.1.0` | `feat:` 포함 | `v1.2.0` |
| `v1.1.0` | `fix:` 만 포함 | `v1.1.1` |

---

## 배포 전 게이트 (develop → main)

main 배포를 진행하기 전 아래 항목을 모두 확인한다.

- [ ] `develop` 이 `main` 보다 앞서 있음 (`git log --oneline main..develop` 결과 존재)
- [ ] `develop` 에서 베타 테스트 완료 (크래시·치명적 버그 없음)
- [ ] 릴리즈 가능한 커밋 prefix 가 1개 이상 존재 (`feat`/`fix`/`refactor`/`perf`/`style`/`ci`/`breaking`)
- [ ] `gh` CLI 인증 완료 (`gh auth status`)
- [ ] 로컬 `main`, `develop` 최신 동기화 (`git pull`)
- [ ] husky 훅 활성 (`git config --get core.hooksPath` → `.husky/_`)
- [ ] 릴리즈 노트 초안 작성 완료 (머지 전 필수)

---

## 정규 배포 플로우 (`/release`)

```
1. git fetch --all --tags --prune
2. 마지막 태그 이후 develop 에 머지된 PR 목록 수집
3. 버전 자리 판정 (최초 = v1.0.0 고정, 이후 = 알고리즘) → 사용자 확인
4. git checkout -b release/vX.Y.Z (from develop)
5. pubspec.yaml version bump + 커밋
6. 릴리즈 노트 작성 (필수 게이트 — 확정 전 §7 진행 불가)
7. gh pr create --base main --head release/vX.Y.Z
8. gh pr merge <PR_NUMBER> --merge --delete-branch=false
   ↓ (이 시점 GitHub Actions `release-publish` 가 자동 트리거)
9. 워크플로 완료 확인 — 태그 vX.Y.Z + GitHub Release 자동 생성 검증
10. git checkout develop && git pull && git merge --no-ff release/vX.Y.Z
11. release/vX.Y.Z 브랜치 삭제
```

상세 절차: `.claude/commands/release.md`
트리거: `/release` 슬래시 커맨드
자동화: `.github/workflows/release-publish.yml` (§ "CI 자동화" 참조)

---

## 긴급 패치 플로우 (`/hotfix`)

프로덕션(`main`) 버그를 즉시 수정해야 할 때 사용. **forward-fix 만 허용.**

```
1. git checkout main && git pull
2. git checkout -b hotfix/vX.Y.(Z+1)
3. 버그 수정 커밋 (fix: 또는 revert: 접두어)
4. gh pr create --base main --head hotfix/vX.Y.(Z+1)
5. gh pr merge --merge
   ↓ (이 시점 GitHub Actions `release-publish` 가 자동 트리거)
6. 워크플로 완료 확인 — 패치 태그 vX.Y.(Z+1) + GitHub Release 자동 생성 검증
7. develop 으로 back-merge (동일 버그 재발 방지)
8. hotfix 브랜치 삭제
```

상세 절차: `.claude/commands/hotfix.md`
트리거: `/hotfix` 슬래시 커맨드
자동화: `.github/workflows/release-publish.yml` (§ "CI 자동화" 참조)

---

## CI 자동화 (`.github/workflows/release-publish.yml`)

태그 생성과 GitHub Release 공개를 수동 단계에서 분리해, PR 머지 이벤트에 맞춰 GitHub Actions 가 대신 수행한다. 사람/에이전트의 단계 누락(이번 v1.0.0 처럼 태그·Release 누락)을 구조적으로 막기 위함이다.

### 트리거

| 이벤트 | 실행 조건 |
|--------|----------|
| `pull_request_target` (closed, base=main) | `merged == true` **AND** PR 제목이 `release:` 또는 `hotfix:` 로 시작 |
| `workflow_dispatch` | 수동 입력 (version / sha / pr_number) — 소급 태깅 · 실패 복구 용도 |

> ⚠️ release/* 브랜치에서 올라온 **비릴리즈 PR** (예: `ci:`, `docs:` 로 시작)은 필터에 걸려 실행되지 않는다. "릴리즈 PR" 임을 제목 prefix 로 구분한다.

### 작업 순서

1. `main` 체크아웃 (`fetch-depth: 0`)
2. 메타 추출
   - PR 제목에서 `vX.Y.Z` 정규식 매칭 → `VERSION`
   - 머지 커밋 SHA = `pull_request.merge_commit_sha`
   - PR 번호 = `pull_request.number`
3. 게이트
   - 버전 형식 검증 (`^v[0-9]+\.[0-9]+\.[0-9]+$`)
   - SHA 가 `origin/main` 의 조상인지 `git merge-base --is-ancestor` 로 검증
   - PR 본문 비어 있으면 실패 (릴리즈 노트 필수)
   - 동일 태그 이미 존재 → 태그 생성은 스킵, Release 본문만 갱신 (idempotent)
4. annotated 태그 생성 + push (`git tag -a $VERSION $SHA`)
5. `gh release create` (이미 있으면 `gh release edit` 로 본문 갱신)
6. Summary 출력 (버전 / SHA / 트리거 / PR)

### 안전 장치

- `permissions: contents: write, pull-requests: read` — 최소 권한만 부여
- 태그·Release 양쪽 idempotent → 재실행 가능
- 실패 시 커맨드 fallback: `.claude/commands/release.md` §8 "워크플로 실패 복구" 절 참조
- **태그 삭제 / Release 삭제는 절대 금지** (워크플로도 이 동작은 수행하지 않음)

### 소급 적용 · 재실행 방법

이미 머지됐지만 태그·Release 가 없는 릴리즈(예: v1.0.0) 또는 워크플로 실패 시:

```bash
gh workflow run release-publish.yml \
  -f version=v1.0.0 \
  -f sha=<머지 커밋 SHA> \
  -f pr_number=<릴리즈 PR 번호>
```

실행 결과는 `gh run list --workflow=release-publish.yml --limit 1` 로 확인.

---

## 이전 릴리즈 롤백 정책

> 핵심 원칙: **태그는 이전 버전으로 되돌릴 수 없다.** 태그는 특정 커밋에 고정된 immutable 포인터이므로 수정·삭제 불가.

### 롤백 = 새 버전으로 "되돌리기" (forward-fix)

이전 버전의 상태로 돌아가려면 `hotfix` 브랜치에서 `git revert` 를 사용해 나쁜 변경을 취소하는 새 버전을 만든다.

```
v1.1.0 배포 후 문제 발견 → hotfix/v1.1.1 분기 → git revert <bad-commit> → v1.1.1 배포
```

- ✅ 허용: `hotfix/*` 브랜치 내에서 `git revert <커밋>` 후 PR → 새 버전 태그
- ❌ 금지: `main` / `develop` 에서 직접 `git revert` 후 push
- ❌ 금지: 기존 태그(`v1.1.0`) 삭제 후 이전 커밋에 재태깅
- ❌ 금지: force push 로 main 히스토리 되돌리기

---

## 릴리즈 노트 필수 규칙

**릴리즈 노트 없이 main 에 머지하는 것은 금지.**

### 템플릿

```markdown
## vX.Y.Z (YYYY-MM-DD)

### 개요
<이 릴리즈가 무엇을, 왜 담고 있는지 1~3줄 요약>

### 신규 기능 (feat)
- #PR번호 — 한 줄 요약

### 변경 (style / refactor / perf)
- #PR번호 — 한 줄 요약

### 버그 픽스 (fix)
- #PR번호 — 한 줄 요약

### 기타 (chore / docs / ci / test)
- #PR번호 — 한 줄 요약

### 호환성 / 마이그레이션 영향
<영향 없으면 "해당 없음" 명시>
```

- 비어 있는 분류 섹션은 제거한다.
- PR 목록은 마지막 태그 이후 `develop` 에 머지된 것만 포함.
- GitHub Release (`gh release create`) 에 반드시 공개.

---

## 보호 규칙 (불변)

| 행위 | main | develop |
|------|------|---------|
| 직접 push | ❌ PR 필수 | ✅ FF 머지만 |
| Force push | ❌ | ❌ |
| 브랜치 삭제 | ❌ | ❌ |
| Admin 우회 | ❌ (`enforce_admins: true`) | ❌ |

- `main` 직접 push → GitHub Branch Protection + `.husky/pre-push` 이중 차단
- 잘못된 릴리즈 복구 → **`/hotfix` 만 허용** (태그 삭제 / force push 전면 금지)

---

## Claude Code 에이전트 규칙

릴리즈 관련 작업 시 Claude Code 가 반드시 따르는 규칙.

### `/release` 실행 시

1. **최초 릴리즈(태그 없음)는 v1.0.0 고정** — 알고리즘 적용 없이 v1.0.0.
2. **릴리즈 가능 커밋 없으면 중단** — `feat`/`fix`/`refactor`/`perf`/`style`/`ci`/`breaking` 0개이면 릴리즈 불가.
3. **버전 판정 후 사용자 확인 필수** — 자동 판정 결과만 믿고 진행 금지.
4. **릴리즈 노트 초안 확정 전 main 머지 금지** — 사용자 승인 후 `gh pr merge`.
5. **`git push origin main` 직접 호출 금지** — 항상 `gh pr merge` 경유.
6. **back-merge 생략 금지** — release 브랜치를 develop 에도 반드시 반영.
7. **태그·GitHub Release 는 워크플로가 자동 생성** — 머지 이후 `gh run list --workflow=release-publish.yml` 로 성공 확인. 실패 시 `workflow_dispatch` 로 재실행 (태그/Release 직접 생성 금지).
8. **PR 제목은 반드시 `release: vX.Y.Z` 형식** — 제목 prefix 로 워크플로가 릴리즈 PR 을 식별한다.

### `/hotfix` 실행 시

1. **`main` 에서만 분기** — `hotfix/vX.Y.(Z+1)` 는 반드시 `main` 기준.
2. **hotfix 브랜치 내 `git revert` 허용** — 원인 제거 커밋 또는 `git revert` 모두 가능.
3. **main / develop 에서 직접 `git revert` 금지** — 반드시 hotfix 브랜치 경유.
4. **develop back-merge 필수** — 핫픽스 내용이 다음 릴리즈에도 반영되어야 함.
5. **릴리즈 노트 간단해도 반드시 PR 본문에 작성** — 워크플로가 PR 본문을 Release 노트로 사용한다. 본문이 비면 워크플로가 실패 처리.
6. **PR 제목은 반드시 `hotfix: vX.Y.(Z+1) ...` 형식** — 워크플로 식별 조건.

### 공통

- `--no-verify` 로 husky 훅 우회 금지.
- `git reset --hard` 금지 (`--soft` 만 허용).
- 이미 push 된 태그 삭제 금지.
- 이미 공개된 GitHub Release 삭제 금지.
- 머지 충돌 발생 시 자동 resolve 금지 — 사용자에게 알리고 중단.
