// 관계 → 호칭 (명세서 '호칭 대응표' 시트, TTL-01~04)
// 보내는 사람이 고른 관계 + 받는 분 성별로 호칭이 정해진다. 외가 구분 없음, 직접 입력 없음.

// 관계 8개. 서버 값(openapi Relationship enum)과 같은 문자열을 쓴다.
export const RELATIONSHIPS = ['손녀', '손자', '딸', '아들', '며느리', '사위', '손주며느리', '손주사위'];

const HONORIFIC = {
  손녀: { female: '할머니', male: '할아버지' },
  손자: { female: '할머니', male: '할아버지' },
  딸: { female: '엄마', male: '아빠' },
  아들: { female: '엄마', male: '아빠' },
  며느리: { female: '어머님', male: '아버님' },
  사위: { female: '장모님', male: '장인어른' },
  손주며느리: { female: '할머니', male: '할아버지' },
  손주사위: { female: '할머니', male: '할아버지' },
};

// genders: 받는 분들의 성별 배열 ('female' | 'male' | null). 부부면 두 개.
// 부부는 '할머니·할아버지'처럼 여성 → 남성 순서로 잇는다 (TTL-02).
// 성별을 아직 모르면 두 호칭을 함께 보여 준다.
export function honorificFor(relationship, genders) {
  const pair = HONORIFIC[relationship];
  if (!pair) return null;
  const known = genders.filter(Boolean);
  if (genders.length === 1 && known.length === 1) return pair[known[0]];
  return `${pair.female}·${pair.male}`;
}

// 받침이 있는 글자로 끝나는지 (조사 고르기용, TTL-03)
function hasFinalConsonant(word) {
  const code = word.charCodeAt(word.length - 1);
  if (code < 0xac00 || code > 0xd7a3) return false; // 한글이 아니면 받침 없음으로 본다
  return (code - 0xac00) % 28 !== 0;
}

// 을/를, 이/가, 은/는, 이에요/예요 를 받침에 맞게 붙인다. 예) withJosa('손녀', '을/를') → '손녀를'
export function withJosa(word, pair) {
  const [withBatchim, withoutBatchim] = pair.split('/');
  return word + (hasFinalConsonant(word) ? withBatchim : withoutBatchim);
}
