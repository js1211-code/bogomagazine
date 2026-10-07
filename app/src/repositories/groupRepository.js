import { getCurrentAccount, groups, SIMULATE_CREATE_FAILURE } from '../mocks/mockStore';

// 가족방(가족 그룹) 저장소. 지금은 mock 이고, 서버가 준비되면 이 함수 안만 실제 호출로 바꾼다.

const wait = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

function requireUser() {
  const account = getCurrentAccount();
  if (!account) throw new Error('로그인 상태가 아니에요.');
  return account.user;
}

// 내가 속한 가족방 목록 (FAM-04)
// 반환: FamilyGroup[]  ← openapi 의 FamilyGroup 모양 { id, name, newsletterTitle, ownerId, ... }
// TODO(2단계): GET /groups
export async function getMyGroups() {
  const user = requireUser();
  return groups.filter((g) => g.members.includes(user.id)).map((g) => g.group);
}

// 가족방 만들기 (FAM-01). 만든 사람이 방장이 된다.
// input: {
//   name, newsletterTitle,                       ← 3/3 이름 짓기
//   relationship,                                ← 1/3 내 관계 (Relationship 8개 중 하나)
//   recipients: [{ name, gender }],              ← 1/3 받는 분 (한 분이면 1개, 부부면 2개)
//   recipientConsent: true,                      ← 1/3 받는 분 정보 입력 동의 (RCV-03)
//   deliveryAddress: { postalCode, addressLine1, addressLine2 },  ← 2/3 배송지
//   requestKey,                                  ← 같은 요청을 다시 보내도 한 번만 만들어지게 하는 번호
// }
// 반환: FamilyGroup
//
// TODO(2단계): POST /groups
// TODO(API 확인): openapi 의 DeliveryAddressInput 은 받는 분 이름이 한 칸이고 성별은 한 분일 때만 받는다.
//   명세서(RCV-01)는 부부면 두 분 각각 이름·성별을 받으므로 recipients 배열로 보내야 한다 — 백엔드와 맞출 것.
// TODO(API 확인): 받는 분 정보 입력 동의(RCV-03)를 보내는 칸이 openapi 에 없다.
export async function createGroup(input) {
  const user = requireUser();
  await wait(1200); // 실제 요청처럼 '만드는 중' 화면이 잠깐 보이게 한다
  if (SIMULATE_CREATE_FAILURE) throw new Error('mock: 가족방 만들기 실패');

  // 중복 생성 방지 (FAM-01 ②): 같은 요청 번호로 다시 오면 새로 만들지 않고 그 가족방을 돌려준다
  const existing = groups.find((g) => g.requestKey === input.requestKey && g.group.ownerId === user.id);
  if (existing) return existing.group;

  const group = {
    id: `mock-group-${groups.length + 1}`,
    name: input.name,
    newsletterTitle: input.newsletterTitle || '보고잡지',
    ownerId: user.id,
    createdAt: new Date().toISOString(),
  };
  groups.push({
    group,
    members: [user.id],
    relationshipByUser: { [user.id]: input.relationship },
    recipients: input.recipients,
    deliveryAddress: input.deliveryAddress,
    inviteCode: Math.random().toString(36).slice(2, 8),
    requestKey: input.requestKey,
  });
  return group;
}

// 가족방 초대 링크 (FAM-05). 가족마다 고정 코드 1개라 몇 번을 불러도 같은 링크가 나온다.
// 반환: { shareUrl }
// TODO(2단계): POST /groups/{groupId}/invites
// TODO(API 확인): openapi 는 '방장만' 만들 수 있다고 되어 있지만 명세서(FAM-05)는 '구성원 누구나 공유 가능'.
// TODO(API 확인): 링크 도메인은 아직 정해지지 않았다 (명세서: https://{도메인}/i/{코드}).
export async function getInviteLink(groupId) {
  const entry = groups.find((g) => g.group.id === groupId);
  if (!entry) throw new Error('가족방을 찾을 수 없어요.');
  return { shareUrl: `https://bogo.app/i/${entry.inviteCode}` };
}
