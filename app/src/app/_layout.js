import { Stack } from 'expo-router';
import * as SplashScreen from 'expo-splash-screen';
import { StatusBar } from 'expo-status-bar';
import { useFonts } from 'expo-font';
import { useEffect } from 'react';
import { AuthProvider, useAuth } from '../context/AuthContext';
import { fontSources } from '../theme';

// 글꼴이 준비될 때까지 스플래시 화면을 유지한다 (글꼴이 늦게 바뀌어 보이는 깜빡임 방지)
SplashScreen.preventAutoHideAsync();

function RootStack() {
  const { isLoggedIn } = useAuth();

  // guard 가 false 인 화면은 접근이 막히고, 로그인 상태가 바뀌면 자동으로 이동한다.
  return (
    <Stack screenOptions={{ headerShown: false }}>
      <Stack.Protected guard={!isLoggedIn}>
        <Stack.Screen name="login" />
      </Stack.Protected>
      <Stack.Protected guard={isLoggedIn}>
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
      <StatusBar style="dark" />
      <RootStack />
    </AuthProvider>
  );
}
