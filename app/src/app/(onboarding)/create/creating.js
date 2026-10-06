import { useCallback, useEffect, useRef, useState } from 'react';
import { AccessibilityInfo, Animated, Easing, StyleSheet, Text, View } from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import BrandHeader from '../../../components/BrandHeader';
import { NewspaperIcon } from '../../../components/LineIcons';
import { useBackHandler } from '../../../hooks/useBackHandler';
import { colors, fonts, hairline } from '../../../theme';

const BAR_FILL = 72; // Figma: 채워진 막대 너비

// Figma 0-4-4 만드는 중. 요청은 이름 짓기 화면이 보내고, 이 화면은 기다리는 동안 보여 주기만 한다.
// 다시 누르거나 뒤로 갈 수 없게 막는다 (중복 요청 방지, FAM-01 ①).
export default function CreatingScreen() {
  const [trackWidth, setTrackWidth] = useState(0);
  const slide = useRef(new Animated.Value(0)).current;

  // 안드로이드 뒤로 가기 버튼 막기 (iOS 밀어서 뒤로 가기는 _layout 에서 막았다)
  useBackHandler(useCallback(() => true, []));

  // 막대가 왼쪽에서 오른쪽으로 계속 지나간다. '동작 줄이기'를 켠 사람에게는 멈춰 있는 막대를 보여 준다.
  useEffect(() => {
    let loop;
    AccessibilityInfo.isReduceMotionEnabled().then((reduceMotion) => {
      if (reduceMotion) return;
      loop = Animated.loop(
        Animated.timing(slide, { toValue: 1, duration: 1200, easing: Easing.inOut(Easing.quad), useNativeDriver: true }),
      );
      loop.start();
    });
    return () => loop?.stop();
  }, [slide]);

  const translateX = slide.interpolate({ inputRange: [0, 1], outputRange: [-BAR_FILL, trackWidth] });

  return (
    <SafeAreaView style={styles.screen} edges={['top', 'bottom']}>
      <BrandHeader />
      <View style={styles.body}>
        <View style={styles.hero} accessibilityLiveRegion="polite">
          <NewspaperIcon />
          <Text style={styles.title}>{'가족의 이야기를\n한 장에 담고 있어요.'}</Text>
          <Text style={styles.subtitle}>다 되면 바로 알려 드려요.</Text>
          <View
            style={styles.track}
            onLayout={(e) => setTrackWidth(e.nativeEvent.layout.width)}
            accessibilityRole="progressbar"
            accessibilityLabel="가족방을 만드는 중"
          >
            <Animated.View style={[styles.fill, { transform: [{ translateX }] }]} />
          </View>
        </View>
        <View style={styles.divider} />
      </View>
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  screen: { flex: 1, backgroundColor: colors.background.page },
  body: { paddingHorizontal: 24, paddingTop: 24 },
  hero: { alignItems: 'center', paddingVertical: 32, gap: 24 },
  title: { fontFamily: fonts.bold, fontSize: 26, lineHeight: 39, color: colors.text.primary, textAlign: 'center' },
  subtitle: { fontFamily: fonts.regular, fontSize: 15, lineHeight: 22, color: colors.text.secondary, textAlign: 'center' },
  track: { alignSelf: 'stretch', height: 3, backgroundColor: colors.border.default, overflow: 'hidden' },
  fill: { width: BAR_FILL, height: 3, backgroundColor: colors.action.primary },
  divider: { height: hairline, backgroundColor: colors.border.default },
});
