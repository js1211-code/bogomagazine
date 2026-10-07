import { StyleSheet, Text, View } from 'react-native';
import { colors, typography } from '../theme';
import { BackButton } from './ScreenHeader';

// 가운데에 '보고잡지' 가 있는 머리말 (Figma 0-5, 0-4-4, 0-4-5)
// onBack 을 주면 왼쪽에 뒤로 가기 '<' 를 보여 준다 (0-5 → 처음 화면, 사용자 추가 기능)
export default function BrandHeader({ onBack, backLabel }) {
  return (
    <View style={styles.bar}>
      {onBack ? (
        <View style={styles.back}>
          <BackButton onPress={onBack} label={backLabel} />
        </View>
      ) : null}
      <Text style={styles.title}>보고잡지</Text>
    </View>
  );
}

const styles = StyleSheet.create({
  bar: { height: 52, alignItems: 'center', justifyContent: 'center' },
  back: { position: 'absolute', left: 24, top: 4 },
  title: { ...typography.label, color: colors.text.primary },
});
