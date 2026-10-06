import { useEffect, useRef, useState } from 'react';
import { Pressable, ScrollView, StyleSheet, Text, View } from 'react-native';
import { colors, fonts, typography } from '../theme';
import BottomSheet, { SheetActions } from './BottomSheet';
import Button from './Button';

// 월·일 선택 시트 (Figma 0-2-a). 연도는 받지 않으므로 2월은 29일까지 고를 수 있다.
const DAYS_IN_MONTH = [31, 29, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];
const ITEM_HEIGHT = 48;
const ITEM_GAP = 8;
const PITCH = ITEM_HEIGHT + ITEM_GAP;
const VISIBLE_HEIGHT = ITEM_HEIGHT * 3 + ITEM_GAP * 2; // 위·가운데·아래 3줄

// 세로로 스크롤하며 가운데 줄에 멈추는 숫자 목록. 가운데 줄이 선택된 값이다.
function Wheel({ label, values, selectedIndex, onChange }) {
  const scrollRef = useRef(null);

  // 처음 보일 때 선택된 값이 가운데 오도록 위치를 맞춘다
  const jumpToSelected = () => scrollRef.current?.scrollTo({ y: selectedIndex * PITCH, animated: false });

  const indexFromOffset = (y) => Math.min(values.length - 1, Math.max(0, Math.round(y / PITCH)));

  return (
    <View style={styles.column}>
      <Text style={styles.columnLabel}>{label}</Text>
      <ScrollView
        ref={scrollRef}
        style={styles.wheel}
        contentContainerStyle={{ paddingVertical: PITCH }}
        showsVerticalScrollIndicator={false}
        snapToInterval={PITCH}
        decelerationRate="fast"
        scrollEventThrottle={16}
        onLayout={jumpToSelected}
        onScroll={(e) => {
          const next = indexFromOffset(e.nativeEvent.contentOffset.y);
          if (next !== selectedIndex) onChange(next);
        }}
      >
        {values.map((v, i) => {
          const selected = i === selectedIndex;
          return (
            <Pressable
              key={v}
              accessibilityRole="button"
              accessibilityLabel={`${v}${label}`}
              accessibilityState={{ selected }}
              onPress={() => scrollRef.current?.scrollTo({ y: i * PITCH, animated: true })}
              style={[styles.item, selected && styles.itemSelected, i > 0 && { marginTop: ITEM_GAP }]}
            >
              <Text style={selected ? styles.itemTextSelected : styles.itemText}>{v}</Text>
            </Pressable>
          );
        })}
      </ScrollView>
    </View>
  );
}

// initial: { month, day } 또는 null. onSelect({ month, day }) 로 결과를 돌려준다.
export default function BirthdayPickerSheet({ visible, onClose, onSelect, initial }) {
  const [month, setMonth] = useState(1);
  const [day, setDay] = useState(1);
  const [openCount, setOpenCount] = useState(0);

  // 열릴 때마다 기존 값(없으면 1월 1일)으로 시작하고, 목록을 새로 그려 위치를 다시 맞춘다
  useEffect(() => {
    if (!visible) return;
    setMonth(initial?.month ?? 1);
    setDay(initial?.day ?? 1);
    setOpenCount((c) => c + 1);
  }, [visible, initial]);

  const months = Array.from({ length: 12 }, (_, i) => i + 1);
  const maxDay = DAYS_IN_MONTH[month - 1];
  const days = Array.from({ length: maxDay }, (_, i) => i + 1);
  const safeDay = Math.min(day, maxDay);

  return (
    <BottomSheet visible={visible} onClose={onClose} title="생일을 알려 주세요">
      <View style={styles.content}>
        <Text style={styles.subtitle}>월과 일만 받아요.</Text>
        <View style={styles.wheels}>
          <Wheel
            key={`m${openCount}`}
            label="월"
            values={months}
            selectedIndex={month - 1}
            onChange={(i) => setMonth(i + 1)}
          />
          <Wheel
            // 월이 바뀌어 일 수가 달라지면 목록을 새로 그린다
            key={`d${openCount}-${maxDay}`}
            label="일"
            values={days}
            selectedIndex={safeDay - 1}
            onChange={(i) => setDay(i + 1)}
          />
        </View>
        <Text style={styles.summary}>{`선택한 생일 · ${month}월 ${safeDay}일`}</Text>
      </View>
      <SheetActions>
        <Button title="선택" onPress={() => onSelect({ month, day: safeDay })} />
      </SheetActions>
    </BottomSheet>
  );
}

const styles = StyleSheet.create({
  content: { gap: 16 },
  subtitle: { ...typography.bodySmall, color: colors.text.secondary },
  wheels: { flexDirection: 'row', gap: 12 },
  column: { flex: 1, alignItems: 'stretch', gap: 8 },
  columnLabel: { ...typography.caption, fontFamily: fonts.medium, color: colors.text.secondary, textAlign: 'center' },
  wheel: { height: VISIBLE_HEIGHT },
  item: {
    height: ITEM_HEIGHT,
    borderRadius: 10,
    backgroundColor: colors.background.paper,
    alignItems: 'center',
    justifyContent: 'center',
  },
  itemSelected: { backgroundColor: colors.surface.accent },
  itemText: { fontFamily: fonts.regular, fontSize: 17, color: colors.text.disabled },
  itemTextSelected: { fontFamily: fonts.bold, fontSize: 20, color: colors.text.primary },
  summary: { ...typography.label, color: colors.action.primary },
});
