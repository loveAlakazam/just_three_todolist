-- profiles.updated_at 자동 갱신 트리거
-- UPDATE 시 updated_at이 현재 시각으로 자동 설정된다.

create or replace function public.update_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create trigger profiles_updated_at
  before update on public.profiles
  for each row execute function public.update_updated_at();
