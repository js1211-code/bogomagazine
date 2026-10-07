import { NotoSansKR_400Regular, NotoSansKR_500Medium, NotoSansKR_700Bold } from '@expo-google-fonts/noto-sans-kr';

// Android/iOS 는 굵기마다 글꼴 이름이 따로 있어야 해서 fontWeight 대신 fontFamily 로 굵기를 정한다.
export const fonts = {
  regular: 'NotoSansKR_400Regular',
  medium: 'NotoSansKR_500Medium',
  bold: 'NotoSansKR_700Bold',
};

// 루트 레이아웃의 useFonts() 에 그대로 넘기는 글꼴 목록
export const fontSources = {
  NotoSansKR_400Regular,
  NotoSansKR_500Medium,
  NotoSansKR_700Bold,
};
