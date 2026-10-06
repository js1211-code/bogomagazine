import { Pressable, StyleSheet, Text, View } from 'react-native';
import { colors, typography } from '../theme';
import ScreenHeader from './ScreenHeader';

// Figma '탐색 (3단계)': 뒤로 가기 + 제목 + 오른쪽 'n / 전체', 그 아래 단계 막대 (높이 2, 간격 8)
// onStepPress(n): 이미 지나온 단계의 막대를 누르면 그 단계로 돌아간다 (사용자 추가 기능).
//   아직 안 간 다음 단계로는 이동하지 않는다.
export default function StepHeader({ title, step, total, onBack, onStepPress }) {
  return (
    <View style={styles.wrap}>
      <View style={styles.row}>
        <View style={styles.flex}>
          <ScreenHeader title={title} onBack={onBack} />
        </View>
        <Text style={styles.step}>{`${step} / ${total}`}</Text>
      </View>
      <View style={styles.bars}>
        {Array.from({ length: total }, (_, i) => {
          const n = i + 1;
          const done = n <= step;
          const canGoBack = onStepPress && n < step;
          return (
            <Pressable
              key={n}
              disabled={!canGoBack}
              onPress={() => onStepPress(n)}
              accessibilityRole={canGoBack ? 'button' : undefined}
              accessibilityLabel={canGoBack ? `${n}단계로 돌아가기` : undefined}
              // 막대가 가늘어서 누르기 쉽도록 위아래로 넉넉히
              hitSlop={{ top: 14, bottom: 14 }}
              style={[styles.bar, done && styles.barDone]}
            />
          );
        })}
      </View>
    </View>
  );
}

const styles = StyleSheet.create({
  wrap: { paddingHorizontal: 24 },
  row: { flexDirection: 'row', alignItems: 'center' },
  flex: { flex: 1 },
  step: { ...typography.label, color: colors.text.secondary },
  bars: { flexDirection: 'row', gap: 8 },
  bar: { flex: 1, height: 2, backgroundColor: colors.border.default },
  barDone: { backgroundColor: colors.action.primary },
});
