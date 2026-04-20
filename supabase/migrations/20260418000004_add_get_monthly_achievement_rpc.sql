-- 월별 달성률 집계 RPC
--
-- 캘린더 화면이 특정 월의 일자별 달성률을 조회할 때 사용한다.
-- 기존 방식(해당 월 todos row 를 전부 SELECT → 클라이언트에서 GROUP BY)은
-- 데이터가 쌓일수록 네트워크 전송량이 커지므로, 집계를 DB 쪽으로 옮겨
-- 결과(day, rate) 만 반환한다.
--
-- 계산식: per-day rate = sum(is_completed=true) / count(*)
--       셋째 자리에서 반올림하여 둘째 자리까지 유지 (numeric, scale 2).
-- 스코프: auth.uid() 본인의 todos 만. security definer 이지만 WHERE 절에서
--        user_id = auth.uid() 로 명시적으로 걸러 소유자 격리를 보장한다.

create or replace function public.get_monthly_achievement(
  p_year int,
  p_month int
)
returns table(day int, rate numeric)
language sql
security definer
set search_path = public
as $$
  select
    extract(day from date)::int as day,
    round(
      sum(case when is_completed then 1 else 0 end)::numeric
        / count(*)::numeric,
      2
    ) as rate
  from public.todos
  where user_id = auth.uid()
    and date >= make_date(p_year, p_month, 1)
    and date <  (make_date(p_year, p_month, 1) + interval '1 month')
  group by date
  order by date;
$$;

-- anon 에는 권한 주지 않음. 로그인 사용자(authenticated) 만 호출 가능.
revoke all on function public.get_monthly_achievement(int, int) from public;
grant execute on function public.get_monthly_achievement(int, int) to authenticated;
