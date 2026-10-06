import { StyleSheet, Text, View } from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import Button from '../components/Button';
import { useAuth } from '../context/AuthContext';
import { colors, fonts, spacing, typography } from '../theme';

// Figma 0-1 로그인. 약관 동의 카드와 동의 시트는 온보딩 단계에서 붙인다.
export default function LoginScreen() {
  const { signInWithKakao, signInWithApple } = useAuth();

  return (
    <SafeAreaView style={styles.screen}>
      <View style={styles.hero}>
        <Text style={styles.eyebrow}>떨어져 있어도, 일상은 함께</Text>
        <Text style={styles.title}>보고잡지</Text>
        <Text style={styles.tagline}>{'우리 가족 소식이\n한 장의 신문이 되어 배달돼요'}</Text>
      </View>
      <View style={styles.actions}>
        <Button title="카카오 로그인" variant="kakao" onPress={signInWithKakao} />
        <Button title="Apple로 로그인" variant="apple" onPress={signInWithApple} />
      </View>
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  screen: { flex: 1, backgroundColor: colors.background.page, paddingHorizontal: spacing.lg },
  hero: { flex: 1, alignItems: 'center', justifyContent: 'center' },
  eyebrow: { ...typography.label, color: colors.text.editorial, marginBottom: spacing.sm },
  title: { fontFamily: fonts.bold, fontSize: 48, lineHeight: 60, letterSpacing: -1, color: colors.text.primary },
  tagline: { ...typography.body, color: colors.text.secondary, textAlign: 'center', marginTop: spacing.md },
  actions: { gap: spacing.sm, paddingBottom: spacing.md },
});
