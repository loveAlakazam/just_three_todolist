-- 로그인 직후 14일 쿨다운 판정 RPC (check_signin_cooldown)
--
-- 클라이언트가 `signInWithIdToken()` 성공 직후(그리고 `ensureProfileExists` 이전)
-- 이 RPC 를 호출한다. 쿨다운 중이면 클라이언트는 `auth.signOut()` 을 호출해
-- 방금 만들어진 세션을 제거하고 `CooldownException` 을 throw 해 로그인 화면에
-- 남게 한다.
--
-- 매칭 로직: 현재 인증된 사용자의 JWT 에서
--   - email (소문자 정규화)
--   - app_metadata.provider (예: 'google')
--   - user_metadata.provider_id / user_metadata.sub (Google OAuth sub)
-- 를 뽑아 `deleted_accounts` 에서 가장 최근 탈퇴 row 를 찾는다. 이메일 단독
-- 매칭만으로는 Google 계정 이메일 변경 시 우회될 수 있으므로 provider identity
-- 매칭을 함께 사용한다.
--
-- 권한: security definer 로 실행되어 RLS 가 활성화된 `deleted_accounts` 도
-- 조회할 수 있다. `set search_path = public` 으로 schema 탈취를 방지한다.
-- anon 은 접근 불가. authenticated 만 호출 가능.

create or replace function public.check_signin_cooldown()
returns table(blocked boolean, until timestamptz, remaining_days int)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_email         text;
  v_provider      text;
  v_provider_uid  text;
  v_row           public.deleted_accounts%rowtype;
begin
  v_email := lower(coalesce(auth.jwt() ->> 'email', ''));
  v_provider := coalesce(auth.jwt() -> 'app_metadata' ->> 'provider', '');
  -- Supabase 버전에 따라 provider_id 또는 sub 에 저장됨. 둘 다 시도.
  v_provider_uid := coalesce(
    auth.jwt() -> 'user_metadata' ->> 'provider_id',
    auth.jwt() -> 'user_metadata' ->> 'sub',
    ''
  );

  select *
    into v_row
    from public.deleted_accounts
   where (v_email <> '' and email = v_email)
      or (v_provider <> '' and v_provider_uid <> ''
          and provider = v_provider
          and provider_user_id = v_provider_uid)
   order by deleted_at desc
   limit 1;

  -- 매칭되는 탈퇴 기록이 없거나 이미 14일이 지났으면 쿨다운 해제.
  if not found or v_row.reactivation_at <= now() then
    return query select false, null::timestamptz, 0;
    return;
  end if;

  -- 쿨다운 활성 — 남은 일수는 올림 계산(당일 23:59:59 이라도 D-1 로 안내).
  return query
    select
      true,
      v_row.reactivation_at,
      greatest(
        0,
        ceil(extract(epoch from (v_row.reactivation_at - now())) / 86400)::int
      );
end;
$$;

revoke all on function public.check_signin_cooldown() from public;
grant execute on function public.check_signin_cooldown() to authenticated;
