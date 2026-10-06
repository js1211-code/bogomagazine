import { Alert, StyleSheet, Text, View } from 'react-native';
import { colors, fonts, typography } from '../theme';
import BottomSheet, { SheetActions } from './BottomSheet';
import Button from './Button';

// Figma 0-4-1-b 받는 분 정보 동의 내용 시트 (명세서 RCV-03)
// [동의하기] 를 누르면 동의 칸이 체크된 채로 0-4-1 로 돌아간다.
// Figma 의 '최종 동의 문안은 검토 후 확정해요.' 는 내부 메모라 넣지 않았다.
// TODO(O-40): 보관 기간과 법적 문구가 확정되면 바꾼다.
const ROWS = [
  ['항목', '이름, 성별, 배송지'],
  ['목적', '신문 제작과 배송, 호칭 적용'],
  ['보관 기간', '미결 · 법적 문구 검토 후 확정'],
  ['동의하지 않으면', '가족방을 만들 수 없어요.'],
];

export default function RecipientConsentSheet({ visible, onClose, onAgree }) {
  const openPolicy = () => {
    // TODO(O-40): 개인정보 처리방침 웹 페이지 주소가 정해지면 인앱 브라우저로 연다
    Alert.alert('준비 중이에요', '개인정보 처리방침은 문구가 확정되면 볼 수 있어요.');
  };

  return (
    <BottomSheet visible={visible} onClose={onClose} title="받는 분 정보는 이렇게 써요" showHandle>
      <View style={styles.rows}>
        {ROWS.map(([label, value]) => (
          <View key={label} style={styles.row}>
            <Text style={styles.label}>{label}</Text>
            <Text style={styles.value}>{value}</Text>
          </View>
        ))}
        <Text style={styles.note}>입력하기 전에 받는 분께 알리고 동의를 받아 주세요.</Text>
      </View>
      <SheetActions>
        <Button title="동의하기" onPress={onAgree} />
        <Button title="개인정보 처리방침 보기" variant="quiet" onPress={openPolicy} />
      </SheetActions>
    </BottomSheet>
  );
}

const styles = StyleSheet.create({
  rows: { gap: 16 },
  row: { gap: 6 },
  label: { fontFamily: fonts.bold, fontSize: 14, lineHeight: 21, color: colors.action.primary },
  value: { fontFamily: fonts.regular, fontSize: 15, lineHeight: 22, color: colors.text.primary },
  note: { ...typography.label, fontFamily: fonts.regular, color: colors.text.secondary },
});
