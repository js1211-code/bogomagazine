import { Modal, Pressable, StyleSheet, Text, View } from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { colors, fonts, radius, typography } from '../theme';
import Button from './Button';

// Figma 선택 대화상자(0-2-b, 0-4-1-c, 0-4-4-a): 화면 아래쪽에 뜨는 카드. 위 버튼이 주요 행동, 아래는 글자 버튼.
// - cancelLabel 이 없으면 버튼 하나만 보인다 (만들기 실패의 [다시 시도])
// - onDismiss: 바깥이나 뒤로 가기를 눌렀을 때. 없으면 onConfirm 과 같다 ('계속 쓰기' 처럼 머무르는 동작일 때)
// - 설명 문구 왼쪽에 세로선 (사용자 조정, 동의 상세의 안내 박스와 같은 표현)
export default function ConfirmDialog({
  visible,
  title,
  message,
  confirmLabel,
  cancelLabel,
  onConfirm,
  onCancel,
  onDismiss,
}) {
  const insets = useSafeAreaInsets();
  const dismiss = onDismiss ?? onConfirm;
  return (
    <Modal transparent visible={visible} animationType="fade" statusBarTranslucent onRequestClose={dismiss}>
      <View style={[styles.overlay, { paddingBottom: Math.max(insets.bottom, 16) }]}>
        <Pressable style={StyleSheet.absoluteFill} onPress={dismiss} accessibilityLabel="닫기" />
        <View style={styles.card} accessibilityViewIsModal>
          <Text style={styles.title}>{title}</Text>
          <View style={styles.messageBox}>
            <Text style={styles.message}>{message}</Text>
          </View>
          <View style={styles.actions}>
            <Button title={confirmLabel} onPress={onConfirm} />
            {cancelLabel ? <Button title={cancelLabel} variant="quiet" onPress={onCancel} /> : null}
          </View>
        </View>
      </View>
    </Modal>
  );
}

const styles = StyleSheet.create({
  overlay: { flex: 1, justifyContent: 'flex-end', paddingHorizontal: 24, backgroundColor: colors.overlay },
  card: {
    backgroundColor: colors.background.paper,
    borderRadius: radius.modal,
    paddingHorizontal: 24,
    paddingTop: 24,
    paddingBottom: 16,
  },
  title: { fontFamily: fonts.bold, fontSize: 18, lineHeight: 34, letterSpacing: -0.4, color: colors.text.primary },
  messageBox: { marginTop: 18, borderLeftWidth: 2, borderLeftColor: colors.border.default, paddingLeft: 12 },
  message: { ...typography.bodySmall, color: colors.text.secondary },
  actions: { marginTop: 60, gap: 8 },
});
