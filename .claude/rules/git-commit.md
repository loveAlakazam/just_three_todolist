---
description: git commit 메시지 작성 규칙. 커밋 생성 시 항상 참조.
globs:
  - "**/*"
---

# Git 커밋 메시지 규칙

## 형식

```
커밋prefix: 커밋메시지
```

- `커밋prefix`는 영어 소문자
- 커밋메시지는 한글, 약 60자 이내
- prefix와 메시지 사이에 콜론 + 공백(`: `)

## 커밋 prefix 목록

| prefix | 목적 |
|--------|------|
| `feat` | 새로운 기능 추가 |
| `fix` | 버그 수정 |
| `docs` | 문서 변경 (README 등) |
| `style` | 코드 스타일 변경 (UI, 포맷팅, 기능 변화 없음) |
| `refactor` | 리팩터링 (동작 변경 없이 구조 개선) |
| `perf` | 성능 개선 |
| `test` | 테스트 코드 추가/수정 |
| `chore` | 기타 자잘한 변경 (빌드, 설정, 패키지, 의존성) |
| `ci` | CI 설정/스크립트 변경 (GitHub Actions, Jenkins 등) |
| `revert` | 이전 커밋 되돌리기 |
| `remove` | 파일 삭제, 코드 제거 |

## 예시

```
feat: 로그인 화면 UI 구현
fix: 캘린더 월 이동 시 날짜 오프셋 계산 오류 수정
chore: flutter_riverpod 패키지 추가
docs: CLAUDE.md 아키텍처 규칙 업데이트
style: Todo 화면 버튼 색상 디자인 시스템에 맞게 변경
refactor: TodoItemWidget 공통 위젯으로 분리
remove: 사용하지 않는 counter 예제 코드 제거
```
