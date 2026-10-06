import { useCallback, useState } from 'react';
import { Alert, KeyboardAvoidingView, Platform, ScrollView, StyleSheet, Text, View } from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import BirthdayPickerSheet from '../../components/BirthdayPickerSheet';
import Button from '../../components/Button';
import ConfirmDialog from '../../components/ConfirmDialog';
import Divider from '../../components/Divider';
import ScreenHeader from '../../components/ScreenHeader';
import TextField from '../../components/TextField';
import { useAuth } from '../../context/AuthContext';
import { useBackHandler } from '../../hooks/useBackHandler';
import { colors, typography } from '../../theme';

// Figma 0-2 이름 입력 + 0-2-a 생일 선택 시트 + 0-2-b 나가기 확인 (명세서 PRF-01)
// - 이름은 필수. 카카오는 닉네임이 미리 채워지고, 애플은 빈칸으로 시작한다.
// - 생일은 월·일만, 건너뛸 수 있다.
// - 뒤로 가기: 입력한 게 있으면 확인창, 빈칸이면 바로 로그인 화면으로 (입력 내용은 저장하지 않음)
export default function NameScreen() {
  const { session, signOut, completeProfile } = useAuth();
  const prefilledName = session?.user?.name ?? '';
  const showKakaoNote = session?.provider === 'kakao' && prefilledName !== '';

  const [name, setName] = useState(prefilledName);
  const [birthday, setBirthday] = useState(null); // { month, day } | null
  const [pickerOpen, setPickerOpen] = useState(false);
  const [leaveOpen, setLeaveOpen] = useState(false);
  const [saving, setSaving] = useState(false);

  const trimmedName = name.trim();
  const hasInput = trimmedName !== '' || birthday !== null;

  const requestLeave = useCallback(() => {
    if (hasInput) setLeaveOpen(true);
    else signOut();
    return true; // 안드로이드 뒤로 가기 버튼의 기본 동작(앱 종료)을 막는다
  }, [hasInput, signOut]);

  useBackHandler(requestLeave);

  const submit = async () => {
    if (!trimmedName || saving) return;
    setSaving(true);
    try {
      await completeProfile({
        name: trimmedName,
        birthMonth: birthday?.month ?? null,
        birthDay: birthday?.day ?? null,
      });
      // 성공하면 _layout 의 guard 가 다음 화면으로 보낸다
    } catch {
      setSaving(false);
      Alert.alert('저장하지 못했어요', '입력한 내용은 그대로예요. 인터넷 연결을 확인하고 다시 시도해 주세요.');
    }
  };

  return (
    <SafeAreaView style={styles.screen} edges={['top', 'bottom']}>
      <KeyboardAvoidingView style={styles.flex} behavior={Platform.OS === 'ios' ? 'padding' : undefined}>
        <View style={styles.headerWrap}>
          <ScreenHeader title="내 정보" onBack={requestLeave} />
        </View>

        <ScrollView style={styles.flex} contentContainerStyle={styles.body} keyboardShouldPersistTaps="handled">
          <View style={styles.intro}>
            <Text style={styles.title}>신문에 실릴 이름</Text>
            <Text style={styles.subtitle}>받는 분이 알아볼 수 있는 이름으로 적어 주세요.</Text>
          </View>
          <TextField
            label="이름"
            value={name}
            onChangeText={setName}
            placeholder="이름을 입력해주세요"
            helper="신문에는 '손녀 강보민'처럼 관계와 함께 실려요."
            inputProps={{ returnKeyType: 'done', autoComplete: 'name', textContentType: 'name' }}
          />
          <Divider />
          <TextField
            label="생일 (선택)"
            value={birthday ? `${birthday.month}월 ${birthday.day}일` : ''}
            placeholder="예) 3월 15일"
            helper="생일이 다가오면 신문에 실려요."
            onPress={() => setPickerOpen(true)}
          />
        </ScrollView>

        <View style={styles.footer}>
          {showKakaoNote ? <Text style={styles.note}>카카오에 등록된 이름을 가져왔어요. 다르면 고쳐 주세요.</Text> : null}
          <Button title="다음" onPress={submit} disabled={!trimmedName || saving} />
        </View>
      </KeyboardAvoidingView>

      <BirthdayPickerSheet
        visible={pickerOpen}
        initial={birthday}
        onClose={() => setPickerOpen(false)}
        onSelect={(value) => {
          setBirthday(value);
          setPickerOpen(false);
        }}
      />
      <ConfirmDialog
        visible={leaveOpen}
        title="입력한 내용이 사라져요"
        message={'지금 나가면 입력한 이름과 생일이\n저장되지 않아요.'}
        confirmLabel="계속 쓰기"
        cancelLabel="나가기"
        onConfirm={() => setLeaveOpen(false)}
        onCancel={() => {
          setLeaveOpen(false);
          signOut();
        }}
      />
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  screen: { flex: 1, backgroundColor: colors.background.page },
  flex: { flex: 1 },
  headerWrap: { paddingHorizontal: 24 },
  body: { paddingHorizontal: 24, paddingTop: 24, paddingBottom: 16, gap: 24 },
  intro: { gap: 16 },
  title: { ...typography.screenHeading, color: colors.text.primary },
  subtitle: { ...typography.bodySmall, color: colors.text.secondary },
  footer: { paddingHorizontal: 24, paddingVertical: 16, gap: 8, backgroundColor: colors.surface.default },
  note: { ...typography.caption, color: colors.text.secondary, textAlign: 'center' },
});
