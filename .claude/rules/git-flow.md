# Git Flow 규칙

Just Three 앱의 브랜치 전략은 [git-flow](https://danielkummer.github.io/git-flow-cheatsheet/index.html)를 따른다. 기능 추가/수정/신규 기능 작업 시 아래 규칙을 반드시 준수한다.

## 브랜치 구조

| 브랜치 | 역할 | 비고 |
|--------|------|------|
| `main` | 배포(릴리즈) 기준 브랜치 | 릴리즈 태그(`vX.Y.Z`)가 찍히는 브랜치. **직접 커밋/푸시 금지** — PR 경유 필수. |
| `develop` | 통합 개발 브랜치 | 다음 릴리즈에 포함될 기능들이 모이는 브랜치. feature PR 의 base. |
| `feature/*` | 기능 개발 브랜치 | `develop`에서 분기 → 작업 완료 시 `develop`으로 PR. |
| `release/*` | 릴리즈 준비 브랜치 | `develop`에서 분기 → 최종 QA 후 `main` 으로 PR + `develop` back-merge. |
| `hotfix/*` | 긴급 버그픽스 브랜치 | **`main`에서 분기** → `main` 으로 PR + `develop` back-merge. |

---

## 브랜치 보호 규칙 (불변)

`main` 과 `develop` 은 "보호 브랜치" 다. 다음 행위는 **서버(GitHub) + 로컬(pre-push hook) 양쪽에서 차단**된다.

| 행위 | main | develop | 비고 |
|------|------|---------|------|
| 브랜치 삭제 | ❌ 금지 | ❌ 금지 | 서버: `allow_deletions: false` / 로컬: `.husky/pre-push` |
| Force push / non-fast-forward push | ❌ 금지 | ❌ 금지 | 서버: `allow_force_pushes: false` / 로컬: `.husky/pre-push` |
| 직접 push (PR 경유 아님) | ❌ 금지 | ✅ 허용 (FF 머지만) | main 은 required PR 로 차단. 로컬 `.husky/pre-push` 도 main 직접 push 차단. |
| **`main` 에서 직접 커밋** | ❌ 금지 | — | 로컬 `.husky/pre-commit` 이 차단 (stage + commit 시점) |
| Admin 계정의 규칙 우회 | ❌ 불가 | ❌ 불가 | `enforce_admins: true` |

### GitHub 서버 측 Branch Protection

현재 적용된 설정 (`gh api` 기준):

**`main`**
```json
{
  "enforce_admins": true,
  "allow_force_pushes": false,
  "allow_deletions": false,
  "required_pull_request_reviews": {
    "required_approving_review_count": 0
  }
}
```

**`develop`**
```json
{
  "enforce_admins": true,
  "allow_force_pushes": false,
  "allow_deletions": false
}
```

> 규칙 변경이 필요하면 `gh api -X PUT repos/<owner>/<repo>/branches/<branch>/protection --input -` 로 수정. 단, main 의 "PR 필수 + admin enforce" 는 이 프로젝트의 **불변 규칙**이므로 해제 금지.

### 로컬 git hook (Husky)

서버 측과 동일한 규칙을 클라이언트에서도 방어한다 (빠른 피드백 + 서버 요청 이전 차단). **Claude Code 뿐 아니라 사람이 터미널에서 직접 커밋/푸시할 때도 동일하게 적용**되도록 [husky](https://typicode.github.io/husky/) v9 로 관리한다.

| 훅 | 파일 | 역할 |
|----|------|------|
| `pre-commit` | `.husky/pre-commit` | `main` 브랜치에서의 직접 커밋을 차단 (stage 완료 후 `git commit` 시점) |
| `commit-msg` | `.husky/commit-msg` | 커밋 메시지가 `prefix: 메시지` 형식을 따르는지 검증 (`.claude/rules/git-commit.md`) |
| `pre-push` | `.husky/pre-push` | `main` / `develop` 삭제 · force push · non-FF push 차단 + `main` 직접 push 차단 |

- 활성화: 저장소를 clone 한 직후 **npm install 한 번** 실행하면 된다. `package.json` 의 `prepare` 스크립트가 `husky` 를 호출해 `core.hooksPath` 를 `.husky/_` 로 자동 설정한다.
  ```bash
  npm install
  git config --get core.hooksPath   # .husky/_  가 출력되면 활성
  ```
- 검사 항목 (pre-push):
  1. `main` / `develop` 브랜치 삭제 시도 → 차단
  2. `main` / `develop` 로의 force push / non-FF push → 차단
  3. `main` 직접 push → 차단 (릴리즈는 `/release`, 긴급 패치는 `/hotfix` 의 PR 머지 경유만 허용)
- 검사 항목 (pre-commit):
  1. `git symbolic-ref --short HEAD` 가 `main` 이면 커밋 차단

> hook 은 로컬 안전망이다. 다른 기기에서 clone 했을 때도 `npm install` 을 건너뛰면 hook 이 비활성이지만, 서버 측 보호가 여전히 차단하므로 안전하다. `--no-verify` 로 hook 을 우회하는 것은 규칙 위반이다 (PR 리뷰에서 걸러질 수 있으며, 서버 측 보호까지 우회되지는 않는다).

---

## Feature 브랜치 작업 규칙

1. **분기 시점**: feature 단위 작업은 **반드시 `develop` 브랜치에서 생성**한다.
   ```bash
   git checkout develop
   git pull origin develop
   git checkout -b feature/<이름>
   ```
2. **작업 범위**: 해당 feature 에 속하는 변경만 커밋한다. 다른 feature 의 파일을 건드려야 한다면 별도 브랜치에서 처리한다.
3. **작업 중 동기화**: 장기간 작업 시 `git fetch origin develop && git merge origin/develop` 로 주기적으로 최신 `develop` 을 반영한다. (rebase 는 공유 브랜치에서는 금지)
4. **PR base 브랜치**: feature 브랜치의 PR 은 **항상 `develop` 을 base 로** 생성한다. `main` 을 base 로 하는 feature PR 은 금지.
5. **머지 이후**: PR 머지 후 원격/로컬 feature 브랜치는 삭제한다 (보호 브랜치가 아니므로 가능).

---

## 릴리즈 규칙

릴리즈는 `develop` 에 누적된 PR 들을 바탕으로 수행하며, **반드시 `/release` 슬래시 커맨드로** 트리거한다. 수동으로 `git merge` / `git tag` / `git push origin main` 하는 것은 금지다 (서버/hook 이 차단).

### 버전 태그: `vX.Y.Z`

- **최초 릴리즈**: PR 내용과 무관하게 `v1.0.0` 고정. `pubspec.yaml` 초기값 `1.0.0+1`.
- **두 번째 릴리즈부터**: 아래 알고리즘으로 버전 자리를 결정.

| 자리 | 의미 | 트리거 커밋 prefix |
|------|------|-------------------|
| **X** | Breaking 변경 & 앱 전면 개편 | `breaking:` 이 1개라도 포함 |
| **Y** | 기능 변경사항 반영 & 일부 서비스 UI 변경 | `feat:` 이 1개라도 포함 (breaking 없을 때) |
| **Z** | 버그 개선 & 리팩터링 | `fix:` / `refactor:` / `perf:` / `style:` / `ci:` 가 1개라도 포함 (breaking·feat 없을 때) |

> ⚠️ `feat`/`fix`/`refactor`/`perf`/`style`/`ci`/`breaking` 이 단 하나도 없으면 릴리즈 불가 (`chore`/`docs`/`test`/`remove` 만 있는 경우).  
> ⚠️ 본 프로젝트의 `X.Y.Z` 정의는 일반 SemVer 와 다르다. **X = breaking·앱개편 / Y = 기능변경·UI변경 / Z = 버그·리팩터링** 으로 해석한다.

### 릴리즈 플로우 (요약)

1. `develop` 에 반영된 PR 목록 확인 (마지막 태그 이후).
2. PR 분류 → `X` / `Y` / `Z` 중 어느 자리를 올릴지 판정 후 **사용자 확인**.
3. `release/vX.Y.Z` 브랜치를 `develop` 에서 분기.
4. 버전 bump / 메타 업데이트.
5. **릴리즈 노트 작성** (아래 "릴리즈 노트 필수 규칙" 절 참조).
6. `release/vX.Y.Z` → `main` 으로 **PR 생성 + `gh pr merge --merge`** (직접 merge/push 금지).
7. 머지 완료 후 main 최신 커밋에 `vX.Y.Z` annotated 태그 생성 + push.
8. `gh release create vX.Y.Z` 로 GitHub Release 생성 (릴리즈 노트 본문 반드시 포함).
9. `release/vX.Y.Z` 를 `develop` 으로도 back-merge (버전 정보 동기화).
10. `release/vX.Y.Z` 브랜치 삭제.

상세 절차는 `.claude/commands/release.md` 참조.

### 릴리즈 노트 필수 규칙

**`main` 에 배포(머지)할 때는 반드시 릴리즈 노트를 작성한다.** 릴리즈 노트 없는 릴리즈는 금지.

- 작성 시점: release PR 을 main 에 머지하기 **전**에 본문/GitHub Release 로 준비.
- 게이트: `/release` 커맨드는 릴리즈 노트 초안이 확정되기 전에는 main 머지로 넘어가지 않는다.
- 필수 항목:
  - 버전 (`vX.Y.Z`) 과 릴리즈 날짜 (YYYY-MM-DD)
  - 변경 분류별 PR 목록 (신규 기능 / 변경 / 버그 픽스 / 기타)
  - 사용자 영향(호환성, 마이그레이션 필요 여부) — 해당 없으면 "해당 없음" 명시
- 공개: `gh release create vX.Y.Z --notes "..."` 로 GitHub Release 에 반드시 공개한다. 태그만 찍고 릴리즈를 만들지 않는 것은 금지.

---

## Hotfix 규칙 (긴급 버그픽스)

프로덕션(`main`) 에 나간 버그를 긴급 수정해야 할 때 사용한다. **`/hotfix` 커맨드로 트리거**하는 것이 표준이며, 수동 절차도 아래와 동일하다.

### 언제 쓰는가

- `main` 에 이미 배포된 버전(`vX.Y.Z`) 에서 버그가 발견되었고,
- `develop` 에는 다음 릴리즈용 새 기능이 이미 쌓여 있어 일반 릴리즈 플로우로 밀 수 없을 때.

### 플로우 (forward-fix only)

1. `main` 에서 `hotfix/vX.Y.(Z+1)` 브랜치 분기
   ```bash
   git checkout main
   git pull origin main
   git checkout -b hotfix/vX.Y.(Z+1)
   ```
2. 버그 수정 커밋 (feature 브랜치와 동일하게 prefix 규칙 준수: `fix: ...`).
3. `hotfix/vX.Y.(Z+1)` → `main` 으로 **PR 생성 + `gh pr merge --merge`**.
4. 머지된 main 최신 커밋에 `vX.Y.(Z+1)` 태그 생성 + push.
5. `gh release create vX.Y.(Z+1)` 로 **hotfix 릴리즈 노트** 공개 (간단해도 반드시 생성).
6. 동일 변경을 **`develop` 으로도 반드시 back-merge** 한다 (다음 릴리즈에서 같은 버그가 재발하지 않게).
   ```bash
   git checkout develop
   git pull origin develop
   git merge --no-ff hotfix/vX.Y.(Z+1) -m "chore: hotfix vX.Y.(Z+1) develop 동기화"
   git push origin develop
   ```
7. `hotfix/vX.Y.(Z+1)` 브랜치 삭제.

상세 절차는 `.claude/commands/hotfix.md` 참조.

---

## 잘못된 릴리즈 복구 전략

**원칙: Forward-fix 만 사용한다.** 이미 `main` 에 머지된 릴리즈에 문제가 있더라도 히스토리를 되돌리거나 삭제하지 않는다. 다음 패치 버전으로 고친다.

### ✅ 허용 — Forward-fix (`/hotfix`)

- `main` 에서 `hotfix/*` 분기 → 수정 → `main` PR 머지 → 패치 태그 → `develop` back-merge.
- 잘못된 릴리즈의 태그/릴리즈 노트는 **그대로 보존**된다. "어떤 일이 있었는지" 추적 가능.
- 사용자는 깨진 버전을 잠시 보지만, 다음 패치 릴리즈로 신속히 복구한다.
- 이 프로젝트의 유일한 공식 복구 방법.

### ❌ 금지 — Revert 커밋으로 롤백

- `git revert <머지커밋>` 후 재배포 방식은 **금지**한다.
- 이유: revert 된 변경을 나중에 다시 적용하려 할 때 cherry-pick 이 꼬이고, develop 에 revert 를 동기화하지 않으면 다음 릴리즈에서 같은 문제가 재발한다.
- 긴급하더라도 hotfix 플로우로 원인을 제거하는 방식이 항상 더 안전하다.

### ❌ 금지 — 태그/릴리즈 삭제

- `git tag -d` / `git push --delete origin vX.Y.Z` / `gh release delete` 모두 **금지**한다.
- 이유:
  - 이미 `git fetch --tags` 한 다른 기기/CI 에 태그가 남아 있어 히스토리가 어긋남.
  - GitHub Release 는 공개된 순간 캐시/인덱스에 남을 수 있음.
  - main 머지 커밋 자체를 지우려면 force push 가 필요 → git-flow 및 보호 규칙 위반.
- 잘못된 태그조차 "그때 이런 릴리즈가 있었고, vX.Y.(Z+1) 에서 고쳤다" 는 기록으로 남긴다.

### ❌ 금지 — main / develop force push · 삭제

- 서버/로컬 hook 양쪽에서 차단된다. 우회 시도 금지.

---

## 금지 사항 (총정리)

| 금지 항목 | 차단 방식 |
|-----------|----------|
| `main` 직접 커밋/푸시 | GitHub required PR + local pre-push hook |
| `main` / `develop` force push · non-FF push | GitHub `allow_force_pushes: false` + local hook |
| `main` / `develop` 브랜치 삭제 | GitHub `allow_deletions: false` + local hook |
| Admin 우회 | `enforce_admins: true` |
| feature 브랜치를 `main` 기준으로 분기 / PR base 를 `main` 으로 설정 | 규칙 문서 + `/pull-request` 기본값 `develop` |
| 릴리즈 태그를 `develop` / feature / hotfix 브랜치에 찍는 것 | 규칙 문서 (`/release`, `/hotfix` 가 main 머지 커밋에만 태그) |
| 릴리즈 후 back-merge 생략 | `/release`, `/hotfix` 커맨드가 back-merge 까지 포함 |
| 잘못된 릴리즈를 revert 커밋으로 롤백 | 규칙 문서 (forward-fix 만 허용) |
| 릴리즈 태그 / GitHub Release 삭제 | 규칙 문서 |
| 릴리즈 노트 없이 `main` 에 배포 | `/release` 커맨드가 필수 게이트로 차단 |

---

## 새 기기 / 새 저장소 clone 시 초기 설정

```bash
git clone <repo-url>
cd just_three_todolist
npm install               # husky prepare 가 core.hooksPath 자동 설정
```

hook 활성화 여부는 `git config --get core.hooksPath` 로 확인할 수 있다 (`.husky/_` 가 출력되면 활성). husky 소스는 `.husky/pre-commit`, `.husky/commit-msg`, `.husky/pre-push` 세 개다.

### `--no-verify` 사용 금지

- `git commit --no-verify` / `git push --no-verify` 로 husky 훅을 우회하는 것은 **git-flow 규칙 위반**이다.
- 훅이 막는 상황이 발생하면 "훅이 틀렸다" 가 아니라 "작업 브랜치가 틀렸다" 로 먼저 의심한다.
- 정말로 훅 로직 자체가 잘못된 경우에만 훅 파일을 수정해 커밋으로 남긴다. 일회성 우회 금지.
