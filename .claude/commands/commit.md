현재 staged/unstaged 변경사항을 분석하고 커밋을 생성한다.

## 절차

1. `git status`와 `git diff`로 변경사항 확인
2. `git log --oneline -5`로 최근 커밋 스타일 확인
3. 변경 내용을 분석하여 적절한 prefix 선택:
   - `feat`: 새로운 기능 추가
   - `fix`: 버그 수정
   - `docs`: 문서 변경
   - `style`: 코드 스타일 변경 (UI, 포맷팅, 기능 변화 없음)
   - `refactor`: 리팩터링 (동작 변경 없이 구조 개선)
   - `perf`: 성능 개선
   - `test`: 테스트 코드 추가/수정
   - `chore`: 기타 자잘한 변경 (빌드, 설정, 패키지, 의존성)
   - `ci`: CI 설정/스크립트 변경
   - `revert`: 이전 커밋 되돌리기
   - `remove`: 파일 삭제, 코드 제거
4. 커밋 메시지 형식: `prefix: 한글메시지` (약 60자 이내)
5. 변경된 파일을 staging하고 커밋 생성

## 규칙

- 커밋 메시지는 반드시 한글로 작성
- prefix는 반드시 영어 소문자
- .env, credentials 등 민감 파일은 커밋하지 않음
- 커밋 메시지 끝에 Co-Authored-By 추가
