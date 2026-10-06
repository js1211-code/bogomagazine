import { StyleSheet, Text, View } from 'react-native';
import { colors, typography } from '../theme';

// 뒤로 가기 없이 가운데에 '보고잡지' 만 있는 머리말 (Figma 0-5, 0-4-4, 0-4-5)
export default function BrandHeader() {
  return (
    <View style={styles.bar}>
      <Text style={styles.title}>보고잡지</Text>
    </View>
  );
}

const styles = StyleSheet.create({
  bar: { height: 52, alignItems: 'center', justifyContent: 'center' },
  title: { ...typography.label, color: colors.text.primary },
});
