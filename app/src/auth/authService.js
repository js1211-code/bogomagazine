// 1단계: 실제 카카오/애플 로그인 대신 mock 으로 통과시킨다.
// 2단계에서 이 파일 안의 함수만 실제 SDK + 서버 호출로 바꾸면 된다.
// 화면과 AuthContext 는 이 파일 함수의 반환값 모양만 알고 있다.
import { ALWAYS_NEW_USER, getCurrentProvider, getOrCreateAccount, resetAccount, setCurrentProvider } from '../mocks/mockStore';

// 최초 가입인데 필수 동의가 빠졌을 때 (서버: 422, 명세서 ACC-03)
export class ConsentRequiredError extends Error {
  constructor() {
    super('최초 가입에는 약관 동의가 필요해요.');
    this.name = 'ConsentRequiredError';
  }
}

function hasRequiredConsent(consent) {
  return Boolean(consent?.privacyConsented && consent?.termsConsented && consent?.ageOver14Confirmed);
}

// provider: 'kakao' | 'apple'
// consent: { privacyConsented, termsConsented, ageOver14Confirmed, researchConsented } (최초 가입일 때만 필수)
// 반환: { accessToken, isNewUser, user }  ← openapi 의 AuthResult 와 같은 모양
// TODO(2단계): 카카오 SDK 로 받은 토큰을 POST /auth/kakao, 애플은 POST /auth/apple 에 보낸다.
// TODO(API 확인): 초대 링크로 들어온 경우 inviteToken 도 함께 보낸다 (온보딩 ③).
export async function signIn(provider, consent) {
  const account = getOrCreateAccount(provider);
  const isNewUser = !account.profileSaved;
  if (isNewUser && !hasRequiredConsent(consent)) throw new ConsentRequiredError();

  setCurrentProvider(provider);
  return { accessToken: 'mock-access-token', isNewUser, user: account.user };
}

export async function signOut() {
  // TODO(2단계): 서버 로그아웃(/auth/logout) + 저장된 토큰 삭제
  // 개발용: 가입 절차를 매번 다시 보기 위해 로그아웃하면 계정을 지운다 (mockStore 의 ALWAYS_NEW_USER)
  if (ALWAYS_NEW_USER) resetAccount(getCurrentProvider());
  setCurrentProvider(null);
}
