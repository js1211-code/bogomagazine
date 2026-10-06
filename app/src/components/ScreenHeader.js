import { Pressable, StyleSheet, Text, View } from 'react-native';
import { colors, hairline, typography } from '../theme';

// Figma 탐색 영역: 높이 52, 뒤로 가기 44×44 + 제목 (제목은 뒤로 가기 버튼에 4 만큼 겹쳐 시작한다)
// bordered: 아래에 가는 선을 그린다 (동의 상세 화면)
export default function ScreenHeader({ title, onBack, bordered = false, titleStyle }) {
  return (
    <View style={[styles.bar, bordered && styles.bordered]}>
      <BackButton onPress={onBack} />
      <Text style={[styles.title, titleStyle]}>{title}</Text>
    </View>
  );
}

// 뒤로 가기 '<' 버튼 (44×44). 다른 머리말에서도 쓴다.
export function BackButton({ onPress, label = '뒤로 가기' }) {
  return (
    <Pressable accessibilityRole="button" accessibilityLabel={label} onPress={onPress} style={styles.back}>
      <View style={styles.chevron} />
    </Pressable>
  );
}

const styles = StyleSheet.create({
  bar: { height: 52, flexDirection: 'row', alignItems: 'center' },
  bordered: { borderBottomWidth: hairline, borderBottomColor: colors.border.default },
  back: { width: 44, height: 44, alignItems: 'center', justifyContent: 'center' },
  // 아이콘 없이 테두리 두 변을 45도 돌려 '<' 모양을 만든다
  chevron: {
    width: 11,
    height: 11,
    borderLeftWidth: 2,
    borderBottomWidth: 2,
    borderColor: colors.text.primary,
    transform: [{ rotate: '45deg' }, { translateX: 2 }],
  },
  title: { ...typography.body, color: colors.text.primary, marginLeft: -4 },
});
