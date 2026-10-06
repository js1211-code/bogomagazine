// 1단계: 실제 카카오/애플 로그인 대신 mock 으로 통과시킨다.
// 2단계에서 이 파일 안의 함수만 실제 SDK + 서버 호출로 바꾸면 된다.
// 화면과 AuthContext 는 이 파일 함수의 반환값 모양만 알고 있다.

export async function signInWithKakao() {
  // TODO(2단계): 카카오 로그인 → 서버(/auth/kakao)에 인가코드 전달 → JWT 수신
  return { provider: 'kakao', user: { name: '테스트 사용자' } };
}

export async function signInWithApple() {
  // TODO(2단계): 애플 로그인 → 서버(/auth/apple)
  return { provider: 'apple', user: { name: '테스트 사용자' } };
}

export async function signOut() {
  // TODO(2단계): 서버 로그아웃(/auth/logout) + 저장된 토큰 삭제
}
