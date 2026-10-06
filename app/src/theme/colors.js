// Figma 변수(보고잡지/Color/...)에서 가져온 색. 화면에서는 hex 를 직접 쓰지 말고 여기서 가져다 쓴다.
export const colors = {
  background: {
    page: '#FFFFFF',
    paper: '#F9F8F4', // 신문 느낌의 아이보리 (확인창 배경, 생일 선택 항목 등)
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
    placeholder: '#667069',
    disabled: '#929A90',
    onPrimary: '#FFFFFF',
  },
  action: {
    primary: '#3F6258',
    disabled: '#E4E8E2',
  },
  border: {
    default: '#D7DDD5',
    focus: '#000000', // 비어 있거나 입력 중인 칸의 테두리
  },
  // 시트/대화상자 뒤의 어두운 막
  overlay: 'rgba(0, 0, 0, 0.45)',
  // 시트 손잡이
  handle: '#CCC4BA',
  // 소셜 로그인 버튼은 각 사 디자인 가이드를 따른다 (ACC-01, ACC-02)
  brand: {
    kakao: '#FEE500',
    kakaoText: 'rgba(0, 0, 0, 0.85)',
    apple: '#000000',
  },
};
