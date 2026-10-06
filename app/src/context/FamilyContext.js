import { createContext, useCallback, useContext, useEffect, useMemo, useState } from 'react';
import * as groupRepository from '../repositories/groupRepository';
import { useAuth } from './AuthContext';

const FamilyContext = createContext(null);

// 내가 속한 가족방들과 지금 보고 있는 가족방. 로그인한 사람이 바뀌면 다시 불러온다.
// - ready: 가족방 목록을 불러왔는지 (불러오기 전에는 어느 화면으로 보낼지 정할 수 없다)
// - justCreatedGroupId: 방금 만든 가족방. 초대 화면(0-4-5)을 보여 주는 동안만 값이 있다.
export function FamilyProvider({ children }) {
  const { session } = useAuth();
  const userId = session?.user?.id ?? null;
  const [groups, setGroups] = useState([]);
  const [ready, setReady] = useState(false);
  const [currentGroupId, setCurrentGroupId] = useState(null);
  const [justCreatedGroupId, setJustCreatedGroupId] = useState(null);

  useEffect(() => {
    setGroups([]);
    setCurrentGroupId(null);
    setJustCreatedGroupId(null);
    setReady(false);
    if (!userId) return undefined;

    let cancelled = false;
    groupRepository
      .getMyGroups()
      .then((list) => {
        if (cancelled) return;
        setGroups(list);
        // TODO(FAM-04): 앱을 열면 '마지막에 본 가족'을 보여 준다. 지금은 첫 번째 가족방.
        setCurrentGroupId(list[0]?.id ?? null);
        setReady(true);
      })
      .catch(() => {
        // TODO: 목록을 불러오지 못했을 때의 화면 (가족 전환 작업에서 다시 시도 화면과 함께 만든다)
        if (!cancelled) setReady(true);
      });
    return () => {
      cancelled = true;
    };
  }, [userId]);

  const createGroup = useCallback(async (input) => {
    const group = await groupRepository.createGroup(input);
    setGroups((prev) => (prev.some((g) => g.id === group.id) ? prev : [...prev, group]));
    setCurrentGroupId(group.id);
    setJustCreatedGroupId(group.id);
    return group;
  }, []);

  // 초대 화면(0-4-5)을 마치고 메인으로 들어간다
  const finishSetup = useCallback(() => setJustCreatedGroupId(null), []);

  const value = useMemo(
    () => ({
      ready,
      groups,
      currentGroup: groups.find((g) => g.id === currentGroupId) ?? null,
      justCreatedGroup: groups.find((g) => g.id === justCreatedGroupId) ?? null,
      // 가족방 없음(0-5)·가족방 만들기 흐름에 있어야 하는지
      needsFamilySetup: ready && (groups.length === 0 || justCreatedGroupId !== null),
      createGroup,
      finishSetup,
    }),
    [ready, groups, currentGroupId, justCreatedGroupId, createGroup, finishSetup],
  );

  return <FamilyContext.Provider value={value}>{children}</FamilyContext.Provider>;
}

export function useFamily() {
  const ctx = useContext(FamilyContext);
  if (!ctx) throw new Error('useFamily 는 FamilyProvider 안에서만 쓸 수 있어요.');
  return ctx;
}
