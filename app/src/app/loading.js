import { StyleSheet, View } from 'react-native';
import { colors } from '../theme';

// 로그인 직후 가족방 목록을 불러오는 아주 짧은 동안 보이는 빈 화면.
// 대부분 눈에 띄지 않을 만큼 짧아서 로딩 표시는 넣지 않았다 (깜빡임 방지).
export default function LoadingScreen() {
  return <View style={styles.screen} />;
}

const styles = StyleSheet.create({
  screen: { flex: 1, backgroundColor: colors.background.page },
});
