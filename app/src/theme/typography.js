import { fonts } from './fonts';

// Figma 텍스트 스타일(보고잡지/Type/...), 글꼴 Noto Sans KR.
// 굵기는 fontWeight 가 아니라 fontFamily 로 정한다 (theme/fonts.js).
export const typography = {
  screenHeading: { fontFamily: fonts.bold, fontSize: 28, lineHeight: 40, letterSpacing: -1 },
  sectionHeading: { fontFamily: fonts.medium, fontSize: 20, lineHeight: 30, letterSpacing: -0.5 },
  body: { fontFamily: fonts.regular, fontSize: 16, lineHeight: 26 },
  bodySmall: { fontFamily: fonts.regular, fontSize: 15, lineHeight: 24 },
  label: { fontFamily: fonts.medium, fontSize: 14, lineHeight: 22 },
  button: { fontFamily: fonts.medium, fontSize: 16, lineHeight: 24 },
  caption: { fontFamily: fonts.regular, fontSize: 13, lineHeight: 20 },
};
