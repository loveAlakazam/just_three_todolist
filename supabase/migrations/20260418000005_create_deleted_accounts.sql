-- 회원탈퇴 쿨다운 테이블 (deleted_accounts)
--
-- 탈퇴한 회원의 14일 재가입 쿨다운을 강제하기 위한 별도 테이블.
-- `auth.users` 를 FK 로 참조하지 않는다 — 탈퇴 시 `auth.users` row 가 삭제되므로
-- FK 가 dangling 되기 때문. 이메일 / OAuth identity (provider + provider_user_id)
-- 를 plain column 으로 저장하여 재가입 시 identity 매칭에 사용한다.
--
-- 접근 정책: RLS 활성화 + 정책 없음 = 일반 사용자(authenticated/anon) 직접 조회/조작 불가.
-- 오직 service_role(Edge Function) 과 security definer RPC (check_signin_cooldown)
-- 만 이 테이블을 건드릴 수 있다.
--
-- 삽입 주체: `delete-account` Edge Function (탈퇴 처리 시).
-- 조회 주체: `check_signin_cooldown()` RPC (로그인 직후 쿨다운 판정).

create table if not exists public.deleted_accounts (
  id                uuid primary key default gen_random_uuid(),
  email             text,                              -- 탈퇴 시점 이메일 (소문자 정규화)
  provider          text        not null,              -- OAuth 제공자 ('google' 등)
  provider_user_id  text        not null,              -- OAuth 제공자 사용자 식별자 (Google sub 등)
  deleted_at        timestamptz not null default now(),
  reactivation_at   timestamptz generated always as (deleted_at + interval '14 days') stored
);

-- 재가입 시도 시 가장 최근 탈퇴 이력을 빠르게 찾기 위한 인덱스.
create index if not exists idx_deleted_accounts_email_recent
  on public.deleted_accounts (email, deleted_at desc);
create index if not exists idx_deleted_accounts_provider_recent
  on public.deleted_accounts (provider, provider_user_id, deleted_at desc);

-- RLS 활성화. 정책은 일부러 추가하지 않는다 →
-- authenticated / anon 은 select/insert/update/delete 모두 차단된다.
-- service_role 은 RLS 를 무시하고, security definer RPC 는 definer 권한으로 통과.
alter table public.deleted_accounts enable row level security;
