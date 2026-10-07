import { createContext, useContext, useMemo, useState } from 'react';

// 가족방 만들기 1/3 ~ 3/3 이 함께 쓰는 입력값.
// 만들기 흐름(create/_layout)이 열려 있는 동안만 살아 있고, 가족방 없음 화면으로 나가면 사라진다 (FAM-01: 저장하지 않음).
const EMPTY_PERSON = { name: '', gender: null };

function createInitialDraft() {
  return {
    count: 'single', // 'single' | 'couple'
    people: [{ ...EMPTY_PERSON }, { ...EMPTY_PERSON }], // 한 분이면 첫 번째만 쓴다
    activeIndex: 0, // 두 분일 때 지금 입력 중인 분
    relationship: null, // 관계 8개 중 하나 (두 분이어도 한 번만 고른다, PRF-02)
    recipientConsent: false, // 받는 분 정보 입력 동의 (RCV-03)
    address: { postalCode: '', addressLine1: '', addressLine2: '' },
    groupName: '',
    newsletterTitle: '',
    // 같은 요청을 여러 번 보내도 가족방이 하나만 만들어지게 하는 번호 (FAM-01 ②). 다시 시도해도 그대로 쓴다.
    requestKey: `${Date.now()}-${Math.random().toString(36).slice(2, 10)}`,
  };
}

export function isPersonComplete(person) {
  return person.name.trim() !== '' && person.gender !== null;
}

// 지금 받는 분 목록 (한 분이면 1명, 두 분이면 2명)
export function recipientsOf(draft) {
  return draft.count === 'couple' ? draft.people : draft.people.slice(0, 1);
}

// 단계 번호 → 화면 주소. 단계 막대를 눌러 이전 단계로 돌아갈 때 쓴다.
export const STEP_ROUTES = { 1: '/create/recipient', 2: '/create/address', 3: '/create/naming' };

const DraftContext = createContext(null);

export function CreateFamilyDraftProvider({ children }) {
  const [draft, setDraft] = useState(createInitialDraft);

  const value = useMemo(
    () => ({
      draft,
      // 일부만 바꾼다. 예) update({ groupName: '미자 여사네' })
      update: (patch) => setDraft((prev) => ({ ...prev, ...patch })),
      // 받는 분 한 명의 값만 바꾼다
      updatePerson: (index, patch) =>
        setDraft((prev) => ({
          ...prev,
          people: prev.people.map((p, i) => (i === index ? { ...p, ...patch } : p)),
        })),
    }),
    [draft],
  );

  return <DraftContext.Provider value={value}>{children}</DraftContext.Provider>;
}

export function useCreateFamilyDraft() {
  const ctx = useContext(DraftContext);
  if (!ctx) throw new Error('useCreateFamilyDraft 는 CreateFamilyDraftProvider 안에서만 쓸 수 있어요.');
  return ctx;
}
