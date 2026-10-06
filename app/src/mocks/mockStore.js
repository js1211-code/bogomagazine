// 1단계 전용: 서버가 없는 동안 쓰는 가짜 데이터. 앱을 완전히 껐다 켜면 사라진다.
// 실제 API 로 바꾸면 repositories/, auth/ 쪽 함수만 바뀌고 이 파일은 쓰이지 않는다.

// provider('kakao' | 'apple') 별 가짜 계정. profileSaved 가 false 면 아직 가입 절차(이름 입력)를 안 마친 계정.
const accounts = {};
let currentProvider = null;

// 카카오는 닉네임을 이름으로 미리 채워 주고, 애플은 이름을 주지 않는다 (명세서 ACC-01/02, PRF-01)
const DEFAULT_NAME = { kakao: '강보민', apple: null };

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

export function getCurrentAccount() {
  return currentProvider ? accounts[currentProvider] : null;
}

// ── 가족방 ──────────────────────────────────────────────
// 가족방 목록. 각 항목: { group, members: [userId], recipients, relationshipByUser, deliveryAddress, inviteCode, requestKey }
export const groups = [];

// 개발 중 실패 화면을 확인하고 싶을 때 true 로 바꾼다 (가족방 만들기가 항상 실패한다)
export const SIMULATE_CREATE_FAILURE = false;
