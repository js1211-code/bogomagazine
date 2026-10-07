import { router } from 'expo-router';
import { useCallback, useState } from 'react';
import { KeyboardAvoidingView, Platform, Pressable, ScrollView, StyleSheet, Text, View } from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import Button from '../../../components/Button';
import CheckboxRow from '../../../components/CheckboxRow';
import ChoiceChips from '../../../components/ChoiceChips';
import ChoiceGridSheet from '../../../components/ChoiceGridSheet';
import ConfirmDialog from '../../../components/ConfirmDialog';
import RecipientConsentSheet from '../../../components/RecipientConsentSheet';
import SegmentedControl from '../../../components/SegmentedControl';
import StepHeader from '../../../components/StepHeader';
import TextField from '../../../components/TextField';
import { isPersonComplete, recipientsOf, useCreateFamilyDraft } from '../../../context/CreateFamilyDraft';
import { useBackHandler } from '../../../hooks/useBackHandler';
import { colors, fonts, typography } from '../../../theme';
import { honorificFor, RELATIONSHIPS, withJosa } from '../../../utils/honorific';

// Figma 0-4-1 받는 분 정보 (1/3) + 0-4-1-a 관계 선택 + 0-4-1-b 동의 내용 + 0-4-1-c 나가기 확인
// 명세서 FAM-01, RCV-01, RCV-03, PRF-02:
// - 한 분 / 부부(두 분). 두 분이면 한 분씩 오가며 이름·성별을 입력하고, 관계·동의는 아래에서 한 번만.
// - 관계는 고르기 전에는 빈 상태, 고르기 전에는 다음으로 갈 수 없다.
// - 뒤로: 입력한 게 있으면 확인창, 빈칸이면 바로 가족방 없음 화면으로. 입력 내용은 저장하지 않는다.
// 디자인 조정(사용자 결정): 성별은 시트 대신 화면 안 흰 칸 두 개(고르면 연두 상자), 두 분은 밑줄 탭으로 오간다.
const GENDERS = [
  { value: 'female', label: '여성' },
  { value: 'male', label: '남성' },
];

export default function RecipientScreen() {
  const { draft, update, updatePerson } = useCreateFamilyDraft();
  const [sheet, setSheet] = useState(null); // 'relationship' | 'consent' | null
  const [leaveOpen, setLeaveOpen] = useState(false);

  const isCouple = draft.count === 'couple';
  const index = isCouple ? draft.activeIndex : 0;
  const person = draft.people[index];
  const recipients = recipientsOf(draft);
  const allPeopleComplete = recipients.every(isPersonComplete);
  const canProceed = allPeopleComplete && draft.relationship !== null && draft.recipientConsent;

  // 두 분일 때: 지금 분을 다 썼고 다른 분이 남았으면 [다음]은 다른 분으로 넘어간다
  const otherIndex = index === 0 ? 1 : 0;
  const goesToOtherPerson =
    isCouple && isPersonComplete(person) && !isPersonComplete(draft.people[otherIndex]);
  const nextEnabled = canProceed || goesToOtherPerson;

  const hasInput =
    draft.people.some((p) => p.name.trim() !== '' || p.gender !== null) ||
    draft.relationship !== null ||
    draft.recipientConsent;

  const requestLeave = useCallback(() => {
    if (hasInput) setLeaveOpen(true);
    else router.back();
    return true;
  }, [hasInput]);

  useBackHandler(requestLeave);

  const next = () => {
    if (goesToOtherPerson) {
      update({ activeIndex: otherIndex });
      return;
    }
    if (canProceed) router.push('/create/address');
  };

  // 관계 시트 설명: '손녀를 선택하면 이분은 할머니예요.' (TTL-01 호칭 미리보기)
  const previewRelationship = draft.relationship ?? '손녀';
  const honorific = honorificFor(previewRelationship, recipients.map((p) => p.gender));
  const relationshipDescription = `${withJosa(previewRelationship, '을/를')} 선택하면 ${
    isCouple ? '두 분은' : '이분은'
  } ${withJosa(honorific, '이에요/예요')}.`;

  return (
    <SafeAreaView style={styles.screen} edges={['top', 'bottom']}>
      <KeyboardAvoidingView style={styles.flex} behavior={Platform.OS === 'ios' ? 'padding' : undefined}>
        <StepHeader title="받는 분" step={1} total={3} onBack={requestLeave} />

        <ScrollView style={styles.flex} contentContainerStyle={styles.body} keyboardShouldPersistTaps="handled">
          <View style={styles.intro}>
            <Text style={styles.title}>누구에게 신문을 보낼까요?</Text>
            <Text style={styles.subtitle}>받는 분은 가입 없이 신문만 받아요.</Text>
          </View>

          <SegmentedControl
            options={[
              { value: 'single', label: '한 분' },
              { value: 'couple', label: '두 분' },
            ]}
            value={draft.count}
            onChange={(count) => update({ count, activeIndex: 0 })}
          />

          <View style={styles.fields}>
            {isCouple ? (
              <PersonTabs people={draft.people} activeIndex={index} onChange={(i) => update({ activeIndex: i })} />
            ) : null}
            <TextField
              label="이름 · 필수"
              value={person.name}
              onChangeText={(name) => updatePerson(index, { name })}
              placeholder="이름을 입력해주세요"
              inputProps={{ returnKeyType: 'done' }}
            />
            <View style={styles.genderGroup}>
              <Text style={styles.fieldLabel}>성별 · 필수</Text>
              <ChoiceChips
                options={GENDERS}
                value={person.gender}
                onChange={(gender) => updatePerson(index, { gender })}
              />
            </View>
          </View>

          <View style={[styles.fields, isCouple && styles.shared]}>
            <TextField
              label="신문 받는 분과 나의 관계 · 필수"
              value={draft.relationship ?? ''}
              placeholder="관계 선택"
              select
              onPress={() => setSheet('relationship')}
            />
            <CheckboxRow
              compact
              label="[필수] 받는 분 정보 입력 동의"
              checked={draft.recipientConsent}
              onToggle={() => update({ recipientConsent: !draft.recipientConsent })}
              onView={() => setSheet('consent')}
            />
          </View>
        </ScrollView>

        <View style={styles.footer}>
          <Button title="다음" onPress={next} disabled={!nextEnabled} />
        </View>
      </KeyboardAvoidingView>

      <ChoiceGridSheet
        visible={sheet === 'relationship'}
        onClose={() => setSheet(null)}
        title="신문 받는 분과 나의 관계"
        description={relationshipDescription}
        options={RELATIONSHIPS}
        value={draft.relationship}
        onSelect={(relationship) => {
          update({ relationship });
          setSheet(null);
        }}
      />
      <RecipientConsentSheet
        visible={sheet === 'consent'}
        onClose={() => setSheet(null)}
        onAgree={() => {
          update({ recipientConsent: true });
          setSheet(null);
        }}
      />
      <ConfirmDialog
        visible={leaveOpen}
        title="입력한 내용이 사라져요"
        message={'지금 나가면 입력한 받는 분 정보가\n저장되지 않아요.'}
        confirmLabel="계속 쓰기"
        cancelLabel="나가기"
        onConfirm={() => setLeaveOpen(false)}
        onCancel={() => {
          setLeaveOpen(false);
          router.back();
        }}
      />
    </SafeAreaView>
  );
}

// 두 분일 때 '첫 번째 분 | 두 번째 분' 밑줄 탭. 이름을 쓰면 이름으로 바뀌고, 다 쓰면 ✓ 가 붙는다.
function PersonTabs({ people, activeIndex, onChange }) {
  return (
    <View style={styles.tabs} accessibilityRole="tablist">
      {people.map((p, i) => {
        const active = i === activeIndex;
        const complete = isPersonComplete(p);
        const name = p.name.trim() || (i === 0 ? '첫 번째 분' : '두 번째 분');
        return (
          <Pressable
            key={i}
            accessibilityRole="tab"
            accessibilityState={{ selected: active }}
            accessibilityLabel={`${name}${complete ? ', 입력 완료' : ''}`}
            onPress={() => onChange(i)}
            style={styles.tab}
          >
            <Text style={[styles.tabText, active && styles.tabTextActive]} numberOfLines={1}>
              {name}
              {complete ? <Text style={styles.tabCheck}> ✓</Text> : null}
            </Text>
            <View style={[styles.tabLine, active && styles.tabLineActive]} />
          </Pressable>
        );
      })}
    </View>
  );
}

const styles = StyleSheet.create({
  screen: { flex: 1, backgroundColor: colors.background.page },
  flex: { flex: 1 },
  body: { paddingHorizontal: 24, paddingTop: 24, paddingBottom: 16, gap: 24 },
  intro: { gap: 16 },
  title: { ...typography.screenHeading, color: colors.text.primary },
  subtitle: { ...typography.bodySmall, color: colors.text.secondary },
  fields: { gap: 8 },
  fieldLabel: { ...typography.label, color: colors.text.secondary },
  genderGroup: { gap: 8, marginTop: 4 },
  // 두 분: 받는 분 입력과 관계·동의 사이를 선으로 나눈다 (관계·동의는 두 분 공통으로 한 번)
  shared: { borderTopWidth: 1, borderTopColor: colors.border.default, paddingTop: 24 },
  tabs: { flexDirection: 'row', gap: 8, marginBottom: 8 },
  tab: { flex: 1, paddingTop: 4, gap: 10 },
  tabText: { fontFamily: fonts.medium, fontSize: 16, lineHeight: 24, color: colors.text.secondary, textAlign: 'center' },
  tabTextActive: { color: colors.text.primary },
  tabCheck: { color: colors.action.primary },
  tabLine: { height: 2, backgroundColor: colors.border.default },
  tabLineActive: { backgroundColor: colors.action.primary },
  footer: { paddingHorizontal: 24, paddingVertical: 16, backgroundColor: colors.surface.default },
});
