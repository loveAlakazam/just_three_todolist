`develop` 브랜치에 누적된 변경사항을 분석해 다음 릴리즈 버전(`vX.Y.Z`)을 결정하고, git-flow 규칙에 따라 **release 브랜치 생성 → release PR → `main` PR 머지 → (GitHub Actions 가 `vX.Y.Z` 태그 + GitHub Release 자동 생성) → `develop` back-merge** 까지 처리한다.

전체 규칙은 `.claude/rules/git-flow.md`, 자동화 설계는 `.claude/plans/deployment-plan.md` § "CI 자동화" 참조. 잘못된 릴리즈 복구는 **`/hotfix` 커맨드만 사용**한다 (revert 금지, 태그/릴리즈 삭제 금지).

## 절대 규칙 (이 커맨드가 지켜야 하는 것)

1. **`main` 직접 push 금지.** 모든 main 반영은 `gh pr merge` 를 통해 진행한다. 서버 측 branch protection + 로컬 pre-push hook 이 이중으로 차단한다.
2. **릴리즈 노트 없이 머지 금지.** §6 에서 릴리즈 노트 초안이 확정되기 전에는 `gh pr merge` 로 넘어가지 않는다. 릴리즈 노트는 **PR 본문에 게시**하며, GitHub Release 본문은 워크플로가 PR 본문을 그대로 재사용한다.
3. **force push / 태그 삭제 / 릴리즈 삭제 전면 금지.** 이미 찍힌 태그와 릴리즈 노트는 기록으로 보존한다.
4. **back-merge 생략 금지.** release 브랜치는 main 머지 후 반드시 develop 에도 머지한다.
5. **버전 판정은 반드시 사용자 확인.** 자동 판정 결과만 믿고 진행하지 않는다.
6. **태그·Release 는 워크플로 자동 생성에 위임.** 로컬/수동으로 `git tag` / `gh release create` 실행 금지. 실패 시 `workflow_dispatch` 로 재실행한다 (§8 복구 절차).
7. **PR 제목 형식은 `release: vX.Y.Z`.** 워크플로가 제목 prefix 로 릴리즈 PR 을 식별한다. 다른 형식이면 자동화가 발화되지 않는다.

## 사전 조건

- `gh` CLI 설치 및 인증 (`gh auth status`)
- 로컬 `main`, `develop` 브랜치가 원격과 최신 동기화 상태
- husky 훅 활성화 (`npm install` 한 번 실행 → `git config --get core.hooksPath` 가 `.husky/_`)
- 현재 작업 중인 feature 브랜치가 있다면 먼저 커밋/스태시 후 분리
- `develop` 이 `main` 보다 앞서 있어 릴리즈할 변경이 존재

## 절차

### 1. 상태 확인

1. `git fetch --all --tags --prune` — 원격 정보 최신화
2. `git branch --show-current` — 현재 브랜치 확인
3. `git status` — working tree clean 확인 (dirty 면 중단)
4. `git log --oneline main..develop` — `develop` 이 `main` 보다 앞서 있는지 확인. 없으면 릴리즈할 변경 없음 → 중단.

### 2. 마지막 릴리즈 태그 조회

```bash
git describe --tags --abbrev=0 2>/dev/null || echo "NO_TAG"
```

- 이전 태그가 있으면 `LAST_TAG` 로 기억.
- 없으면 **최초 릴리즈** 로 판단하고 `v1.0.0` 을 후보로 고정한다 (PR 내용과 무관하게 v1.0.0 으로 시작).
  - 최초 릴리즈는 버전 알고리즘 적용 대상이 아니다. §4 를 건너뛰고 §5 로 진행.
  - `pubspec.yaml` 의 `version` 이 `1.0.0+1` 인지 확인하고 일치하면 그대로 사용.

### 3. 릴리즈 대상 PR 수집

마지막 태그 이후 `develop` 에 머지된 PR 만 수집한다.

```bash
gh pr list --base develop --state merged --limit 50 \
  --json number,title,mergedAt,labels,body \
  --jq '.[] | select(.mergedAt != null)'
```

- 태그가 있으면 `git log LAST_TAG..develop --merges --oneline` 과 교차 검증.
- PR 이 전혀 없으면 커밋 기반 분석으로 fallback (`git log LAST_TAG..develop --oneline`).

### 4. 버전 증가 자리 결정 (`X.Y.Z`)

> ⚠️ **최초 릴리즈(태그 없음)** 는 이 단계를 건너뛴다. 버전은 `v1.0.0` 으로 고정. §2 참조.

**두 번째 릴리즈부터 적용**되는 버전 규칙 (일반 SemVer 와 정의 다름):

| 자리 | 의미 | 트리거 커밋 prefix |
|------|------|-------------------|
| **X** | Breaking 변경 & 앱 전면 개편 | `breaking:` 이 1개라도 포함 |
| **Y** | 기능 변경사항 반영 & 일부 서비스 UI 변경 | `feat:` 이 1개라도 포함 (breaking 없을 때) |
| **Z** | 버그 개선 & 리팩터링 | `fix:` / `refactor:` / `perf:` / `style:` / `ci:` 가 1개라도 포함 (breaking·feat 없을 때) |

#### 결정 알고리즘

```text
if   (breaking: 커밋 1개 이상)              → X += 1, Y = 0, Z = 0
elif (feat: 커밋 1개 이상)                  → Y += 1, Z = 0
elif (fix/refactor/perf/style/ci 1개 이상)  → Z += 1
else                                        → 릴리즈 불가 (릴리즈 조건 미충족 → 중단)
```

#### 릴리즈 불가 조건

`feat` / `fix` / `refactor` / `perf` / `style` / `ci` / `breaking` 커밋이 **단 하나도 없으면** 릴리즈를 진행하지 않는다. `chore` / `docs` / `test` / `remove` 만 있는 경우 해당.

- 판정된 후보 버전을 **반드시 사용자에게 제시하고 확인**한 뒤 진행한다.

### 5. 릴리즈 브랜치 생성 + 버전 bump

```bash
git checkout develop
git pull origin develop
git checkout -b release/vX.Y.Z
```

- `pubspec.yaml` 의 `version: X.Y.Z+build` 갱신.
- CHANGELOG 파일이 있다면 이 릴리즈 섹션 추가 (없으면 생성하지 않음).
- 변경 커밋:
  ```bash
  git add pubspec.yaml
  git commit -m "chore: vX.Y.Z 릴리즈 준비"
  git push -u origin release/vX.Y.Z
  ```

> 💡 `release/vX.Y.Z` 브랜치는 보호 브랜치가 아니므로 일반 push 가능하다.

### 6. 릴리즈 노트 작성 (필수 게이트)

**이 단계를 건너뛰고 §7 로 넘어가지 않는다.** 릴리즈 노트는 release PR 본문과 GitHub Release 양쪽에서 동일하게 사용되므로 한 번 작성해 둔다.

#### 템플릿

```markdown
## vX.Y.Z (YYYY-MM-DD)

### 개요

<이 릴리즈가 무엇을, 왜 담고 있는지 1~3줄 요약. "무엇"보다 "왜"에 집중>

### 신규 기능 (feat)
- #PR번호 — 한 줄 요약

### 변경 (refactor / style / perf)
- #PR번호 — 한 줄 요약

### 버그 픽스 (fix)
- #PR번호 — 한 줄 요약

### 기타 (chore / docs / ci / test)
- #PR번호 — 한 줄 요약

### 호환성 / 마이그레이션 영향

<사용자/개발자에게 영향 있는 변경 여부. 없으면 "해당 없음" 명시>
```

- 분류별 섹션 중 비어 있는 것은 제거한다.
- PR 번호/제목은 §3 에서 수집한 목록을 그대로 사용.
- 사용자에게 초안을 제시하고 확인받은 뒤 §7 로 진행한다.

### 7. `main` 으로 release PR 생성 + 머지

⚠️ **`main` 은 직접 push 가 금지되어 있다.** `gh pr merge` 의 merge commit 방식만 사용한다.

```bash
# 1) release PR 생성 (base = main, head = release/vX.Y.Z)
gh pr create \
  --base main \
  --head release/vX.Y.Z \
  --title "release: vX.Y.Z" \
  --body "$(cat <<'EOF'
<§6 에서 작성한 릴리즈 노트>
EOF
)"

# 2) PR 번호 확인
PR_NUMBER=$(gh pr view release/vX.Y.Z --json number --jq '.number')

# 3) PR 머지 (merge commit 방식 — no squash/rebase)
gh pr merge "$PR_NUMBER" --merge --delete-branch=false
```

- `--merge` 옵션으로 merge commit 을 생성한다 (히스토리에 "vX.Y.Z 릴리즈" 가 명확히 남음).
- `--delete-branch=false` 로 release 브랜치를 남겨둔다 (§9 back-merge 이후 일괄 정리).
- 머지가 실패하면 (충돌 등) 중단하고 사용자에게 알린다. 자동 resolve 금지.

### 8. GitHub Actions `release-publish` 워크플로 완료 확인

§7 PR 머지 직후 `pull_request_target: closed` 이벤트로 `.github/workflows/release-publish.yml` 이 자동 실행된다. **로컬에서 `git tag` / `gh release create` 를 직접 호출하지 않는다.**

워크플로가 수행하는 작업:
1. PR 제목에서 `vX.Y.Z` 추출 + 형식 검증
2. 머지 커밋 SHA 가 `origin/main` 의 조상인지 검증
3. PR 본문을 릴리즈 노트로 사용 (비어 있으면 실패)
4. annotated 태그 `vX.Y.Z` 생성 + push
5. `gh release create` 로 GitHub Release 공개 (idempotent)

#### 확인

```bash
# 최근 실행 결과 조회
gh run list --workflow=release-publish.yml --limit 3

# 진행 중이면 최신 실행을 watch
gh run watch

# 태그 / Release 공개 검증
git fetch --tags origin
git tag -l vX.Y.Z
gh release view vX.Y.Z --json url,name,publishedAt
```

- 워크플로 상태가 `completed / success` 여야 §9 back-merge 로 진행한다.
- 태그가 이미 존재하면 워크플로는 태그 생성을 스킵하고 Release 본문만 갱신한다 (재실행 안전).

#### 워크플로 실패 복구

실패 원인별 대응:

| 증상 | 원인 | 복구 |
|------|------|------|
| 워크플로가 아예 실행 안 됨 | PR 제목이 `release:` prefix 아님 / head 가 `release/*` 아님 | 제목/브랜치 수정 후 `workflow_dispatch` 수동 실행 |
| 버전 추출 실패 | PR 제목에 `vX.Y.Z` 없음 | 제목 정정 후 `workflow_dispatch` 재실행 |
| PR 본문 비어 있음 → 릴리즈 노트 게이트 실패 | §6 누락 | PR 본문에 릴리즈 노트 추가 → `workflow_dispatch` 재실행 |
| 네트워크 / API 일시 실패 | GitHub Actions 측 이슈 | 동일 입력으로 `workflow_dispatch` 재실행 |

수동 재실행:

```bash
gh workflow run release-publish.yml \
  -f version=vX.Y.Z \
  -f sha=<머지 커밋 SHA> \
  -f pr_number=<릴리즈 PR 번호>
```

> ⚠️ 워크플로 실패를 우회해 로컬에서 `git tag -a && git push origin vX.Y.Z` 를 직접 실행하는 것은 **금지**. 반드시 `workflow_dispatch` 로 재시도한다.

### 9. `develop` 으로 back-merge

릴리즈 브랜치의 버전 bump 커밋이 `develop` 에도 반영되어야 한다. develop 은 PR 필수가 아니므로 로컬 머지 후 push.

```bash
git checkout develop
git pull origin develop
git merge --no-ff release/vX.Y.Z -m "chore: vX.Y.Z 릴리즈 내용 develop 동기화"
git push origin develop
```

- `--no-ff` 로 머지 커밋을 남겨 "vX.Y.Z 릴리즈 반영" 이 히스토리에 명확히 보이게 한다.
- pre-push hook 은 develop 의 FF/non-FF 만 검사한다. 일반 merge push 는 통과한다.

### 10. release 브랜치 정리

```bash
git branch -d release/vX.Y.Z
git push origin --delete release/vX.Y.Z
```

### 11. 결과 보고

- 생성된 태그 (`vX.Y.Z`)
- GitHub Release URL (`gh release view vX.Y.Z --json url --jq .url`)
- release PR URL + 머지 SHA
- 포함된 PR 개수 / 분류
- develop back-merge 완료 여부
- 다음 릴리즈를 위해 develop 에 남아 있는 작업이 있으면 언급

## 금지 사항 (재확인)

- `git push origin main` 직접 호출 금지 (서버 + hook 차단)
- `git merge release/* ` 후 `git push main` 금지 — 반드시 `gh pr merge` 경유
- `git tag -d` / `git push --delete origin vX.Y.Z` / `gh release delete` 금지
- 릴리즈 노트 없는 태그 push 금지
- back-merge 생략 금지
- `--hard` 리셋 금지 (`.claude/rules/git-commit.md`)
- 잘못된 릴리즈를 revert 커밋으로 롤백 금지 — **`/hotfix` 커맨드 사용**

## 실패 / 복구

- **§7 PR 머지 충돌**: `gh pr merge` 실패 → release 브랜치에서 `git merge origin/main` 으로 충돌 해결 → 재시도. 충돌 해결 커밋도 PR 에 포함.
- **§8 태그 push 실패**: 네트워크/권한 문제. 재시도. 태그가 이미 존재한다고 하면 로컬/원격 태그가 일치하는지 확인. 일치하면 OK.
- **§9 back-merge 충돌**: develop 의 새 커밋과 release 브랜치 변경이 충돌 → develop 에서 충돌 해결 후 머지. 여기서도 force push 절대 금지.
- **릴리즈 이후 버그 발견**: 이 커맨드로 복구하지 않는다. `/hotfix vX.Y.(Z+1)` 사용.
