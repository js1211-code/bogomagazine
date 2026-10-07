import { Pressable, StyleSheet, Text, View } from 'react-native';
import { colors, fonts, typography } from '../theme';
import BottomSheet from './BottomSheet';

// 두 줄 칸으로 하나를 고르는 시트 (Figma 0-4-1-a 관계 선택). 칸을 누르면 바로 고르고 닫힌다.
// options: 문자열 배열 또는 [{ value, label }]
export default function ChoiceGridSheet({ visible, onClose, title, description, options, value, onSelect }) {
  const items = options.map((o) => (typeof o === 'string' ? { value: o, label: o } : o));
  return (
    <BottomSheet visible={visible} onClose={onClose} title={title} showHandle>
      {description ? <Text style={styles.description}>{description}</Text> : null}
      <View style={styles.grid}>
        {items.map((item) => {
          const selected = item.value === value;
          return (
            <Pressable
              key={item.value}
              accessibilityRole="radio"
              accessibilityState={{ selected }}
              onPress={() => onSelect(item.value)}
              style={[styles.chip, selected && styles.chipSelected]}
            >
              <Text style={[styles.chipText, selected && styles.chipTextSelected]}>{item.label}</Text>
            </Pressable>
          );
        })}
      </View>
    </BottomSheet>
  );
}

const styles = StyleSheet.create({
  description: { ...typography.bodySmall, color: colors.text.secondary, marginBottom: 16 },
  // 2열, 칸 사이 16
  grid: { flexDirection: 'row', flexWrap: 'wrap', justifyContent: 'space-between', rowGap: 16 },
  chip: {
    width: '47.5%',
    height: 64,
    borderRadius: 14,
    borderWidth: 1.5,
    borderColor: 'transparent',
    backgroundColor: colors.surface.subtle,
    alignItems: 'center',
    justifyContent: 'center',
  },
  chipSelected: { backgroundColor: colors.surface.accent, borderColor: colors.action.primary },
  chipText: { fontFamily: fonts.medium, fontSize: 15, color: colors.text.primary },
  chipTextSelected: { fontFamily: fonts.bold, color: colors.action.primary },
});
