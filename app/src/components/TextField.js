import { useRef, useState } from 'react';
import { Pressable, StyleSheet, Text, TextInput, View } from 'react-native';
import { colors, hairline, radius, typography } from '../theme';

// Figma 입력칸: 라벨이 칸 안 위쪽에 있고 그 아래에 값(또는 안내 문구)이 있다.
// - 평소에는 테두리가 없고, 눌러서 입력 중일 때만 연한 테두리가 생긴다 (사용자 조정).
// - onPress 를 주면 글자를 직접 입력하지 않고 눌러서 시트를 여는 칸이 된다 (생일).
// - select: 고르는 칸이면 값 뒤에 '▾' 를 붙인다 (성별, 관계).
// 높이는 항상 80 으로 고정해서 테두리가 생기거나 값을 입력해도 아래 내용이 밀리지 않게 한다.
export default function TextField({
  label,
  value,
  onChangeText,
  placeholder,
  onPress,
  helper,
  select = false,
  inputProps,
}) {
  const inputRef = useRef(null);
  const [focused, setFocused] = useState(false);
  const empty = !value;

  return (
    <View style={styles.group}>
      <Pressable
        // 칸의 빈 곳을 눌러도 입력이 시작되게 한다. onPress 가 있으면 시트를 여는 버튼으로 동작.
        onPress={onPress ?? (() => inputRef.current?.focus())}
        accessibilityRole={onPress ? 'button' : undefined}
        accessibilityLabel={onPress ? label : undefined}
        style={styles.wrapper}
      >
        <View style={[styles.box, focused && styles.boxFocused]} />
        <View style={styles.texts}>
          <Text style={styles.label}>{label}</Text>
          {onPress ? (
            <Text style={[styles.value, empty && styles.placeholder]} numberOfLines={1}>{(empty ? placeholder : value) + (select ? '  ▾' : '')}</Text>
          ) : (
            <TextInput
              ref={inputRef}
              value={value}
              onChangeText={onChangeText}
              placeholder={placeholder}
              placeholderTextColor={colors.text.placeholder}
              onFocus={() => setFocused(true)}
              onBlur={() => setFocused(false)}
              style={styles.value}
              accessibilityLabel={label}
              {...inputProps}
            />
          )}
        </View>
      </Pressable>
      {helper ? <Text style={styles.helper}>{helper}</Text> : null}
    </View>
  );
}

const styles = StyleSheet.create({
  group: { gap: 12 },
  // 여백을 넉넉히 (사용자 조정: Figma 72 → 80, 좌우 16 → 20)
  wrapper: { height: 80, justifyContent: 'center' },
  box: {
    position: 'absolute',
    left: 0,
    right: 0,
    top: 0,
    bottom: 0,
    borderRadius: radius.surface,
    backgroundColor: colors.surface.subtle,
    borderWidth: hairline,
    borderColor: 'transparent',
  },
  boxFocused: { borderColor: colors.border.focus },
  texts: { paddingHorizontal: 20 },
  label: { ...typography.label, color: colors.text.secondary },
  value: {
    ...typography.body,
    color: colors.text.primary,
    padding: 0,
    marginTop: 4,
    height: 26,
  },
  placeholder: { color: colors.text.placeholder },
  helper: { ...typography.caption, color: colors.text.secondary },
});
