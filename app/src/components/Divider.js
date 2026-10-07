import { StyleSheet, View } from 'react-native';
import { colors, hairline } from '../theme';

// 가는 가로 구분선. 설명이 붙은 입력칸 사이처럼 묶음을 나눌 때 쓴다.
export default function Divider() {
  return <View style={styles.line} />;
}

const styles = StyleSheet.create({
  line: { height: hairline, backgroundColor: colors.border.default },
});
