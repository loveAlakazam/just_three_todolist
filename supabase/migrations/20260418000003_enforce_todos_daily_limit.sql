-- 하루 최대 10개 todo 제한 (DB 레벨)
--
-- 클라이언트의 canAddMore 검사를 우회한 변조 INSERT 를 DB 에서 차단한다.
-- 동일 (user_id, date) 조합의 기존 row 수가 10개 이상이면 INSERT 실패.
--
-- 실패 시 PostgreSQL 에러코드 '23514' (check_violation) 를 반환하여
-- 클라이언트가 명확하게 분기 처리할 수 있다.

create or replace function public.enforce_todos_daily_limit()
returns trigger
language plpgsql
as $$
declare
  current_count integer;
begin
  select count(*)
    into current_count
    from public.todos
    where user_id = new.user_id
      and date = new.date;

  if current_count >= 10 then
    raise exception '하루 최대 10개까지만 생성할 수 있습니다.'
      using errcode = 'check_violation';
  end if;

  return new;
end;
$$;

create trigger todos_enforce_daily_limit
  before insert on public.todos
  for each row execute function public.enforce_todos_daily_limit();
