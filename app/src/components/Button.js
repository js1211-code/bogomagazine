import { Pressable, StyleSheet, Text } from 'react-native';
import { colors, hairline, radius, typography } from '../theme';

// variant: primary(초록) | kakao | apple
const variants = {
  primary: { bg: colors.action.primary, fg: colors.text.onPrimary, border: colors.action.primary },
  kakao: { bg: colors.brand.kakao, fg: colors.brand.kakaoText, border: colors.brand.kakao },
  apple: { bg: colors.surface.default, fg: colors.brand.apple, border: colors.brand.apple },
};

export default function Button({ title, onPress, variant = 'primary', disabled = false }) {
  const v = variants[variant];
  return (
    <Pressable
      accessibilityRole="button"
      onPress={onPress}
      disabled={disabled}
      style={({ pressed }) => [
        styles.base,
        { backgroundColor: v.bg, borderColor: v.border },
        pressed && styles.pressed,
        disabled && styles.disabled,
      ]}
    >
      <Text style={[typography.button, { color: v.fg }]}>{title}</Text>
    </Pressable>
  );
}

const styles = StyleSheet.create({
  base: {
    height: 56,
    borderRadius: radius.surface,
    borderWidth: hairline,
    alignItems: 'center',
    justifyContent: 'center',
  },
  pressed: { opacity: 0.85 },
  disabled: { opacity: 0.4 },
});
