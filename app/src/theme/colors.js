// Figma 변수(보고잡지/Color/...)에서 가져온 색. 화면에서는 hex 를 직접 쓰지 말고 여기서 가져다 쓴다.
export const colors = {
  background: {
    page: '#FFFFFF',
    paper: '#F9F8F4', // 신문 느낌의 아이보리. 어느 화면에 쓰는지는 화면별로 Figma 확인
  },
  surface: {
    default: '#FFFFFF',
    accent: '#E8F0EB',
    subtle: '#F5F6F7',
  },
  text: {
    primary: '#252B2A',
    secondary: '#525E57',
    editorial: '#897665',
    onPrimary: '#FFFFFF',
  },
  action: {
    primary: '#3F6258',
  },
  border: {
    default: '#D7DDD5',
  },
  // 소셜 로그인 버튼은 각 사 디자인 가이드를 따른다 (ACC-01, ACC-02)
  brand: {
    kakao: '#FEE500',
    kakaoText: '#191919',
    apple: '#000000',
  },
};
