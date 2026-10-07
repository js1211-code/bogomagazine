import { useEffect, useState } from 'react';
import { colors } from '../theme';
import BottomSheet, { SheetActions, SheetDivider } from './BottomSheet';
import Button from './Button';
import CheckboxRow from './CheckboxRow';

// 약관 항목. required 가 true 면 모두 체크해야 [동의하고 계속하기] 가 켜진다. (명세서 ACC-03)
const TERMS = [
  { key: 'terms', label: '[필수] 서비스 이용약관', required: true },
  { key: 'privacy', label: '[필수] 개인정보 수집·이용', required: true },
  { key: 'age14', label: '[필수] 만 14세 이상입니다', required: true },
  { key: 'research', label: '[선택] 연구·발표 활용 동의', required: false },
];

const NONE = { terms: false, privacy: false, age14: false, research: false };

// consent: 이미 동의한 값이 있으면 다시 열 때 체크된 상태로 보여 준다 (null 이면 모두 비어 있음)
export default function ConsentSheet({ visible, onClose, onConfirm, onViewTerm, consent, onHeightChange }) {
  const [checked, setChecked] = useState(NONE);

  // 저장된 동의가 바뀔 때만 맞춘다. 시트를 닫았다 열어도(동의 상세를 보고 돌아와도) 체크하던 상태는 남는다.
  useEffect(() => {
    setChecked(
      consent
        ? {
            terms: consent.termsConsented,
            privacy: consent.privacyConsented,
            age14: consent.ageOver14Confirmed,
            research: consent.researchConsented,
          }
        : NONE,
    );
  }, [consent]);

  const allChecked = TERMS.every((t) => checked[t.key]);
  const requiredChecked = TERMS.filter((t) => t.required).every((t) => checked[t.key]);

  const toggleAll = () => {
    const next = !allChecked;
    setChecked({ terms: next, privacy: next, age14: next, research: next });
  };

  const confirm = () => {
    // 서버 요청 형식(SignupConsent)과 같은 모양으로 넘긴다
    onConfirm({
      privacyConsented: true,
      termsConsented: true,
      ageOver14Confirmed: true,
      researchConsented: checked.research,
    });
  };

  return (
    <BottomSheet
      visible={visible}
      onClose={onClose}
      backgroundColor={colors.surface.subtle}
      title="서비스 이용을 위해 약관에 동의해주세요."
      showHandle
      onHeightChange={onHeightChange}
    >
      <CheckboxRow label="전체 동의" checked={allChecked} onToggle={toggleAll} />
      <SheetDivider />
      {TERMS.map((t) => (
        <CheckboxRow
          key={t.key}
          label={t.label}
          emphasis={t.required}
          checked={checked[t.key]}
          onToggle={() => setChecked((prev) => ({ ...prev, [t.key]: !prev[t.key] }))}
          onView={() => onViewTerm(t.key)}
        />
      ))}
      <SheetActions>
        <Button title="동의하고 계속하기" onPress={confirm} disabled={!requiredChecked} />
      </SheetActions>
    </BottomSheet>
  );
}
