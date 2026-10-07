import { Pressable, StyleSheet, Text, View } from 'react-native';
import { colors, fonts, radius, typography } from '../theme';

// 약관 한 줄: 체크박스 + 이름 + (선택) '보기' 링크
// emphasis: 굵은 글씨(전체 동의, 필수 항목) / 보통 글씨(선택 항목)
// compact: 글씨 14 (받는 분 정보 동의 줄처럼 화면 안에 들어가는 동의 줄)
export default function CheckboxRow({ label, checked, onToggle, onView, emphasis = true, compact = false }) {
  return (
    <View style={styles.row}>
      <Pressable
        accessibilityRole="checkbox"
        accessibilityState={{ checked }}
        onPress={onToggle}
        style={styles.main}
      >
        <View style={[styles.box, checked && styles.boxChecked]}>
          {checked ? <Text style={styles.check}>✓</Text> : null}
        </View>
        <Text style={[styles.label, compact && styles.labelCompact, { fontFamily: emphasis ? fonts.medium : fonts.regular }]}>
          {label}
        </Text>
      </Pressable>
      {onView ? (
        <Pressable accessibilityRole="link" accessibilityLabel={`${label} 보기`} onPress={onView} hitSlop={12}>
          <Text style={styles.view}>보기</Text>
        </Pressable>
      ) : null}
    </View>
  );
}

const styles = StyleSheet.create({
  row: { flexDirection: 'row', alignItems: 'center', gap: 10, paddingVertical: 10 },
  main: { flex: 1, flexDirection: 'row', alignItems: 'center', gap: 10 },
  box: {
    width: 24,
    height: 24,
    borderRadius: radius.checkbox,
    borderWidth: 1,
    borderColor: colors.border.default,
    alignItems: 'center',
    justifyContent: 'center',
  },
  boxChecked: { backgroundColor: colors.action.primary, borderColor: colors.action.primary },
  check: { ...typography.button, color: colors.text.onPrimary, lineHeight: 20 },
  label: { flex: 1, fontSize: 15, color: colors.text.primary },
  labelCompact: { fontSize: 14, lineHeight: 22 },
  view: { ...typography.label, fontFamily: fonts.regular, color: colors.text.secondary },
});
