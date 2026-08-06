// 러브 윈즈 올 — 2인용 온라인 대전 서버
//
// 서버는 베팅·선언 무브를 해석하지 않고 릴레이만 하되, 손패가 비공개인 게임 특성상
// "딜러" 역할을 겸한다: 라운드마다 30장을 섞어 각자에게 자기 손패 3장만 보내고,
// 양쪽이 쇼다운을 요청하면 두 손패를 공개한다. (폴드로 끝난 라운드는 공개하지 않는다)
//
// 프로토콜 (JSON over WebSocket) — 카드는 정수 (0 가위, 1 바위, 2 보, 3 러브)
//   클라이언트 → 서버
//     {"type":"create"}                 방 생성
//     {"type":"join","code":"ABC123"}   방 입장
//     {"type":"move","move":{...}}      무브 릴레이 (서버는 내용을 해석하지 않음)
//     {"type":"showdown"}               쇼다운 공개 요청 (양쪽 요청이 모이면 reveal)
//     {"type":"ready"}                  다음 라운드 준비 (양쪽 준비가 모이면 새 딜)
//   서버 → 클라이언트
//     {"type":"room","code":"ABC123","player":0}   방 생성 완료 (방장 = 0)
//     {"type":"joined","player":1}                 입장 완료 (참가자 = 1)
//     {"type":"start","first":0|1}                 대국 시작, first = 라운드 1 선
//     {"type":"hand","cards":[0,1,3]}              자기 손패 (비공개 — 본인에게만)
//     {"type":"reveal","hands":[[..],[..]]}        쇼다운 — 양쪽 손패 공개
//     {"type":"move","move":{...}}                 상대의 무브
//     {"type":"left"}                              상대 퇴장
//     {"type":"error","message":"..."}             오류

const fs = require('fs');
const http = require('http');
const path = require('path');
const { WebSocketServer } = require('ws');

const PORT = process.env.PORT || 8080;
const PRIVACY_HTML = fs.readFileSync(path.join(__dirname, 'privacy.html'), 'utf8');
// 헷갈리기 쉬운 문자(0/O, 1/I)를 뺀 코드 알파벳
const CODE_ALPHABET = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
const CODE_LENGTH = 6;

// 가위 12, 바위 7, 보 7, 러브 4 — 총 30장 (iOS Card rawValue와 동일한 인코딩)
const FULL_DECK = [
  ...Array(12).fill(0), ...Array(7).fill(1), ...Array(7).fill(2), ...Array(4).fill(3),
];
const HAND_SIZE = 3;

/** code → { sockets: [creator, joiner|null], started, hands, showdownRequests, readyRequests } */
const rooms = new Map();

function generateCode() {
  let code;
  do {
    code = Array.from({ length: CODE_LENGTH }, () =>
      CODE_ALPHABET[Math.floor(Math.random() * CODE_ALPHABET.length)]
    ).join('');
  } while (rooms.has(code));
  return code;
}

function send(ws, message) {
  if (ws && ws.readyState === ws.OPEN) ws.send(JSON.stringify(message));
}

function opponentOf(room, ws) {
  return room.sockets[0] === ws ? room.sockets[1] : room.sockets[0];
}

function indexOf(room, ws) {
  return room.sockets[0] === ws ? 0 : 1;
}

/** 30장을 섞어 각자 3장씩 배분하고 본인에게만 전송한다 */
function deal(room) {
  const deck = [...FULL_DECK];
  for (let i = deck.length - 1; i > 0; i--) {
    const j = Math.floor(Math.random() * (i + 1));
    [deck[i], deck[j]] = [deck[j], deck[i]];
  }
  room.hands = [deck.slice(0, HAND_SIZE), deck.slice(HAND_SIZE, HAND_SIZE * 2)];
  room.showdownRequests = [false, false];
  room.readyRequests = [false, false];
  room.sockets.forEach((s, i) => send(s, { type: 'hand', cards: room.hands[i] }));
}

// 클라우드(Render 등) 헬스체크용 HTTP 서버 위에 WebSocket을 얹는다
const httpServer = http.createServer((req, res) => {
  if (req.url === '/privacy' || req.url === '/privacy/') {
    res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' });
    res.end(PRIVACY_HTML);
    return;
  }
  // AdMob app-ads.txt (광고 인벤토리 판매 권한 증명)
  if (req.url === '/app-ads.txt') {
    res.writeHead(200, { 'Content-Type': 'text/plain; charset=utf-8' });
    res.end('google.com, pub-1063542820867439, DIRECT, f08c47fec0942fa0\n');
    return;
  }
  // 크롤러 허용 — 없으면 Google이 app-ads.txt 크롤링을 차단된 것으로 판단한다
  if (req.url === '/robots.txt') {
    res.writeHead(200, { 'Content-Type': 'text/plain; charset=utf-8' });
    res.end('User-agent: *\nAllow: /\n');
    return;
  }
  res.writeHead(200, { 'Content-Type': 'text/plain; charset=utf-8' });
  res.end('러브 윈즈 올 서버 동작 중\n');
});
const wss = new WebSocketServer({ server: httpServer });

wss.on('connection', (ws) => {
  ws.roomCode = null;
  ws.isAlive = true;
  ws.on('pong', () => { ws.isAlive = true; });

  ws.on('message', (raw) => {
    let msg;
    try {
      msg = JSON.parse(raw.toString());
    } catch {
      return send(ws, { type: 'error', message: '잘못된 메시지 형식입니다.' });
    }

    switch (msg.type) {
      case 'create': {
        if (ws.roomCode) return send(ws, { type: 'error', message: '이미 방에 있습니다.' });
        const code = generateCode();
        rooms.set(code, {
          sockets: [ws, null],
          started: false,
          hands: null,
          showdownRequests: [false, false],
          readyRequests: [false, false],
        });
        ws.roomCode = code;
        send(ws, { type: 'room', code, player: 0 });
        break;
      }

      case 'join': {
        if (ws.roomCode) return send(ws, { type: 'error', message: '이미 방에 있습니다.' });
        const code = String(msg.code || '').toUpperCase().trim();
        const room = rooms.get(code);
        if (!room) return send(ws, { type: 'error', message: '존재하지 않는 방 코드입니다.' });
        if (room.sockets[1]) return send(ws, { type: 'error', message: '방이 가득 찼습니다.' });
        room.sockets[1] = ws;
        room.started = true;
        ws.roomCode = code;
        send(ws, { type: 'joined', player: 1 });
        // 라운드 1의 선(先) 추첨
        const first = Math.random() < 0.5 ? 0 : 1;
        room.sockets.forEach((s) => send(s, { type: 'start', first }));
        deal(room);
        break;
      }

      case 'move': {
        const room = rooms.get(ws.roomCode);
        if (!room || !room.started) {
          return send(ws, { type: 'error', message: '대국이 시작되지 않았습니다.' });
        }
        send(opponentOf(room, ws), { type: 'move', move: msg.move });
        break;
      }

      case 'showdown': {
        const room = rooms.get(ws.roomCode);
        if (!room || !room.started || !room.hands) return;
        room.showdownRequests[indexOf(room, ws)] = true;
        if (room.showdownRequests[0] && room.showdownRequests[1]) {
          room.sockets.forEach((s) => send(s, { type: 'reveal', hands: room.hands }));
        }
        break;
      }

      case 'ready': {
        const room = rooms.get(ws.roomCode);
        if (!room || !room.started) return;
        room.readyRequests[indexOf(room, ws)] = true;
        if (room.readyRequests[0] && room.readyRequests[1]) {
          deal(room);
        }
        break;
      }

      default:
        send(ws, { type: 'error', message: `알 수 없는 메시지: ${msg.type}` });
    }
  });

  ws.on('close', () => {
    const room = rooms.get(ws.roomCode);
    if (!room) return;
    send(opponentOf(room, ws), { type: 'left' });
    rooms.delete(ws.roomCode);
  });
});

// 30초마다 ping — 응답 없는(끊긴) 연결을 정리해 상대에게 퇴장을 빨리 알린다
setInterval(() => {
  wss.clients.forEach((ws) => {
    if (!ws.isAlive) return ws.terminate();
    ws.isAlive = false;
    ws.ping();
  });
}, 30000);

httpServer.listen(PORT, () => {
  console.log(`러브 윈즈 올 서버 실행 중 — ws://0.0.0.0:${PORT}`);
});
