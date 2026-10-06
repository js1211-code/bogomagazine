import { router } from 'expo-router';
import { useState } from 'react';
import { KeyboardAvoidingView, Platform, ScrollView, StyleSheet, Text, View } from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import AddressSearchModal from '../../../components/AddressSearchModal';
import Button from '../../../components/Button';
import StepHeader from '../../../components/StepHeader';
import TextField from '../../../components/TextField';
import { STEP_ROUTES, useCreateFamilyDraft } from '../../../context/CreateFamilyDraft';
import { colors, typography } from '../../../theme';

// Figma 0-4-2 배송지 (2/3), 명세서 RCV-02
// 주소 칸을 누르면 주소 찾기(우편번호 검색)가 열리고, 고른 주소가 채워진다. 상세 주소는 직접 입력.
export default function AddressScreen() {
  const { draft, update } = useCreateFamilyDraft();
  const { address } = draft;
  const [searchOpen, setSearchOpen] = useState(false);

  const setAddress = (patch) => update({ address: { ...address, ...patch } });
  const canProceed = address.addressLine1 !== '' && address.addressLine2.trim() !== '';

  return (
    <SafeAreaView style={styles.screen} edges={['top', 'bottom']}>
      <KeyboardAvoidingView style={styles.flex} behavior={Platform.OS === 'ios' ? 'padding' : undefined}>
        <StepHeader
          title="배송지"
          step={2}
          total={3}
          onBack={() => router.back()}
          onStepPress={(n) => router.dismissTo(STEP_ROUTES[n])}
        />

        <ScrollView style={styles.flex} contentContainerStyle={styles.body} keyboardShouldPersistTaps="handled">
          <View style={styles.intro}>
            <Text style={styles.title}>신문을 어디로 보낼까요?</Text>
            <Text style={styles.subtitle}>주소는 나중에 바꿀 수 있어요.</Text>
          </View>
          <View style={styles.fields}>
            <TextField
              label="주소 · 필수"
              value={address.addressLine1 ? `[${address.postalCode}] ${address.addressLine1}` : ''}
              placeholder="눌러서 주소 찾기"
              onPress={() => setSearchOpen(true)}
            />
            <TextField
              label="상세 주소 · 필수"
              value={address.addressLine2}
              onChangeText={(addressLine2) => setAddress({ addressLine2 })}
              placeholder="동, 호수 등 상세 주소"
              inputProps={{ returnKeyType: 'done' }}
            />
          </View>
        </ScrollView>

        <View style={styles.footer}>
          <Button title="다음" onPress={() => router.push('/create/naming')} disabled={!canProceed} />
        </View>
      </KeyboardAvoidingView>

      <AddressSearchModal
        visible={searchOpen}
        onClose={() => setSearchOpen(false)}
        onSelect={({ postalCode, addressLine1 }) => {
          setAddress({ postalCode, addressLine1 });
          setSearchOpen(false);
        }}
      />
    </SafeAreaView>
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
  footer: { paddingHorizontal: 24, paddingVertical: 16, backgroundColor: colors.surface.default },
});
