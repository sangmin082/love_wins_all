// 서버 통합 테스트: 방 생성 → 코드 입장 → 딜링(비공개) → 무브 릴레이 → 쇼다운 공개 → 다음 라운드 → 퇴장
const { spawn } = require('child_process');
const WebSocket = require('ws');

const PORT = 8181;
const URL = `ws://127.0.0.1:${PORT}`;

function connect() {
  return new Promise((resolve, reject) => {
    const ws = new WebSocket(URL);
    ws.inbox = [];
    ws.waiters = [];
    ws.on('message', (raw) => {
      const msg = JSON.parse(raw.toString());
      const waiter = ws.waiters.shift();
      if (waiter) waiter(msg);
      else ws.inbox.push(msg);
    });
    ws.next = () =>
      new Promise((res, rej) => {
        if (ws.inbox.length) return res(ws.inbox.shift());
        ws.waiters.push(res);
        setTimeout(() => rej(new Error('메시지 수신 타임아웃')), 3000);
      });
    ws.on('open', () => resolve(ws));
    ws.on('error', reject);
  });
}

function assert(cond, label) {
  if (!cond) throw new Error(`실패: ${label}`);
  console.log(`  ✓ ${label}`);
}

// 손패가 30장 덱 구성(가위12/바위7/보7/러브4)에서 나올 수 있는 유효한 3장인지
function validHand(cards) {
  if (!Array.isArray(cards) || cards.length !== 3) return false;
  const limit = { 0: 12, 1: 7, 2: 7, 3: 4 };
  const counts = {};
  for (const c of cards) {
    if (!(c in limit)) return false;
    counts[c] = (counts[c] || 0) + 1;
    if (counts[c] > limit[c]) return false;
  }
  return true;
}

async function main() {
  const server = spawn('node', ['index.js'], {
    cwd: __dirname,
    env: { ...process.env, PORT },
    stdio: 'inherit',
  });
  await new Promise((r) => setTimeout(r, 500));

  try {
    // 1) 방 생성
    const host = await connect();
    host.send(JSON.stringify({ type: 'create' }));
    const roomMsg = await host.next();
    assert(roomMsg.type === 'room' && roomMsg.player === 0, '방 생성 응답');
    assert(/^[A-Z2-9]{6}$/.test(roomMsg.code), `방 코드 형식 (${roomMsg.code})`);

    // 2) 잘못된 코드 입장
    const stranger = await connect();
    stranger.send(JSON.stringify({ type: 'join', code: 'XXXXXX' }));
    const errMsg = await stranger.next();
    assert(errMsg.type === 'error', '존재하지 않는 방 코드 거부');
    stranger.close();

    // 3) 정상 입장 → 양쪽 start → 딜링
    const guest = await connect();
    guest.send(JSON.stringify({ type: 'join', code: roomMsg.code }));
    const joinedMsg = await guest.next();
    assert(joinedMsg.type === 'joined' && joinedMsg.player === 1, '입장 응답');
    const startHost = await host.next();
    const startGuest = await guest.next();
    assert(startHost.type === 'start' && startGuest.type === 'start', '양쪽 start 수신');
    assert(startHost.first === startGuest.first, '선 플레이어 일치');
    assert([0, 1].includes(startHost.first), '선 플레이어 인덱스 유효');

    // 4) 딜링 — 각자 자기 손패만 받고, 두 손패는 덱 구성상 유효
    const handHost = await host.next();
    const handGuest = await guest.next();
    assert(handHost.type === 'hand' && handGuest.type === 'hand', '양쪽 hand 수신');
    assert(validHand(handHost.cards) && validHand(handGuest.cards), '손패 3장 유효');
    assert(validHand([...handHost.cards, ...handGuest.cards].slice(0, 3)), '(형식 확인)');
    assert(handHost.hands === undefined, '상대 손패는 전달되지 않음');

    // 5) 무브 릴레이 (iOS 클라이언트와 동일한 인코딩)
    const move = { kind: 'bet', amount: 3 };
    host.send(JSON.stringify({ type: 'move', move }));
    const relayed = await guest.next();
    assert(relayed.type === 'move' && relayed.move.kind === 'bet' && relayed.move.amount === 3,
      '무브 릴레이 (호스트→게스트)');

    const move2 = { kind: 'declare', open: 0, rank: 2 };
    guest.send(JSON.stringify({ type: 'move', move: move2 }));
    const relayed2 = await host.next();
    assert(relayed2.type === 'move' && relayed2.move.open === 0 && relayed2.move.rank === 2,
      '무브 릴레이 (게스트→호스트)');

    // 6) 쇼다운 — 한 쪽 요청만으로는 공개되지 않고, 양쪽 요청이 모이면 공개
    host.send(JSON.stringify({ type: 'showdown' }));
    const pendingReveal = host.next(); // 아직 오지 않아야 할 reveal 대기
    const early = await Promise.race([pendingReveal, new Promise((r) => setTimeout(() => r(null), 300))]);
    assert(early === null, '한 쪽 요청만으로는 공개 안 됨');
    guest.send(JSON.stringify({ type: 'showdown' }));
    const revealHost = await pendingReveal;
    const revealGuest = await guest.next();
    assert(revealHost.type === 'reveal' && revealGuest.type === 'reveal', '양쪽 reveal 수신');
    assert(JSON.stringify(revealHost.hands) === JSON.stringify(revealGuest.hands), '공개 손패 일치');
    assert(JSON.stringify(revealHost.hands[0]) === JSON.stringify(handHost.cards)
      && JSON.stringify(revealHost.hands[1]) === JSON.stringify(handGuest.cards),
      '공개 손패 = 배분 손패');

    // 7) 다음 라운드 — 양쪽 ready가 모이면 새로 딜링
    host.send(JSON.stringify({ type: 'ready' }));
    guest.send(JSON.stringify({ type: 'ready' }));
    const hand2Host = await host.next();
    const hand2Guest = await guest.next();
    assert(hand2Host.type === 'hand' && hand2Guest.type === 'hand', '다음 라운드 딜링');
    assert(validHand(hand2Host.cards) && validHand(hand2Guest.cards), '다음 라운드 손패 유효');

    // 8) 퇴장 알림
    guest.close();
    const leftMsg = await host.next();
    assert(leftMsg.type === 'left', '상대 퇴장 알림');
    host.close();

    console.log('\n모든 테스트 통과 ✅');
  } finally {
    server.kill();
  }
}

main().catch((e) => {
  console.error(e.message);
  process.exit(1);
});
