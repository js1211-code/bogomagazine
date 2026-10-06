// 1단계 전용: 서버가 없는 동안 쓰는 가짜 데이터. 앱을 완전히 껐다 켜면 사라진다.
// 실제 API 로 바꾸면 repositories/, auth/ 쪽 함수만 바뀌고 이 파일은 쓰이지 않는다.

// provider('kakao' | 'apple') 별 가짜 계정. profileSaved 가 false 면 아직 가입 절차(이름 입력)를 안 마친 계정.
const accounts = {};
let currentProvider = null;

// 카카오는 닉네임을 이름으로 미리 채워 주고, 애플은 이름을 주지 않는다 (명세서 ACC-01/02, PRF-01)
const DEFAULT_NAME = { kakao: '강보민', apple: null };

// 개발용: true 면 로그아웃할 때 계정을 지워서, 다시 로그인하면 새 계정으로 시작한다
// (약관 → 이름 → 가족방 만들기를 매번 다시 보기 위해). 앱을 껐다 켜도 새 계정이 된다.
// '기존 회원은 바로 탭 화면' 동작을 확인하려면 false 로 바꾼다.
export const ALWAYS_NEW_USER = true;

// 이 계정을 처음 상태로 되돌린다 (계정 정보와 그 사람이 속한 가족방을 지운다)
export function resetAccount(provider) {
  const account = accounts[provider];
  if (!account) return;
  for (let i = groups.length - 1; i >= 0; i -= 1) {
    if (groups[i].members.includes(account.user.id)) groups.splice(i, 1);
  }
  delete accounts[provider];
}

export function getOrCreateAccount(provider) {
  if (!accounts[provider]) {
    accounts[provider] = {
      profileSaved: false,
      user: {
        id: `mock-user-${provider}`,
        name: DEFAULT_NAME[provider],
        birthMonth: null,
        birthDay: null,
      },
    };
  }
  return accounts[provider];
}

export function setCurrentProvider(provider) {
  currentProvider = provider;
}

export function getCurrentProvider() {
  return currentProvider;
}

export function getCurrentAccount() {
  return currentProvider ? accounts[currentProvider] : null;
}

// ── 가족방 ──────────────────────────────────────────────
// 가족방 목록. 각 항목: { group, members: [userId], recipients, relationshipByUser, deliveryAddress, inviteCode, requestKey }
export const groups = [];

// 개발 중 실패 화면을 확인하고 싶을 때 true 로 바꾼다 (가족방 만들기가 항상 실패한다)
export const SIMULATE_CREATE_FAILURE = false;
