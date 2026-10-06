import { StyleSheet, Text, View } from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import Button from '../../components/Button';
import { useAuth } from '../../context/AuthContext';
import { colors, spacing, typography } from '../../theme';

// Figma 1-0 소식 피드 (아직 내용 없음)
export default function FeedScreen() {
  const { signOut } = useAuth();
  return (
    <SafeAreaView style={styles.screen}>
      <View style={styles.body}>
        <Text style={styles.title}>소식</Text>
      </View>
      <View style={styles.footer}>
        <Button title="로그아웃 (임시)" onPress={signOut} />
      </View>
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  screen: { flex: 1, backgroundColor: colors.background.page, paddingHorizontal: spacing.lg },
  body: { flex: 1, alignItems: 'center', justifyContent: 'center' },
  title: { ...typography.screenHeading, color: colors.text.primary },
  footer: { paddingBottom: spacing.md },
});
