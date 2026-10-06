import { router } from 'expo-router';
import { ScrollView, StyleSheet, Text, View } from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import BrandHeader from '../../components/BrandHeader';
import Button from '../../components/Button';
import { FamilyIcon } from '../../components/LineIcons';
import { colors, fonts, hairline, radius } from '../../theme';

// Figma 0-5 가족방 없음 (명세서 ACC-01, FAM-06)
// '초대를 받았다면'(버튼 없음)과 '가족방을 처음 만든다면'([가족방 만들기])을 같은 무게로 보여 준다.
export default function NoFamilyScreen() {
  return (
    <SafeAreaView style={styles.screen} edges={['top', 'bottom']}>
      <BrandHeader />
      <ScrollView contentContainerStyle={styles.body}>
        <View style={styles.hero}>
          <FamilyIcon />
          <Text style={styles.title}>아직 함께하는 가족방이 없어요</Text>
          <Text style={styles.subtitle}>가족에게 초대를 받았는지에 따라 골라 주세요.</Text>
        </View>
        <View style={styles.divider} />

        <View style={[styles.card, styles.cardInfo]}>
          <Text style={styles.cardTitle}>초대를 받았다면</Text>
          <Text style={styles.cardText}>
            카카오톡에서 가족이 보낸 &apos;보고잡지&apos; 초대 메시지를 찾아 [가족신문 참여하기]를 눌러 주세요. 그
            가족방으로 바로 연결돼요.
          </Text>
        </View>

        <View style={[styles.card, styles.cardAction]}>
          <Text style={styles.cardTitle}>가족방을 처음 만든다면</Text>
          <Text style={styles.cardText}>신문 받을 분과 주소를 정하고 가족을 초대해요.</Text>
          <View style={styles.cardButton}>
            <Button title="가족방 만들기" variant="secondary" onPress={() => router.push('/create/recipient')} />
          </View>
        </View>
      </ScrollView>
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  screen: { flex: 1, backgroundColor: colors.background.page },
  body: { paddingHorizontal: 24, paddingTop: 24, paddingBottom: 16, gap: 24 },
  hero: { alignItems: 'center', paddingVertical: 32, gap: 24 },
  title: { fontFamily: fonts.bold, fontSize: 26, lineHeight: 39, color: colors.text.primary, textAlign: 'center' },
  subtitle: { fontFamily: fonts.regular, fontSize: 15, lineHeight: 22, color: colors.text.secondary, textAlign: 'center' },
  divider: { height: hairline, backgroundColor: colors.border.default },
  card: { borderRadius: radius.surface, padding: 20, gap: 8 },
  cardInfo: { backgroundColor: colors.surface.track },
  cardAction: { backgroundColor: colors.surface.default, borderWidth: hairline, borderColor: colors.border.default },
  cardTitle: { fontFamily: fonts.bold, fontSize: 17, lineHeight: 25, color: colors.text.primary },
  cardText: { fontFamily: fonts.regular, fontSize: 15, lineHeight: 23, color: colors.text.secondary },
  cardButton: { marginTop: 8 },
});
