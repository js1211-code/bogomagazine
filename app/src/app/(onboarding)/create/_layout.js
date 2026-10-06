import { Stack } from 'expo-router';
import { CreateFamilyDraftProvider } from '../../../context/CreateFamilyDraft';

// 가족방 만들기 흐름 (FAM-01): 1/3 받는 분 → 2/3 배송지 → 3/3 이름 짓기 → 만드는 중 → 완료·초대
// 만드는 중·완료 화면은 뒤로 가기(밀어서 뒤로 가기 포함)를 막는다.
export default function CreateLayout() {
  return (
    <CreateFamilyDraftProvider>
      <Stack screenOptions={{ headerShown: false }}>
        <Stack.Screen name="recipient" />
        <Stack.Screen name="address" />
        <Stack.Screen name="naming" />
        <Stack.Screen name="creating" options={{ gestureEnabled: false, animation: 'fade' }} />
        <Stack.Screen name="done" options={{ gestureEnabled: false, animation: 'fade' }} />
      </Stack>
    </CreateFamilyDraftProvider>
  );
}
