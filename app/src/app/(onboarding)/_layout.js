import { Stack } from 'expo-router';
import { useAuth } from '../../context/AuthContext';

// 가입 절차 화면 묶음.
//  이름 입력(0-2)을 마치기 전 → name
//  마친 뒤 → no-family(0-5) → create(가족방 만들기)
// 이름 입력을 마치면 name 이 막히면서 자동으로 no-family 로 넘어간다.
export default function OnboardingLayout() {
  const { needsOnboarding } = useAuth();
  return (
    <Stack screenOptions={{ headerShown: false }}>
      <Stack.Protected guard={needsOnboarding}>
        <Stack.Screen name="name" />
      </Stack.Protected>
      <Stack.Protected guard={!needsOnboarding}>
        <Stack.Screen name="no-family" />
        {/* 만들기 흐름 전체를 밀어서 닫으면 1/3 의 '입력한 내용이 사라져요' 확인을 건너뛰므로 막는다.
            (흐름 안의 단계끼리는 밀어서 뒤로 가기가 된다) */}
        <Stack.Screen name="create" options={{ gestureEnabled: false }} />
      </Stack.Protected>
    </Stack>
  );
}
