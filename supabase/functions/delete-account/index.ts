// 회원탈퇴 Edge Function (delete-account)
//
// 클라이언트가 `supabase.functions.invoke('delete-account')` 로 호출한다.
// Supabase SDK 가 자동으로 현재 세션의 JWT 를 Authorization 헤더로 실어 보내므로
// 본 함수는 그 JWT 로 "호출자가 누구인지" 를 검증한 뒤, 서버 권한(service_role)이
// 필요한 작업만 수행한다.
//
// 수행 절차
// 1) Authorization 헤더 존재 확인 (없으면 401)
// 2) userClient (anon key + 요청 JWT) 로 `auth.getUser()` 호출하여 신원 확인
// 3) identity 에서 provider / provider_user_id / email 추출
// 4) adminClient (service_role) 로 `deleted_accounts` 에 쿨다운 row INSERT
//    - 먼저 INSERT 가 성공해야 auth.users 삭제를 진행 → "탈퇴는 됐는데
//      쿨다운 누락" 상태 방지
// 5) adminClient 로 `auth.admin.deleteUser(user.id)` 호출
//    - `todos.user_id` FK 가 `on delete cascade` 이므로 todo 도 함께 삭제
//    - `profiles` 는 클라이언트가 이미 삭제했거나, 살아있어도 RLS 로 owner 가
//      사라졌으므로 더 이상 접근 불가
//
// 참고: `04_profile.md` §7 '왜 Edge Function `delete-account` 가 필요한가'.

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

// Flutter mobile 앱이 주 클라이언트이지만, Flutter Web 이나 로컬 테스트에서
// CORS preflight 가 발생할 수 있어 기본 헤더를 세팅한다.
const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers':
    'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

Deno.serve(async (req) => {
  // CORS preflight.
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  // 1) Authorization 헤더 검증.
  const authHeader = req.headers.get('Authorization');
  if (!authHeader) {
    return json({ error: 'Unauthorized' }, 401);
  }

  const supabaseUrl = Deno.env.get('SUPABASE_URL');
  const anonKey = Deno.env.get('SUPABASE_ANON_KEY');
  const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  if (!supabaseUrl || !anonKey || !serviceRoleKey) {
    return json({ error: 'Edge Function env not configured' }, 500);
  }

  // 2) 호출자의 JWT 로 신원 확인 — 요청이 "본인" 의 것인지 확인하는 유일한 지점.
  //    anon key + 요청 JWT 조합이므로 Supabase 가 서명/만료를 검증한다.
  const userClient = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: authHeader } },
  });
  const { data: userData, error: userErr } = await userClient.auth.getUser();
  if (userErr || !userData?.user) {
    return json({ error: 'Unauthorized' }, 401);
  }
  const user = userData.user;

  // 3) identity 추출. 회원가입을 Google OAuth 만 받으므로 identities[0] 가 google
  //    이라고 가정. provider_user_id 는 구현 시점 Supabase 버전에 따라 위치가
  //    다를 수 있어 identity.id → identity_data.sub → user.id 순으로 fallback.
  const identity = (user.identities ?? [])[0];
  const provider = identity?.provider ?? 'unknown';
  const providerUserId =
    identity?.id ?? identity?.identity_data?.sub ?? user.id;
  const email = (user.email ?? '').toLowerCase();

  // 4) 쿨다운 row INSERT — service_role 로 RLS 우회. 실패 시 auth.users 는
  //    건드리지 않고 중단 → 클라이언트가 재시도 가능 (사용자 데이터 손실 없음).
  const adminClient = createClient(supabaseUrl, serviceRoleKey);
  const { error: insertErr } = await adminClient
    .from('deleted_accounts')
    .insert({
      email,
      provider,
      provider_user_id: providerUserId,
    });
  if (insertErr) {
    return json(
      { error: `failed to record cooldown: ${insertErr.message}` },
      500,
    );
  }

  // 5) auth.users 삭제 → todos cascade 삭제.
  const { error: deleteErr } = await adminClient.auth.admin.deleteUser(
    user.id,
  );
  if (deleteErr) {
    return json({ error: deleteErr.message }, 500);
  }

  return json({ ok: true }, 200);
});

function json(body: unknown, status: number): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'content-type': 'application/json' },
  });
}
