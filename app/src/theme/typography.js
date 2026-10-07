import { fonts } from './fonts';

// Figma 텍스트 스타일(보고잡지/Type/...), 글꼴 Noto Sans KR.
// 굵기는 fontWeight 가 아니라 fontFamily 로 정한다 (theme/fonts.js).
// Figma 의 letterSpacing 은 % 단위(-1 = -1%)이고 React Native 는 px 이므로 글자 크기에 곱해 환산했다.
export const typography = {
  screenHeading: { fontFamily: fonts.bold, fontSize: 28, lineHeight: 40, letterSpacing: -0.28 },
  sectionHeading: { fontFamily: fonts.medium, fontSize: 20, lineHeight: 30, letterSpacing: -0.1 },
  body: { fontFamily: fonts.regular, fontSize: 16, lineHeight: 26 },
  bodySmall: { fontFamily: fonts.regular, fontSize: 15, lineHeight: 24 },
  label: { fontFamily: fonts.medium, fontSize: 14, lineHeight: 22 },
  button: { fontFamily: fonts.medium, fontSize: 16, lineHeight: 24 },
  caption: { fontFamily: fonts.regular, fontSize: 13, lineHeight: 20 },
  // 로그인 화면의 제호 (보고잡지/Launch 제호)
  brandTitle: { fontFamily: fonts.bold, fontSize: 50, lineHeight: 64, letterSpacing: -0.5 },
};
