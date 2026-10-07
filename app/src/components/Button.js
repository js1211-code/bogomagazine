import { Image, Pressable, StyleSheet, Text } from 'react-native';
import { colors, hairline, radius, typography } from '../theme';

// variant: primary(초록) | secondary(흰색+테두리) | quiet(배경 없는 글자 버튼) | kakao | apple
const variants = {
  primary: { bg: colors.action.primary, fg: colors.text.onPrimary, border: colors.action.primary },
  secondary: { bg: colors.surface.default, fg: colors.text.primary, border: colors.border.default },
  quiet: { bg: colors.background.paper, fg: colors.text.secondary, border: colors.background.paper },
  kakao: { bg: colors.brand.kakao, fg: colors.brand.kakaoText, border: colors.brand.kakao },
  apple: { bg: colors.surface.default, fg: colors.brand.apple, border: colors.brand.apple },
};

// disabled 일 때는 Figma 의 비활성 색을 쓴다 (primary 만 정의되어 있다)
const disabledStyle = { bg: colors.action.disabled, fg: colors.text.disabled, border: colors.action.disabled };

export default function Button({ title, onPress, variant = 'primary', disabled = false, icon }) {
  const v = disabled ? disabledStyle : variants[variant];
  return (
    <Pressable
      accessibilityRole="button"
      accessibilityState={{ disabled }}
      onPress={onPress}
      disabled={disabled}
      style={({ pressed }) => [
        styles.base,
        { backgroundColor: v.bg, borderColor: v.border },
        pressed && styles.pressed,
      ]}
    >
      {icon ? <Image source={icon} style={styles.icon} /> : null}
      <Text style={[typography.button, { color: v.fg }]}>{title}</Text>
    </Pressable>
  );
}

const styles = StyleSheet.create({
  base: {
    height: 56,
    borderRadius: radius.large,
    borderWidth: hairline,
    flexDirection: 'row',
    gap: 8,
    alignItems: 'center',
    justifyContent: 'center',
  },
  pressed: { opacity: 0.85 },
  icon: { width: 20, height: 20 },
});
