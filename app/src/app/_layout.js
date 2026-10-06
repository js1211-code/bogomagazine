import { Stack } from 'expo-router';
import * as SplashScreen from 'expo-splash-screen';
import { StatusBar } from 'expo-status-bar';
import { useFonts } from 'expo-font';
import { useEffect } from 'react';
import { AuthProvider, useAuth } from '../context/AuthContext';
import { FamilyProvider, useFamily } from '../context/FamilyContext';
import { fontSources } from '../theme';

// 글꼴이 준비될 때까지 스플래시 화면을 유지한다 (글꼴이 늦게 바뀌어 보이는 깜빡임 방지)
SplashScreen.preventAutoHideAsync();

function RootStack() {
  const { isLoggedIn, needsOnboarding } = useAuth();
  const { ready: familyReady, needsFamilySetup } = useFamily();

  // guard 가 false 인 화면은 접근이 막히고, 상태가 바뀌면 자동으로 이동한다.
  //  로그인 전                      → login
  //  가입 절차 중 / 가족방이 없음    → (onboarding)
  //  가족방 목록을 불러오는 중       → loading
  //  모두 끝남                      → (tabs)
  const inOnboarding = isLoggedIn && (needsOnboarding || needsFamilySetup);
  return (
    <Stack screenOptions={{ headerShown: false }}>
      <Stack.Protected guard={!isLoggedIn}>
        <Stack.Screen name="login" />
        <Stack.Screen name="terms-detail" />
      </Stack.Protected>
      <Stack.Protected guard={inOnboarding}>
        <Stack.Screen name="(onboarding)" />
      </Stack.Protected>
      <Stack.Protected guard={isLoggedIn && !needsOnboarding && !familyReady}>
        <Stack.Screen name="loading" />
      </Stack.Protected>
      <Stack.Protected guard={isLoggedIn && familyReady && !inOnboarding}>
        <Stack.Screen name="(tabs)" />
      </Stack.Protected>
    </Stack>
  );
}

export default function RootLayout() {
  const [fontsLoaded, fontError] = useFonts(fontSources);

  useEffect(() => {
    if (fontsLoaded || fontError) SplashScreen.hideAsync();
  }, [fontsLoaded, fontError]);

  // 글꼴 로딩이 실패해도 기본 글꼴로라도 앱은 열어야 한다
  if (!fontsLoaded && !fontError) return null;

  return (
    <AuthProvider>
      <FamilyProvider>
        <StatusBar style="dark" />
        <RootStack />
      </FamilyProvider>
    </AuthProvider>
  );
}
