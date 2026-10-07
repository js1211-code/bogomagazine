// Figma 둥글기: 버튼·카드 16, 체크박스 4 (그 외 surface 12, control 8). 확인창은 Figma 8 → 16 (사용자 조정)
export const radius = {
  control: 8,
  surface: 12,
  large: 16,
  modal: 16,
  checkbox: 4,
};
export const hairline = 1;

// 4 의 배수 간격 (Figma 화면 기준 좌우 여백 24)
export const spacing = { xs: 4, sm: 8, md: 16, lg: 24, xl: 32 };

// 바텀 시트 공통 규격. 새 시트를 만들 때 이 값을 그대로 쓴다. (약관 동의 시트를 기준으로 정함)
//  ┌ paddingTop
//  │ 손잡이 ── handleGap ── 제목 ── titleGap ── 내용 ── actionGap ── 버튼
//  └ paddingBottom (+ 홈 표시줄 높이)
export const sheet = {
  radius: 20, // 위쪽 두 모서리
  paddingHorizontal: 24,
  paddingTop: 24,
  paddingBottom: 16, // 홈 표시줄 위로 띄우는 여백
  handleWidth: 40,
  handleHeight: 4,
  handleGap: 24, // 손잡이 ↔ 제목
  titleGap: 8, // 제목 ↔ 첫 내용
  dividerGap: 8, // 구분선 위·아래
  actionGap: 16, // 마지막 내용 ↔ 버튼
};
