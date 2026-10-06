import { router } from 'expo-router';
import { useState } from 'react';
import { KeyboardAvoidingView, Platform, ScrollView, StyleSheet, Text, View } from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import Button from '../../../components/Button';
import ConfirmDialog from '../../../components/ConfirmDialog';
import Divider from '../../../components/Divider';
import StepHeader from '../../../components/StepHeader';
import TextField from '../../../components/TextField';
import { recipientsOf, STEP_ROUTES, useCreateFamilyDraft } from '../../../context/CreateFamilyDraft';
import { useFamily } from '../../../context/FamilyContext';
import { colors, typography } from '../../../theme';
import { honorificFor } from '../../../utils/honorific';

const DEFAULT_TITLE = '보고잡지';

// Figma 0-4-3 이름 짓기 (3/3) + 0-4-4-a 만들기 실패, 명세서 FAM-01~03
// [가족방 만들기] → 만드는 중 화면 → 성공하면 완료·초대, 실패하면 이 화면으로 돌아와 확인창.
// 보내는 동안 버튼을 막고, 다시 시도해도 같은 요청 번호를 써서 가족방이 두 번 만들어지지 않게 한다.
export default function NamingScreen() {
  const { draft, update } = useCreateFamilyDraft();
  const { createGroup } = useFamily();
  const [saving, setSaving] = useState(false);
  const [failed, setFailed] = useState(false);

  const recipients = recipientsOf(draft);
  const honorific = honorificFor(draft.relationship, recipients.map((p) => p.gender));
  const canSubmit = draft.groupName.trim() !== '' && !saving;

  const submit = async () => {
    if (!canSubmit) return;
    setSaving(true);
    setFailed(false);
    router.push('/create/creating');
    try {
      await createGroup({
        name: draft.groupName.trim(),
        newsletterTitle: draft.newsletterTitle.trim() || DEFAULT_TITLE,
        relationship: draft.relationship,
        recipients: recipients.map((p) => ({ name: p.name.trim(), gender: p.gender })),
        recipientConsent: draft.recipientConsent,
        deliveryAddress: { ...draft.address, addressLine2: draft.address.addressLine2.trim() },
        requestKey: draft.requestKey,
      });
      router.replace('/create/done');
    } catch {
      router.back(); // 만드는 중 화면을 닫고 이 화면으로 (입력값은 그대로)
      setFailed(true);
    } finally {
      setSaving(false);
    }
  };

  return (
    <SafeAreaView style={styles.screen} edges={['top', 'bottom']}>
      <KeyboardAvoidingView style={styles.flex} behavior={Platform.OS === 'ios' ? 'padding' : undefined}>
        <StepHeader
          title="이름 짓기"
          step={3}
          total={3}
          onBack={() => router.back()}
          onStepPress={(n) => router.dismissTo(STEP_ROUTES[n])}
        />

        <ScrollView style={styles.flex} contentContainerStyle={styles.body} keyboardShouldPersistTaps="handled">
          <Text style={styles.title}>{'가족방과 신문에\n이름을 붙여 주세요'}</Text>
          <View style={styles.fields}>
            {/* FAM-02: 기본값 없음. 회색 예시는 기본값이 아니다 */}
            <TextField
              label="가족방 이름 · 필수"
              value={draft.groupName}
              onChangeText={(groupName) => update({ groupName })}
              placeholder="미자 여사네, 최가네 삼남매, 문경 지부 핫라인"
              helper="앱에서 우리 가족을 부르는 이름이에요. 신문에는 실리지 않아요."
            />
            <Divider />
            {/* FAM-03: 회색 기본값 '보고잡지', 비워 두면 '보고잡지' 로 만든다 */}
            <TextField
              label="신문 이름"
              value={draft.newsletterTitle}
              onChangeText={(newsletterTitle) => update({ newsletterTitle })}
              placeholder={DEFAULT_TITLE}
              helper={`${honorific}께 가는 신문 표지에 인쇄돼요.`}
              inputProps={{ returnKeyType: 'done' }}
            />
          </View>
        </ScrollView>

        <View style={styles.footer}>
          <Button title="가족방 만들기" onPress={submit} disabled={!canSubmit} />
        </View>
      </KeyboardAvoidingView>

      <ConfirmDialog
        visible={failed}
        title="가족방을 만들지 못했어요"
        message={'입력한 내용은 그대로예요.\n인터넷 연결을 확인하고 다시 시도해 주세요.'}
        confirmLabel="다시 시도"
        onConfirm={submit}
        onDismiss={() => setFailed(false)}
      />
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  screen: { flex: 1, backgroundColor: colors.background.page },
  flex: { flex: 1 },
  body: { paddingHorizontal: 24, paddingTop: 24, paddingBottom: 16, gap: 24 },
  title: { ...typography.screenHeading, color: colors.text.primary },
  // 설명이 붙은 입력칸 사이에는 구분선 (사용자 조정)
  fields: { gap: 24 },
  footer: { paddingHorizontal: 24, paddingVertical: 16, backgroundColor: colors.surface.default },
});
