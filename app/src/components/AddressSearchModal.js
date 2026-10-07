import { useState } from 'react';
import { ActivityIndicator, Modal, StyleSheet, Text, View } from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { WebView } from 'react-native-webview';
import { colors, hairline, typography } from '../theme';
import Button from './Button';
import ScreenHeader from './ScreenHeader';

// 주소 찾기 (Figma: '주소 찾기 (우편번호 검색 웹)'). 카카오(다음) 우편번호 서비스를 앱 안의 웹 화면으로 띄운다.
// 무료이고 키가 필요 없다. 주소를 고르면 onSelect({ postalCode, addressLine1 }) 로 돌려준다.
// 참고: https://postcode.map.daum.net/guide
const POSTCODE_HTML = `<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8" />
<meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1" />
<style>html, body, #wrap { margin: 0; padding: 0; width: 100%; height: 100%; }</style>
</head>
<body>
<div id="wrap"></div>
<script src="https://t1.daumcdn.net/mapjsapi/bundle/postcode/prod/postcode.v2.js"></script>
<script>
  new daum.Postcode({
    width: '100%',
    height: '100%',
    oncomplete: function (data) {
      window.ReactNativeWebView.postMessage(JSON.stringify({
        postalCode: data.zonecode,
        addressLine1: data.roadAddress || data.jibunAddress || data.address,
      }));
    },
  }).embed(document.getElementById('wrap'));
</script>
</body>
</html>`;

export default function AddressSearchModal({ visible, onClose, onSelect }) {
  const [failed, setFailed] = useState(false);
  const [attempt, setAttempt] = useState(0); // 다시 시도할 때 웹 화면을 새로 그린다

  const handleMessage = (event) => {
    try {
      const result = JSON.parse(event.nativeEvent.data);
      if (result.postalCode && result.addressLine1) onSelect(result);
    } catch {
      // 우편번호 서비스가 보낸 값이 아니면 무시한다
    }
  };

  return (
    <Modal visible={visible} animationType="slide" presentationStyle="pageSheet" onRequestClose={onClose}>
      <SafeAreaView style={styles.screen} edges={['top', 'bottom']}>
        <View style={styles.header}>
          <ScreenHeader title="주소 찾기" onBack={onClose} />
        </View>
        {failed ? (
          <View style={styles.error}>
            <Text style={styles.errorTitle}>주소 검색을 열지 못했어요</Text>
            <Text style={styles.errorText}>인터넷 연결을 확인하고 다시 시도해 주세요.</Text>
            <Button
              title="다시 시도"
              onPress={() => {
                setFailed(false);
                setAttempt((n) => n + 1);
              }}
            />
          </View>
        ) : (
          <WebView
            key={attempt}
            originWhitelist={['*']}
            source={{ html: POSTCODE_HTML, baseUrl: 'https://postcode.map.daum.net' }}
            onMessage={handleMessage}
            onError={() => setFailed(true)}
            startInLoadingState
            renderLoading={() => (
              <View style={styles.loading}>
                <ActivityIndicator color={colors.action.primary} />
              </View>
            )}
          />
        )}
      </SafeAreaView>
    </Modal>
  );
}

const styles = StyleSheet.create({
  screen: { flex: 1, backgroundColor: colors.background.page },
  header: { paddingHorizontal: 24, borderBottomWidth: hairline, borderBottomColor: colors.border.default },
  loading: { ...StyleSheet.absoluteFillObject, alignItems: 'center', justifyContent: 'center' },
  error: { flex: 1, padding: 24, justifyContent: 'center', gap: 16 },
  errorTitle: { ...typography.sectionHeading, color: colors.text.primary, textAlign: 'center' },
  errorText: { ...typography.bodySmall, color: colors.text.secondary, textAlign: 'center' },
});
