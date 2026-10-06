import { Tabs } from 'expo-router';
import { colors, fonts, typography } from '../../theme';

// 하단 탭 3개 (명세서 HOME-04): 소식 | 질문카드 | 가족
// 설정(우상단)과 알림 종 아이콘은 공유 헤더에서 다룬다. (다음 작업)
export default function TabsLayout() {
  return (
    <Tabs
      screenOptions={{
        headerShown: false,
        tabBarActiveTintColor: colors.action.primary,
        tabBarInactiveTintColor: colors.text.secondary,
        tabBarLabelStyle: { fontFamily: fonts.medium, fontSize: typography.caption.fontSize },
        tabBarStyle: { backgroundColor: colors.surface.default, borderTopColor: colors.border.default },
      }}
    >
      <Tabs.Screen name="index" options={{ title: '소식' }} />
      <Tabs.Screen name="questions" options={{ title: '질문카드' }} />
      <Tabs.Screen name="family" options={{ title: '가족' }} />
    </Tabs>
  );
}
