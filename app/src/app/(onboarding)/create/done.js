import * as Clipboard from 'expo-clipboard';
import { useCallback, useEffect, useRef, useState } from 'react';
import { Alert, Pressable, ScrollView, Share, StyleSheet, Text, View } from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import BrandHeader from '../../../components/BrandHeader';
import Button from '../../../components/Button';
import { useFamily } from '../../../context/FamilyContext';
import { useBackHandler } from '../../../hooks/useBackHandler';
import * as groupRepository from '../../../repositories/groupRepository';
import { colors, hairline, radius, typography } from '../../../theme';

// Figma 0-4-5 가족방 만들기 · 완료 · 초대, 명세서 FAM-05
// - [카카오톡으로 초대하기]: 1단계(Expo Go)는 휴대폰 기본 공유 창으로 대신한다.
//   TODO(2단계): 카카오 SDK 공유 + 0-4-5-a 메시지 템플릿(이미지 카드, [가족신문 참여하기] 버튼)
// - [나중에 하기] 또는 뒤로 가기 → 메인(소식 탭)
export default function DoneScreen() {
  const { justCreatedGroup, finishSetup } = useFamily();
  const [shareUrl, setShareUrl] = useState(null);
  const [copied, setCopied] = useState(false);
  const copiedTimer = useRef(null);

  useEffect(() => {
    if (!justCreatedGroup) return;
    groupRepository
      .getInviteLink(justCreatedGroup.id)
      .then(({ shareUrl: url }) => setShareUrl(url))
      .catch(() => Alert.alert('초대 링크를 불러오지 못했어요', '가족 탭에서 다시 초대할 수 있어요.'));
  }, [justCreatedGroup]);

  useEffect(() => () => clearTimeout(copiedTimer.current), []);

  const leave = useCallback(() => {
    finishSetup();
    return true;
  }, [finishSetup]);

  useBackHandler(leave);

  const groupName = justCreatedGroup?.name ?? '';

  const share = async () => {
    if (!shareUrl) return;
    // 문구는 Figma 0-4-5-a 카카오 메시지 템플릿을 따른다
    await Share.share({
      message: `${groupName}에 초대해요.\n우리의 일상을 모아 종이신문으로 전해요. 함께 소식을 써 주세요!\n${shareUrl}`,
    });
  };

  const copy = async () => {
    if (!shareUrl) return;
    await Clipboard.setStringAsync(shareUrl);
    setCopied(true);
    clearTimeout(copiedTimer.current);
    copiedTimer.current = setTimeout(() => setCopied(false), 2000);
  };

  return (
    <SafeAreaView style={styles.screen} edges={['top', 'bottom']}>
      <BrandHeader />
      <ScrollView contentContainerStyle={styles.body}>
        <View style={styles.intro}>
          <Text style={styles.title}>✓ 가족방을 만들었어요</Text>
          <Text style={styles.subtitle}>{`${groupName}에 가족을 초대해 일상을 함께 모아 보세요.`}</Text>
        </View>

        <Button title="카카오톡으로 초대하기" onPress={share} disabled={!shareUrl} />

        <View style={styles.linkBox}>
          <Text style={styles.link} numberOfLines={1}>
            {shareUrl ? shareUrl.replace(/^https?:\/\//, '') : ' '}
          </Text>
          <Pressable accessibilityRole="button" accessibilityLabel="초대 링크 복사" onPress={copy} hitSlop={12}>
            <Text style={styles.copy} accessibilityLiveRegion="polite">
              {copied ? '복사됨' : '복사'}
            </Text>
          </Pressable>
        </View>

        <View style={styles.divider} />

        <View style={styles.later}>
          <Button title="나중에 하기" variant="quiet" onPress={leave} />
          <Text style={styles.caption}>가족 탭에서 다시 초대할 수 있어요.</Text>
        </View>
      </ScrollView>
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  screen: { flex: 1, backgroundColor: colors.background.page },
  body: { paddingHorizontal: 24, paddingTop: 24, paddingBottom: 16, gap: 24 },
  intro: { gap: 16 },
  title: { ...typography.screenHeading, color: colors.text.primary },
  subtitle: { ...typography.bodySmall, color: colors.text.secondary },
  linkBox: {
    height: 56,
    paddingHorizontal: 16,
    borderWidth: hairline,
    borderColor: colors.border.default,
    borderRadius: radius.control,
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    gap: 12,
  },
  link: { ...typography.body, color: colors.text.secondary, flex: 1 },
  copy: { ...typography.label, color: colors.action.primary },
  divider: { height: hairline, backgroundColor: colors.border.default },
  later: { gap: 8 },
  caption: { ...typography.caption, color: colors.text.secondary, textAlign: 'center' },
});
