import { Stack } from 'expo-router';

// 가입 절차 화면 묶음. 지금은 0-2 이름 입력 하나이고, 가족 확인·가족방 만들기 화면이 이어서 들어온다.
export default function OnboardingLayout() {
  return <Stack screenOptions={{ headerShown: false }} />;
}
