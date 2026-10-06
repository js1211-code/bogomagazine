import { useEffect, useMemo, useRef, useState } from 'react';
import { Animated, Easing, Modal, Pressable, StyleSheet, Text, useWindowDimensions, View } from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { colors, fonts, hairline, sheet } from '../theme';

// 아래에서 올라오는 시트. 라이브러리 없이 React Native 기본 Modal + Animated 로 만든다.
// 여백·둥글기는 theme/layout.js 의 sheet 규격을 따른다. 새 시트는 아래처럼 만든다:
//
//   <BottomSheet visible={...} onClose={...} title="제목" showHandle>
//     ...내용...
//     <SheetDivider />          ← 구분선 (위아래 여백 포함)
//     <SheetActions>            ← 맨 아래 버튼 영역 (위 여백 포함)
//       <Button ... />
//     </SheetActions>
//   </BottomSheet>
//
// - 뒤의 어두운 막이나 손잡이를 누르면 onClose
// - 닫는 애니메이션이 끝날 때까지는 화면에 남겨 둔다 (mounted)
// - onHeightChange: 시트 전체 높이(아래 안전 영역 포함)를 알려 준다. 뒤 화면이 시트 위 공간에 맞춰 움직일 때 쓴다.
export default function BottomSheet({
  visible,
  onClose,
  title,
  children,
  backgroundColor = colors.surface.default,
  showHandle = false,
  onHeightChange,
}) {
  const { height } = useWindowDimensions();
  const insets = useSafeAreaInsets();
  const [mounted, setMounted] = useState(visible);
  const progress = useRef(new Animated.Value(0)).current;

  useEffect(() => {
    if (visible) {
      setMounted(true);
      Animated.timing(progress, {
        toValue: 1,
        duration: 250,
        easing: Easing.out(Easing.cubic),
        useNativeDriver: true,
      }).start();
    } else {
      Animated.timing(progress, {
        toValue: 0,
        duration: 200,
        easing: Easing.in(Easing.cubic),
        useNativeDriver: true,
      }).start(({ finished }) => {
        if (finished) setMounted(false);
      });
    }
  }, [visible, progress]);

  // 다시 그려질 때마다 새로 만들면 진행 중인 애니메이션과 연결이 끊기므로 한 번만 만든다
  const translateY = useMemo(
    () => progress.interpolate({ inputRange: [0, 1], outputRange: [height, 0] }),
    [progress, height],
  );

  if (!mounted) return null;

  return (
    <Modal transparent visible animationType="none" statusBarTranslucent onRequestClose={onClose}>
      <Animated.View style={[styles.scrim, { opacity: progress }]}>
        <Pressable
          style={StyleSheet.absoluteFill}
          onPress={onClose}
          accessibilityRole="button"
          accessibilityLabel="닫기"
        />
      </Animated.View>
      <Animated.View
        onLayout={(e) => onHeightChange?.(e.nativeEvent.layout.height)}
        style={[
          styles.sheet,
          { backgroundColor, paddingBottom: insets.bottom + sheet.paddingBottom, transform: [{ translateY }] },
        ]}
      >
        {showHandle ? (
          <Pressable
            onPress={onClose}
            accessibilityRole="button"
            accessibilityLabel="시트 닫기"
            // 막대가 작아서 누르기 쉽도록 보이는 크기는 그대로 두고 누를 수 있는 범위만 넓힌다
            hitSlop={{ top: 20, bottom: 16, left: 120, right: 120 }}
            style={styles.handleTouch}
          >
            <View style={styles.handle} />
          </Pressable>
        ) : null}
        {title ? <Text style={styles.title}>{title}</Text> : null}
        {children}
      </Animated.View>
    </Modal>
  );
}

// 시트 안 구분선 (위아래 여백 포함)
export function SheetDivider() {
  return <View style={styles.divider} />;
}

// 시트 맨 아래 버튼 영역 (위 여백 포함)
export function SheetActions({ children }) {
  return <View style={styles.actions}>{children}</View>;
}

const styles = StyleSheet.create({
  scrim: { ...StyleSheet.absoluteFillObject, backgroundColor: colors.overlay },
  sheet: {
    position: 'absolute',
    left: 0,
    right: 0,
    bottom: 0,
    paddingHorizontal: sheet.paddingHorizontal,
    paddingTop: sheet.paddingTop,
    borderTopLeftRadius: sheet.radius,
    borderTopRightRadius: sheet.radius,
  },
  handleTouch: { alignSelf: 'center', marginBottom: sheet.handleGap },
  handle: {
    width: sheet.handleWidth,
    height: sheet.handleHeight,
    borderRadius: sheet.handleHeight / 2,
    backgroundColor: colors.handle,
  },
  title: { fontFamily: fonts.bold, fontSize: 20, lineHeight: 30, color: colors.text.primary, marginBottom: sheet.titleGap },
  divider: { height: hairline, backgroundColor: colors.border.default, marginVertical: sheet.dividerGap },
  actions: { marginTop: sheet.actionGap, gap: 8 },
});
