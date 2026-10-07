import { createContext, useCallback, useContext, useMemo, useState } from 'react';
import * as authService from '../auth/authService';
import * as profileRepository from '../repositories/profileRepository';

const AuthContext = createContext(null);

// session: { provider, accessToken, isNewUser, user } | null
//  - isNewUser 가 true 인 동안은 아직 가입 절차(이름 입력)를 끝내지 않은 상태다.
export function AuthProvider({ children }) {
  const [session, setSession] = useState(null);

  // provider: 'kakao' | 'apple'. 최초 가입인데 consent 가 없으면 ConsentRequiredError 를 던진다.
  const signIn = useCallback(async (provider, consent) => {
    const result = await authService.signIn(provider, consent);
    setSession({ provider, ...result });
  }, []);

  const signOut = useCallback(async () => {
    await authService.signOut();
    setSession(null);
  }, []);

  // 이름·생일을 저장하고 가입 절차를 마친다 (0-2 이름 입력의 [다음])
  const completeProfile = useCallback(async (profile) => {
    const user = await profileRepository.updateMe(profile);
    setSession((prev) => (prev ? { ...prev, isNewUser: false, user } : prev));
  }, []);

  const value = useMemo(
    () => ({
      session,
      isLoggedIn: session !== null,
      needsOnboarding: session !== null && session.isNewUser,
      signIn,
      signOut,
      completeProfile,
    }),
    [session, signIn, signOut, completeProfile],
  );

  return <AuthContext.Provider value={value}>{children}</AuthContext.Provider>;
}

export function useAuth() {
  const ctx = useContext(AuthContext);
  if (!ctx) throw new Error('useAuth 는 AuthProvider 안에서만 쓸 수 있어요.');
  return ctx;
}
