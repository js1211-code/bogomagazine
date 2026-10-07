import { Pressable, StyleSheet, Text, View } from 'react-native';
import { colors, fonts, radius } from '../theme';

// 화면 안에서 하나를 고르는 칸들 (성별 등). 입력칸과 같은 연회색 칸이 나란히 있고, 고른 칸은 연두 상자가 된다.
// 테두리는 쓰지 않는다 (사용자 조정).
// '한 분 | 두 분' 같은 바탕 위 전환 버튼(SegmentedControl)과는 일부러 다르게 생겼다.
// options: [{ value, label }]
export default function ChoiceChips({ options, value, onChange }) {
  return (
    <View style={styles.row} accessibilityRole="radiogroup">
      {options.map((o) => {
        const selected = o.value === value;
        return (
          <Pressable
            key={o.value}
            accessibilityRole="radio"
            accessibilityState={{ selected }}
            onPress={() => onChange(o.value)}
            style={[styles.chip, selected && styles.chipSelected]}
          >
            <Text style={[styles.text, selected && styles.textSelected]}>{o.label}</Text>
          </Pressable>
        );
      })}
    </View>
  );
}

const styles = StyleSheet.create({
  row: { flexDirection: 'row', gap: 8 },
  chip: {
    flex: 1,
    height: 56,
    borderRadius: radius.surface,
    backgroundColor: colors.surface.subtle,
    alignItems: 'center',
    justifyContent: 'center',
  },
  chipSelected: { backgroundColor: colors.surface.accent },
  text: { fontFamily: fonts.medium, fontSize: 16, lineHeight: 24, color: colors.text.primary },
  textSelected: { fontFamily: fonts.bold, color: colors.action.primary },
});
