`main` 에 이미 배포된 릴리즈(`vX.Y.Z`)에서 버그가 발견되었을 때, **forward-fix** 방식으로 긴급 패치를 배포한다. `develop` 에는 다음 릴리즈용 기능이 이미 쌓여 있어 일반 `/release` 플로우로 밀 수 없는 상황을 가정한다.

> **이 프로젝트의 유일한 공식 릴리즈 복구 방법이다.** revert 커밋 / 태그 삭제 / 릴리즈 삭제 / force push 는 전면 금지 (`.claude/rules/git-flow.md` §"잘못된 릴리즈 복구 전략" 참조).

## 절대 규칙

1. **`main` 에서 분기**한다. `develop` 에서 분기 금지 (develop 의 미출시 기능이 섞이면 안 됨).
2. **`main` 머지는 PR 경유 (`gh pr merge`)**. 직접 push 금지.
3. **반드시 `develop` 에도 back-merge** 한다. 생략 시 다음 릴리즈에서 같은 버그 재발.
4. **패치 태그(`vX.Y.(Z+1)`) + GitHub Release** 는 필수. 릴리즈 노트는 간단해도 반드시 작성.
5. **force push / 태그 삭제 / 릴리즈 삭제 금지.** 이전 릴리즈 `vX.Y.Z` 의 태그와 릴리즈 노트는 그대로 보존한다 ("어떤 일이 있었고, 어떻게 고쳤는지" 추적 가능하게).

## 사전 조건

- `gh` CLI 인증 완료
- 로컬 `main` / `develop` 최신 동기화
- husky 훅 활성화 (`npm install` 한 번 실행 → `.husky/pre-commit`, `.husky/pre-push` 가 동작)
- 수정하려는 버그의 재현 케이스가 파악되어 있음

## 절차

### 1. 상태 확인

```bash
git fetch --all --tags --prune
git status                              # clean 확인
git describe --tags --abbrev=0          # 현재 배포된 최신 태그 확인 → LAST_TAG
```

- 예: `LAST_TAG=v1.2.0` 이면 hotfix 는 `v1.2.1` 이 된다.
- 이미 `LAST_TAG` 가 hotfix 기반이면 다시 Z+1 (예: `v1.2.1` → `v1.2.2`).

### 2. hotfix 브랜치 생성

`main` 에서 분기한다.

```bash
git checkout main
git pull origin main
git checkout -b hotfix/vX.Y.(Z+1)
git push -u origin hotfix/vX.Y.(Z+1)
```

> 💡 `hotfix/*` 브랜치는 보호 브랜치가 아니므로 직접 push 가능하다.

### 3. 버그 수정 + 커밋

- 원인 분석 → 수정 커밋.
- 커밋 메시지는 `fix:` prefix 사용 (`.claude/rules/git-commit.md`).
- 가능하면 회귀 테스트도 함께 추가 (같은 버그가 다시 생기지 않게).
- `pubspec.yaml` 의 `version` 을 `X.Y.(Z+1)` 로 bump.

```bash
git add <수정 파일>
git add pubspec.yaml
git commit -m "fix: <버그 요약>"
git push origin hotfix/vX.Y.(Z+1)
```

### 4. hotfix 릴리즈 노트 작성 (필수)

아래 템플릿을 사용해 hotfix 릴리즈 노트를 준비한다. release PR 본문 + GitHub Release 양쪽에 동일하게 사용.

```markdown
## vX.Y.(Z+1) — Hotfix (YYYY-MM-DD)

### 개요

`vX.Y.Z` 에서 발견된 <버그 요약> 을 수정하는 긴급 패치 릴리즈.

### 버그 픽스 (fix)

- #PR번호 — <수정 내용 한 줄 요약 + 영향 범위>

### 영향 범위

- 영향을 받은 사용자 / 기능: <설명>
- 업데이트 후 사용자가 해야 할 조치: <있으면 기재, 없으면 "없음">
```

### 5. `main` 으로 hotfix PR 생성 + 머지

⚠️ `main` 직접 push 금지. `gh pr merge` 경유.

```bash
gh pr create \
  --base main \
  --head hotfix/vX.Y.(Z+1) \
  --title "hotfix: vX.Y.(Z+1) <버그 요약>" \
  --body "$(cat <<'EOF'
<§4 에서 작성한 hotfix 릴리즈 노트>
EOF
)"

PR_NUMBER=$(gh pr view hotfix/vX.Y.(Z+1) --json number --jq '.number')

gh pr merge "$PR_NUMBER" --merge --delete-branch=false
```

- `--merge` 로 merge commit 을 남긴다 (히스토리에 hotfix 가 명확히 표시).
- `--delete-branch=false` 로 브랜치 유지 (§7 back-merge 후 일괄 정리).
- 충돌 발생 시 중단하고 사용자에게 알린다. 자동 resolve 금지.

### 6. 패치 태그 + GitHub Release

```bash
git checkout main
git pull origin main

# annotated 태그
git tag -a vX.Y.(Z+1) -m "hotfix: <버그 요약>"
git push origin vX.Y.(Z+1)

# GitHub Release 공개 (릴리즈 노트 필수)
gh release create vX.Y.(Z+1) \
  --target main \
  --title "vX.Y.(Z+1) — Hotfix" \
  --notes "$(cat <<'EOF'
<§4 의 hotfix 릴리즈 노트 본문>
EOF
)"
```

- 태그는 반드시 main 의 머지 커밋 SHA 에 찍는다.
- 릴리즈 노트를 생략하고 태그만 push 하는 것은 금지.

### 7. `develop` back-merge (필수)

이 단계를 빼먹으면 **다음 릴리즈에서 같은 버그가 재발**한다. 절대 생략 금지.

```bash
git checkout develop
git pull origin develop
git merge --no-ff hotfix/vX.Y.(Z+1) -m "chore: hotfix vX.Y.(Z+1) develop 동기화"
git push origin develop
```

- develop 에 최근 머지된 feature 커밋과 hotfix 가 충돌하면 여기서 해결한다.
- develop 은 PR 필수가 아니므로 로컬 머지 후 직접 push 가능 (hook 통과).

### 8. hotfix 브랜치 정리

```bash
git branch -d hotfix/vX.Y.(Z+1)
git push origin --delete hotfix/vX.Y.(Z+1)
```

### 9. 결과 보고

- 생성된 태그 (`vX.Y.(Z+1)`)
- GitHub Release URL
- hotfix PR URL + 머지 SHA
- 수정한 버그 요약 + 영향 범위
- develop back-merge 완료 여부 (✅ 필수 확인)

## 금지 사항 (재확인)

- `git revert <머지커밋>` 으로 이전 릴리즈 롤백 금지 — forward-fix 만 허용
- `git tag -d vX.Y.Z` / `git push --delete origin vX.Y.Z` 금지 — 이전 잘못된 릴리즈 태그도 기록으로 보존
- `gh release delete vX.Y.Z` 금지 — 릴리즈 노트는 "그때 이런 문제가 있었다" 의 증거로 남긴다
- `git push --force` to `main` / `develop` 금지 (서버 + hook 차단)
- `develop` back-merge 생략 금지
- 릴리즈 노트 없이 태그/릴리즈 생성 금지

## 실패 / 복구

- **§5 PR 머지 충돌**: hotfix 브랜치에서 `git merge origin/main` 으로 충돌 해결 → 재시도.
- **§6 태그 생성 실패**: 이미 `vX.Y.(Z+1)` 태그가 존재한다면 이전 hotfix 시도가 중단된 상태일 수 있음. 태그가 가리키는 커밋이 현재 main HEAD 와 일치하는지 확인 후 진행.
- **§7 back-merge 충돌**: develop 의 변경과 충돌 → develop 에서 수동 해결 후 머지. 이 경우에도 force push 금지.
- **hotfix 자체가 또 다른 버그를 유발**: 또 다른 hotfix (`vX.Y.(Z+2)`) 를 만든다. 이전 hotfix 태그/릴리즈는 그대로 둔다.
