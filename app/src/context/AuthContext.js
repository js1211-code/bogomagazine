import { createContext, useContext, useMemo, useState } from 'react';
import * as authService from '../auth/authService';

const AuthContext = createContext(null);

export function AuthProvider({ children }) {
  const [session, setSession] = useState(null);

  const value = useMemo(
    () => ({
      session,
      isLoggedIn: session !== null,
      async signInWithKakao() {
        setSession(await authService.signInWithKakao());
      },
      async signInWithApple() {
        setSession(await authService.signInWithApple());
      },
      async signOut() {
        await authService.signOut();
        setSession(null);
      },
    }),
    [session],
  );

  return <AuthContext.Provider value={value}>{children}</AuthContext.Provider>;
}

export function useAuth() {
  const ctx = useContext(AuthContext);
  if (!ctx) throw new Error('useAuth 는 AuthProvider 안에서만 쓸 수 있어요.');
  return ctx;
}
