// Figma 텍스트 스타일(보고잡지/Type/...). 글꼴은 Noto Sans KR 이지만
// 지금은 폰트 파일을 불러오지 않아 기기 기본 글꼴로 보인다. (TODO: 글꼴 로딩 추가)
export const typography = {
  screenHeading: { fontSize: 28, lineHeight: 40, fontWeight: '700', letterSpacing: -1 },
  sectionHeading: { fontSize: 20, lineHeight: 30, fontWeight: '500', letterSpacing: -0.5 },
  body: { fontSize: 16, lineHeight: 26, fontWeight: '400' },
  bodySmall: { fontSize: 15, lineHeight: 24, fontWeight: '400' },
  label: { fontSize: 14, lineHeight: 22, fontWeight: '500' },
  button: { fontSize: 16, lineHeight: 24, fontWeight: '500' },
  caption: { fontSize: 13, lineHeight: 20, fontWeight: '400' },
};
