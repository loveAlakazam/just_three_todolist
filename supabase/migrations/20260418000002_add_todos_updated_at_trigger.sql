-- todos.updated_at 자동 갱신 트리거
-- UPDATE 시 updated_at이 서버 현재 시각으로 자동 설정된다.
-- (profiles 에서 이미 정의된 public.update_updated_at() 함수를 재사용)

create trigger todos_updated_at
  before update on public.todos
  for each row execute function public.update_updated_at();
