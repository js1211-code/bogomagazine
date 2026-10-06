import { useRef, useState } from 'react';
import { Pressable, StyleSheet, Text, TextInput, View } from 'react-native';
import { colors, hairline, radius, typography } from '../theme';

// Figma 입력칸: 라벨이 칸 안 위쪽에 있고 그 아래에 값(또는 안내 문구)이 있다.
// - 칸이 비어 있거나 입력 중이면 검은 테두리, 값이 채워져 있고 입력 중이 아니면 테두리 없음.
// - onPress 를 주면 글자를 직접 입력하지 않고 눌러서 시트를 여는 칸이 된다 (생일).
// 높이는 항상 72 로 고정해서 값을 입력해도 아래 내용이 밀리지 않게 한다.
export default function TextField({
  label,
  value,
  onChangeText,
  placeholder,
  onPress,
  helper,
  inputProps,
}) {
  const inputRef = useRef(null);
  const [focused, setFocused] = useState(false);
  const empty = !value;
  const outlined = focused || empty;

  return (
    <View style={styles.group}>
      <Pressable
        // 칸의 빈 곳을 눌러도 입력이 시작되게 한다. onPress 가 있으면 시트를 여는 버튼으로 동작.
        onPress={onPress ?? (() => inputRef.current?.focus())}
        accessibilityRole={onPress ? 'button' : undefined}
        accessibilityLabel={onPress ? label : undefined}
        style={styles.wrapper}
      >
        <View style={[styles.box, outlined && styles.boxOutlined]} />
        <View style={styles.texts}>
          <Text style={styles.label}>{label}</Text>
          {onPress ? (
            <Text style={[styles.value, empty && styles.placeholder]}>{empty ? placeholder : value}</Text>
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
  wrapper: { height: 72, justifyContent: 'center' },
  // 배경 상자: 테두리가 없을 때는 64 높이로 가운데, 있을 때는 72 전체
  box: {
    position: 'absolute',
    left: 0,
    right: 0,
    top: 4,
    bottom: 4,
    borderRadius: radius.large,
    backgroundColor: colors.surface.subtle,
    borderWidth: hairline,
    borderColor: 'transparent',
  },
  boxOutlined: { top: 0, bottom: 0, borderColor: colors.border.focus },
  texts: { paddingHorizontal: 16 },
  label: { ...typography.label, color: colors.text.secondary },
  value: {
    ...typography.body,
    color: colors.text.primary,
    padding: 0,
    marginTop: 2,
    height: 26,
  },
  placeholder: { color: colors.text.placeholder },
  helper: { ...typography.caption, color: colors.text.secondary },
});
