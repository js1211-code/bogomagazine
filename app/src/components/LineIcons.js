import { StyleSheet, View } from 'react-native';
import { colors } from '../theme';

// Figma 의 40×40 선 아이콘을 그림 파일 없이 상자와 테두리로 그린다.

// icon-family: 두 사람 (머리 동그라미 + 타원 몸)
export function FamilyIcon() {
  return (
    <View style={styles.icon} accessibilityElementsHidden importantForAccessibility="no-hide-descendants">
      {[9, 21].map((left) => (
        <View key={left} style={[styles.person, { left }]}>
          <View style={styles.head} />
          <View style={styles.body} />
        </View>
      ))}
    </View>
  );
}

// icon-newspaper: 신문 한 장 (테두리, 줄, 사진 칸)
export function NewspaperIcon() {
  return (
    <View style={styles.icon} accessibilityElementsHidden importantForAccessibility="no-hide-descendants">
      <View style={styles.paper} />
      <View style={[styles.line, { left: 10, top: 10, width: 20 }]} />
      <View style={[styles.line, { left: 10, top: 15, width: 20 }]} />
      <View style={styles.photo} />
      <View style={[styles.line, { left: 21, top: 22, width: 9 }]} />
      <View style={[styles.line, { left: 21, top: 26, width: 9 }]} />
      <View style={[styles.line, { left: 10, top: 31, width: 20 }]} />
    </View>
  );
}

const ink = colors.text.primary;

const styles = StyleSheet.create({
  icon: { width: 40, height: 40 },
  person: { position: 'absolute', top: 8, width: 10, alignItems: 'center' },
  head: { width: 7, height: 7, borderRadius: 3.5, borderWidth: 1.8, borderColor: ink },
  body: { marginTop: 3, width: 10, height: 13, borderRadius: 5, borderWidth: 1.8, borderColor: ink },
  paper: { position: 'absolute', left: 6, top: 3, width: 28, height: 34, borderRadius: 2, borderWidth: 1.5, borderColor: ink },
  line: { position: 'absolute', height: 1.5, backgroundColor: ink },
  photo: { position: 'absolute', left: 10, top: 21, width: 8, height: 8, borderWidth: 1.2, borderColor: ink },
});
