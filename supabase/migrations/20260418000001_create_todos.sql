-- todos 테이블: 사용자의 일별 목표 (하루 최대 10개, 클라이언트에서 제한)
create table public.todos (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  date date not null,
  text text not null default '',
  is_completed boolean not null default false,
  order_index integer not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- 일별 조회 + 정렬 최적화
create index idx_todos_user_date on public.todos (user_id, date, order_index);

alter table public.todos enable row level security;

-- RLS: 본인(auth.uid() = user_id) 만 SELECT / INSERT / UPDATE / DELETE
create policy "todos owner select"
  on public.todos for select
  using (auth.uid() = user_id);

create policy "todos owner insert"
  on public.todos for insert
  with check (auth.uid() = user_id);

create policy "todos owner update"
  on public.todos for update
  using (auth.uid() = user_id);

create policy "todos owner delete"
  on public.todos for delete
  using (auth.uid() = user_id);
