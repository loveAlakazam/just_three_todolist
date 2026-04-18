-- profiles 테이블: 사용자 프로필 (auth.users와 1:1)
create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  name text not null,
  avatar_url text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.profiles enable row level security;

-- RLS: 본인만 조회/수정/삽입
create policy "profiles are viewable by owner"
  on public.profiles for select
  using (auth.uid() = id);

create policy "profiles can be updated by owner"
  on public.profiles for update
  using (auth.uid() = id);

create policy "profiles can be inserted by owner"
  on public.profiles for insert
  with check (auth.uid() = id);

-- auth.users insert trigger: 회원가입 시 profiles row 자동 생성.
-- DB trigger를 사용하면 클라이언트의 ensureProfileExists() 호출을 생략할 수 있다.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  insert into public.profiles (id, name)
  values (
    new.id,
    coalesce(
      new.raw_user_meta_data->>'full_name',
      split_part(new.email, '@', 1)
    )
  );
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();
