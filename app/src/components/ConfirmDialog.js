import { Modal, Pressable, StyleSheet, Text, View } from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { colors, fonts, radius, typography } from '../theme';
import Button from './Button';

// Figma 선택 대화상자(0-2-b): 화면 아래쪽에 뜨는 카드. 위 버튼이 주요 행동, 아래는 글자 버튼.
export default function ConfirmDialog({
  visible,
  title,
  message,
  confirmLabel,
  cancelLabel,
  onConfirm,
  onCancel,
}) {
  const insets = useSafeAreaInsets();
  return (
    <Modal transparent visible={visible} animationType="fade" statusBarTranslucent onRequestClose={onConfirm}>
      <View style={[styles.overlay, { paddingBottom: Math.max(insets.bottom, 16) }]}>
        <Pressable style={StyleSheet.absoluteFill} onPress={onConfirm} accessibilityLabel="닫기" />
        <View style={styles.card} accessibilityViewIsModal>
          <Text style={styles.title}>{title}</Text>
          <Text style={styles.message}>{message}</Text>
          <View style={styles.actions}>
            <Button title={confirmLabel} onPress={onConfirm} />
            <Button title={cancelLabel} variant="quiet" onPress={onCancel} />
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
  message: { ...typography.bodySmall, color: colors.text.secondary, marginTop: 18 },
  actions: { marginTop: 60, gap: 8 },
});
