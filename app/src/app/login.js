import { router, useFocusEffect } from 'expo-router';
import { useCallback, useEffect, useRef, useState } from 'react';
import {
  AccessibilityInfo,
  Alert,
  Animated,
  Easing,
  Pressable,
  StyleSheet,
  Text,
  useWindowDimensions,
  View,
} from 'react-native';
import { SafeAreaView, useSafeAreaInsets } from 'react-native-safe-area-context';
import { ConsentRequiredError } from '../auth/authService';
import Button from '../components/Button';
import ConsentSheet from '../components/ConsentSheet';
import { useAuth } from '../context/AuthContext';
import { colors, fonts, radius, typography } from '../theme';

const kakaoSymbol = require('../../assets/login/kakao-symbol.png');
const appleLogo = require('../../assets/login/apple-logo.png');

// Figma 0-1 로그인 + 0-1-c 약관 동의 시트 (명세서 ACC-01~03)
// - 약관 카드를 누르면 언제든 동의 시트가 열린다.
// - 동의 없이 로그인했는데 새 계정이면 시트가 열리고, 동의하면 그 로그인을 이어서 진행한다.
export default function LoginScreen() {
  const { signIn } = useAuth();
  const [consent, setConsent] = useState(null);
  const [sheetOpen, setSheetOpen] = useState(false);
  const [busy, setBusy] = useState(false);
  const pendingProvider = useRef(null); // 동의가 필요해서 멈춘 로그인
  const reopenSheetOnFocus = useRef(false); // 동의 상세를 보고 돌아오면 시트를 다시 연다

  // 등장 모션: 소제목 → 제호 → 안내 문구 순서로 하나씩 서서히 나타난다.
  // 기기에서 '동작 줄이기'를 켠 사람에게는 모션 없이 바로 보여 준다.
  const heroFade = useRef([0, 1, 2].map(() => new Animated.Value(0))).current;
  useEffect(() => {
    let cancelled = false;
    AccessibilityInfo.isReduceMotionEnabled().then((reduceMotion) => {
      if (cancelled) return;
      if (reduceMotion) {
        heroFade.forEach((v) => v.setValue(1));
        return;
      }
      Animated.stagger(
        250, // 다음 줄이 시작되기까지의 간격
        heroFade.map((v) =>
          Animated.timing(v, { toValue: 1, duration: 600, easing: Easing.out(Easing.quad), useNativeDriver: true }),
        ),
      ).start();
    });
    return () => {
      cancelled = true;
    };
  }, [heroFade]);

  // 제호 묶음 위치: 평소에는 약관 카드 위 공간의 가운데, 시트가 열리면 시트 위 공간의 가운데로 옮긴다
  const { height: windowHeight } = useWindowDimensions();
  const insets = useSafeAreaInsets();
  const [heroArea, setHeroArea] = useState(null); // 제호 묶음이 놓인 공간 { y, height }
  const [sheetHeight, setSheetHeight] = useState(0);
  const heroShift = useRef(new Animated.Value(0)).current;

  useEffect(() => {
    let toValue = 0;
    if (sheetOpen && heroArea && sheetHeight) {
      const targetCenter = (insets.top + windowHeight - sheetHeight) / 2; // 상태 표시줄 아래 ~ 시트 위
      const currentCenter = heroArea.y + heroArea.height / 2;
      toValue = targetCenter - currentCenter;
    }
    // 시트가 올라오고 내려가는 속도와 맞춘다
    Animated.timing(heroShift, {
      toValue,
      duration: sheetOpen ? 250 : 200,
      easing: sheetOpen ? Easing.out(Easing.cubic) : Easing.in(Easing.cubic),
      useNativeDriver: true,
    }).start();
  }, [sheetOpen, heroArea, sheetHeight, windowHeight, insets.top, heroShift]);

  useFocusEffect(
    useCallback(() => {
      if (reopenSheetOnFocus.current) {
        reopenSheetOnFocus.current = false;
        setSheetOpen(true);
      }
    }, []),
  );

  const login = async (provider, consentToSend = consent) => {
    if (busy) return;
    setBusy(true);
    try {
      await signIn(provider, consentToSend);
      // 성공하면 _layout 의 guard 가 알아서 다음 화면으로 보낸다
    } catch (e) {
      if (e instanceof ConsentRequiredError) {
        pendingProvider.current = provider;
        setSheetOpen(true);
      } else {
        // TODO: Figma 0-1-b 로그인 복구 화면은 실제 로그인(2단계)을 붙일 때 구현
        Alert.alert('로그인하지 못했어요', '잠시 후 다시 시도해 주세요.');
      }
    } finally {
      setBusy(false);
    }
  };

  const handleConsent = (nextConsent) => {
    setConsent(nextConsent);
    setSheetOpen(false);
    if (pendingProvider.current) {
      const provider = pendingProvider.current;
      pendingProvider.current = null;
      login(provider, nextConsent);
    }
  };

  const closeSheet = () => {
    setSheetOpen(false);
    pendingProvider.current = null;
  };

  const viewTerm = (key) => {
    if (key === 'privacy') {
      reopenSheetOnFocus.current = true;
      setSheetOpen(false);
      router.push('/terms-detail');
      return;
    }
    // TODO(O-40): 이용약관 전문(웹 페이지)과 나머지 항목의 상세 내용은 법적 문구가 확정되면 연결한다
    Alert.alert('준비 중이에요', '약관 전문은 문구가 확정되면 볼 수 있어요.');
  };

  return (
    <SafeAreaView style={styles.screen}>
      <View
        style={styles.heroArea}
        onLayout={(e) => setHeroArea({ y: e.nativeEvent.layout.y, height: e.nativeEvent.layout.height })}
      >
        <Animated.View style={[styles.hero, { transform: [{ translateY: heroShift }] }]}>
          <Animated.Text style={[styles.eyebrow, { opacity: heroFade[0] }]}>떨어져 있어도, 일상은 함께</Animated.Text>
          <Animated.Text style={[styles.title, { opacity: heroFade[1] }]}>보고잡지</Animated.Text>
          <Animated.Text style={[styles.tagline, { opacity: heroFade[2] }]}>
            {'우리 가족 소식이\n한 장의 신문이 되어 배달돼요'}
          </Animated.Text>
        </Animated.View>
      </View>

      <View style={styles.actions}>
        <Pressable
          accessibilityRole="button"
          accessibilityLabel="약관 동의 열기"
          onPress={() => setSheetOpen(true)}
          style={styles.consentCard}
        >
          <Text style={styles.consentTitle}>{'서비스 이용을 위해\n약관에 동의해주세요.'}</Text>
          <View style={styles.consentRow}>
            <Text style={styles.consentSummary}>필수 약관 3개 · 선택 약관 1개</Text>
            <View style={styles.chevronRight} />
          </View>
        </Pressable>
        {/* TODO: 로고는 시안용 근사치. 카카오·애플 공식 배포 파일로 교체할 것 (Figma 주석) */}
        <Button title="카카오 로그인" variant="kakao" icon={kakaoSymbol} onPress={() => login('kakao')} />
        <Button title="Apple로 로그인" variant="apple" icon={appleLogo} onPress={() => login('apple')} />
      </View>

      <ConsentSheet
        visible={sheetOpen}
        consent={consent}
        onClose={closeSheet}
        onConfirm={handleConsent}
        onViewTerm={viewTerm}
        onHeightChange={setSheetHeight}
      />
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  screen: { flex: 1, backgroundColor: colors.background.page, paddingHorizontal: 24 },
  // 약관 카드 위의 남는 공간을 모두 차지하고, 그 가운데에 제호 묶음을 놓는다
  heroArea: { flex: 1, justifyContent: 'center' },
  hero: { alignItems: 'center' },
  eyebrow: { ...typography.label, color: colors.text.editorial },
  title: { ...typography.brandTitle, color: colors.text.primary, marginTop: 8 },
  tagline: { ...typography.body, color: colors.text.secondary, textAlign: 'center', marginTop: 22 },
  actions: { gap: 16, paddingBottom: 16 },
  consentCard: {
    backgroundColor: colors.surface.subtle,
    borderRadius: radius.large,
    paddingHorizontal: 24,
    paddingVertical: 16,
    gap: 8,
  },
  consentTitle: { fontFamily: fonts.medium, fontSize: 15, lineHeight: 22, color: colors.text.primary },
  consentRow: { flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between' },
  consentSummary: { ...typography.caption, color: colors.text.secondary },
  // '>' 모양: 테두리 두 변을 45도 돌린다
  chevronRight: {
    width: 7,
    height: 7,
    marginRight: 5,
    borderRightWidth: 1.5,
    borderTopWidth: 1.5,
    borderColor: colors.text.secondary,
    transform: [{ rotate: '45deg' }],
  },
});
