import { router } from 'expo-router';
import { Alert, ScrollView, StyleSheet, Text, View } from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import Button from '../components/Button';
import ScreenHeader from '../components/ScreenHeader';
import { colors, fonts, hairline } from '../theme';

// Figma 0-1-a 동의 상세. 문구는 Figma 그대로 옮겼다.
// Figma 의 '동의 문안 검토 필요 · 디자인 초안' 메모 박스는 내부 메모라 넣지 않았다.
// TODO(O-40): 보관 기간과 법적 문구가 확정되면 '미결' 문구를 바꾼다.
const SECTIONS = [
  {
    title: '개인정보 수집·이용 동의 · 필수',
    items: [
      ['정보 주체 / 입력하는 사람', '가입·참여하는 구성원이 자신의 정보를 입력해요.'],
      ['입력 항목', '이름, 받는 분과의 관계, 생일(월·일, 선택)', true],
      ['사용 목적', '구성원 표시와 ‘관계 + 이름’ 신문 표기, 생일이 다가오면 신문에 함께 알리는 데 사용해요.'],
      ['보관 기간', '미결 · 법적 문구 검토 후 확정'],
      ['동의하지 않으면', '가입할 수 없어요.'],
    ],
  },
  {
    title: '받는 분(제3자) 정보 입력 동의 · 필수',
    items: [
      ['정보 주체 / 입력하는 사람', '신문을 받는 분의 정보를 가족방을 만드는 사람이 입력해요. 받는 분은 계정 없이 신문만 받아요.'],
      ['입력 항목', '이름, 성별, 배송지', true],
      ['사용 목적', '받는 분 확인과 신문 배송, 호칭 적용에 사용해요.'],
      ['보관 기간', '미결 · 법적 문구 검토 후 확정'],
      ['동의하지 않으면', '가족방을 만들 수 없어요.'],
    ],
    note: '입력 전 받는 분께 어떤 정보를 입력하는지 알려 드리고 동의를 받아 주세요.',
  },
];

export default function TermsDetailScreen() {
  const openPolicy = () => {
    // TODO(O-40): 개인정보 처리방침 웹 페이지 주소가 정해지면 인앱 브라우저로 연다
    Alert.alert('준비 중이에요', '개인정보 처리방침은 문구가 확정되면 볼 수 있어요.');
  };

  return (
    <SafeAreaView style={styles.screen} edges={['top', 'bottom']}>
      <View style={styles.headerWrap}>
        <ScreenHeader title="가입 / 동의 내용" onBack={() => router.back()} titleStyle={styles.headerTitle} />
      </View>
      <ScrollView contentContainerStyle={styles.content}>
        <View style={styles.intro}>
          <Text style={styles.title}>어떤 정보를 왜 입력하나요?</Text>
          <Text style={styles.subtitle}>내 정보와 신문을 받는 분의 정보를 구분해 안내해요.</Text>
        </View>

        {SECTIONS.map((section) => (
          <View key={section.title} style={styles.sectionWrap}>
            <View style={styles.section}>
              <Text style={styles.sectionTitle}>{section.title}</Text>
              {section.items.map(([label, text, strong]) => (
                <View key={label} style={styles.item}>
                  <Text style={styles.itemLabel}>{label}</Text>
                  <Text style={[styles.itemText, strong && styles.itemTextStrong]}>{text}</Text>
                </View>
              ))}
              {section.note ? (
                <View style={styles.note}>
                  <Text style={styles.noteText}>{section.note}</Text>
                </View>
              ) : null}
            </View>
            <View style={styles.divider} />
          </View>
        ))}

        <View style={styles.actions}>
          <Button title="개인정보 처리방침 보기" variant="secondary" onPress={openPolicy} />
          <Button title="확인" onPress={() => router.back()} />
        </View>
      </ScrollView>
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  screen: { flex: 1, backgroundColor: colors.background.page },
  headerWrap: { paddingHorizontal: 16, borderBottomWidth: hairline, borderBottomColor: colors.border.default },
  headerTitle: { fontFamily: fonts.medium, fontSize: 13, lineHeight: 20, marginLeft: 24 },
  content: { paddingHorizontal: 24, paddingTop: 24, paddingBottom: 16, gap: 28 },
  intro: { gap: 8 },
  title: { fontFamily: fonts.bold, fontSize: 26, lineHeight: 39, color: colors.text.primary },
  subtitle: { fontFamily: fonts.regular, fontSize: 15, lineHeight: 22, color: colors.text.secondary },
  sectionWrap: { gap: 28 },
  section: { gap: 16 },
  sectionTitle: { fontFamily: fonts.bold, fontSize: 18, lineHeight: 27, color: colors.text.primary },
  item: { gap: 16 },
  itemLabel: { fontFamily: fonts.bold, fontSize: 13, lineHeight: 19, color: colors.text.primary },
  itemText: { fontFamily: fonts.regular, fontSize: 15, lineHeight: 22, color: colors.text.secondary },
  itemTextStrong: { color: colors.text.primary },
  note: {
    borderLeftWidth: 2,
    borderLeftColor: colors.border.default,
    paddingLeft: 12,
    paddingRight: 10,
    paddingVertical: 10,
  },
  noteText: { fontFamily: fonts.regular, fontSize: 13, lineHeight: 19, color: colors.text.secondary },
  divider: { height: hairline, backgroundColor: colors.border.default },
  actions: { gap: 10, marginTop: -4 },
});
