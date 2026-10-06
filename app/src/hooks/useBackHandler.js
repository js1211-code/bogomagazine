import { useFocusEffect } from 'expo-router';
import { useCallback } from 'react';
import { BackHandler } from 'react-native';

// 안드로이드 뒤로 가기 버튼을 이 화면이 보이는 동안에만 가로챈다.
// (화면이 다른 화면 아래에 깔려 있을 때도 듣고 있으면, 위 화면에서 누른 뒤로 가기를 이 화면이 처리해 버린다)
// handler 가 true 를 돌려주면 기본 동작(이전 화면 / 앱 종료)을 막는다.
export function useBackHandler(handler) {
  useFocusEffect(
    useCallback(() => {
      const sub = BackHandler.addEventListener('hardwareBackPress', handler);
      return () => sub.remove();
    }, [handler]),
  );
}
