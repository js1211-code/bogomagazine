import { Pressable, StyleSheet, Text, View } from 'react-native';
import { colors, fonts, radius } from '../theme';

// Figma '한 분 / 두 분' 선택: 회색 바탕 위에서 고른 칸만 흰색으로 떠 있다.
// options: [{ value, label }]
export default function SegmentedControl({ options, value, onChange }) {
  return (
    <View style={styles.track} accessibilityRole="radiogroup">
      {options.map((o) => {
        const selected = o.value === value;
        return (
          <Pressable
            key={o.value}
            accessibilityRole="radio"
            accessibilityState={{ selected }}
            onPress={() => onChange(o.value)}
            style={[styles.option, selected && styles.optionSelected]}
          >
            <Text style={[styles.label, selected && styles.labelSelected]}>{o.label}</Text>
          </Pressable>
        );
      })}
    </View>
  );
}

const styles = StyleSheet.create({
  track: {
    flexDirection: 'row',
    height: 48,
    padding: 4,
    gap: 8,
    borderRadius: radius.control,
    backgroundColor: colors.surface.track,
  },
  option: {
    flex: 1,
    borderRadius: radius.control,
    borderWidth: 1,
    borderColor: 'transparent',
    alignItems: 'center',
    justifyContent: 'center',
  },
  optionSelected: { backgroundColor: colors.surface.default, borderColor: colors.border.default },
  label: { fontFamily: fonts.medium, fontSize: 16, lineHeight: 24, color: colors.text.secondary },
  labelSelected: { color: colors.text.primary },
});
