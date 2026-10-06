import { getCurrentAccount } from '../mocks/mockStore';

// 내 프로필 저장소. 지금은 mock 이고, 서버가 준비되면 이 함수 안만 실제 호출로 바꾼다.
// 화면은 이 함수의 인자와 반환값 모양만 안다.

// patch: { name?, birthMonth?, birthDay? }  (생일은 월·일만, 연도는 받지 않는다 — PRF-01)
// 반환: 수정된 user  ← openapi 의 User 와 같은 모양
// TODO(2단계): PATCH /me (openapi 의 요청 본문: name, birthMonth, birthDay, ...) 로 교체
export async function updateMe(patch) {
  const account = getCurrentAccount();
  if (!account) throw new Error('로그인 상태가 아니에요.');

  account.user = { ...account.user, ...patch };
  // O-41(명세서 미결): 가입 도중 앱을 나갔다 다시 들어올 때 계정 상태 처리는 아직 정해지지 않았다.
  // mock 은 이름을 저장해야 가입이 끝난 것으로 본다.
  account.profileSaved = true;
  return account.user;
}
