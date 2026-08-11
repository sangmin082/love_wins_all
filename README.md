# 💘 러브 윈즈 올 (Love Wins All)

넷플릭스 예능 **〈데스게임〉**의 게임 "러브 윈즈 올"을 iOS 게임으로 구현한 프로젝트입니다.
[기억의 만찬(feast_of_memory)](https://github.com/sangmin082/feast_of_memory)과 동일한 아키텍처를 사용합니다.

- **1인용** — AI와 베팅 심리전 (난이도 3단계). AI는 몬테카를로 승률 추정 + 블러핑 모델로 플레이합니다.
- **연습 게임** — 칩 20개로 규칙을 익히는 모드 (전적 미기록)
- **2인용** — 방을 만들면 6자리 방코드가 생성되고, 친구가 코드를 입력해 입장하면 실시간 온라인 대결이 시작됩니다.

## 게임 규칙

> 가위바위보 승부와 베팅으로 상대의 칩 25개를 전부 빼앗으면 승리.

- **카드 (30장)**: 가위 12 · 바위 7 · 보 7 · 러브 4 — 매 라운드 전체를 섞어 3장씩 배분
- **족보 (높은 순)**: ① 러브 윈즈 올(러브 3장) ② 트리플(같은 가위바위보 3장) ③ 투 러브(러브 2장) ④ 믹스(가위·바위·보 각 1장) ⑤ 더블(러브 없이 페어) ⑥ 원 러브(러브 1장)
- **동순위**: 가위바위보 상성으로 승부, 무승부면 나머지 카드의 상성. 투 러브끼리는 나머지 1장, 원 러브끼리는 무승부.
- **라운드**: 앤티 1개 → 카드 3장 → 1차 베팅 → 카드 1장 오픈 + 족보 선언(**거짓 선언 가능!**) → 2차 베팅 → 쇼다운. 무승부 팟은 다음 라운드로 이월, 폴드 시 카드 비공개.
- **선(先)**: 1라운드는 추첨, 이후는 직전 라운드 승자.

## 프로젝트 구조

```
LoveWinsAll.xcodeproj        Xcode 16+ 프로젝트
LoveWinsAll/
├── App/LoveWinsAllApp.swift
├── Game/
│   ├── GameEngine.swift     규칙 상태기계 (순수 값 타입 — 양쪽 기기에서 동일 재현)
│   ├── HandEvaluator.swift  족보 판정·비교 (순수 함수 — 전수 테스트 대상)
│   ├── AIPlayer.swift       몬테카를로 승률 + 블러핑 모델 AI (쉬움/보통/어려움)
│   ├── GameViewModel.swift  대국 진행, 베팅/선언 UI 상태, 60초 턴 타이머
│   └── EngineSelfTest.swift 족보 전수 테스트 + 베팅 시나리오 + AI 자동 대국 불변식 (DEBUG)
├── Online/RoomClient.swift  WebSocket 클라이언트 (방 생성/코드 입장/무브 릴레이/딜링 수신)
└── Views/                   홈, 대국 화면(카드·팟·베팅 UI), 온라인 로비, 규칙, 전적, 설정
server/
├── index.js                 2인용 서버 (Node.js + ws) — 릴레이 + 딜러 역할
└── test.js                  서버 통합 테스트
```

### 온라인 동기화 설계

기억의 만찬은 모든 정보가 공개라 순수 릴레이로 충분했지만, 이 게임은 **손패가 비공개**입니다.
클라이언트가 카드를 만들면 상대 앱 메모리에 내 패가 노출되므로 **서버가 딜러 역할**을 겸합니다:

- 라운드마다 서버가 30장을 섞어 각자에게 **자기 손패 3장만** 전송 (`hand`)
- 베팅·선언 무브는 해석 없이 상대에게 릴레이 (엔진이 결정적이라 양쪽 상태가 항상 일치)
- 2차 베팅이 끝나 양쪽이 쇼다운을 요청하면 두 손패를 공개 (`reveal`) — 폴드 라운드는 공개하지 않음
- 쇼다운에서 "오픈했던 카드가 실제 손패에 없는" 변조가 감지되면 해당 플레이어 즉시 패배

## 실행 방법

### iOS 앱 (Xcode 16 이상, iOS 17+)

```bash
open LoveWinsAll.xcodeproj
```

시뮬레이터나 기기에서 Run. DEBUG 빌드는 시작 시 엔진 셀프테스트(족보 전수 검증 + 시나리오 리플레이 + AI 자동 대국 불변식)를 자동 실행합니다.

### 2인용 서버

앱에는 기본 서버 주소(`OnlineConfig.defaultServerURLString`)가 내장되어 있어 사용자는 방 코드만 주고받으면 됩니다.

**클라우드 배포 (Render 무료 티어)**

1. [render.com](https://render.com) 가입 (GitHub 로그인)
2. New → **Blueprint** → 이 저장소 연결 → `render.yaml`이 자동 인식됨 → Deploy
3. 배포 완료 후 주소 확인 (서비스 이름이 `love-wins-all`이면 `wss://love-wins-all-opgx.onrender.com`)
4. 주소가 다르면 `LoveWinsAll/Online/OnlineConfig.swift`의 기본 주소를 수정

무료 티어는 15분간 접속이 없으면 잠들며, 다음 접속 시 깨어나는 데 최대 1분 걸립니다 (로비에 안내 문구 표시됨).
`.github/workflows/keepalive.yml`이 10분마다 핑을 보내 슬립을 방지합니다.

**로컬 실행/테스트**

```bash
cd server
npm install
npm start        # ws://0.0.0.0:8080  (헬스체크: http://localhost:8080)
npm test         # 통합 테스트
```

## TestFlight 배포 (Mac 불필요 — GitHub Actions)

`.github/workflows/testflight.yml`이 macOS 러너에서 빌드·서명 후 TestFlight에 업로드합니다.
인증서/프로비저닝 프로파일은 [fastlane match](https://docs.fastlane.tools/actions/match/)가
CI에서 자동 생성해 별도 private repo에 보관하므로 Mac이 전혀 필요 없습니다.
필요한 GitHub Secrets와 상세 절차는 [docs/APP_STORE.md](docs/APP_STORE.md)를 참고하세요.
(번들 ID: `com.lovewinsall.game`)

### Secrets 재사용 (여러 앱을 만들 때)

TestFlight Secrets 7개는 전부 **계정 공통 값**이라 앱마다 다시 입력할 필요가 없습니다. 두 가지 방법:

- **스크립트 (개인 계정 그대로)** — 값을 로컬 파일에 한 번만 적어 두고, 새 저장소마다 한 줄로 등록:
  ```bash
  cp scripts/ios-secrets.env.example ~/.config/ios-secrets.env   # 최초 1회, 값 채우기
  ./scripts/setup-secrets.sh sangmin082/새앱저장소                # 새 앱마다 이 한 줄
  ```
  (GitHub CLI 필요: `brew install gh && gh auth login`)
- **Organization (아예 입력 제거)** — 무료 org를 만들어 앱 저장소들을 그 아래에 두면,
  org Settings → Secrets and variables → Actions에 **한 번만** 등록해 두고 모든 저장소가 자동으로 공유합니다
  (visibility: All repositories). 기존 저장소는 Settings → Transfer ownership으로 옮기면 되고, 옛 주소는 자동 리다이렉트됩니다.

## 수익화 (AdMob + 광고 제거 IAP)

- **전면 광고** — 노출 지점은 "매치 종료 후 결과 화면에서 나갈 때" 한 곳뿐 (2판당 1회, 최소 3분 간격). 심리전 게임 특성상 게임 도중에는 절대 노출하지 않습니다.
- **광고 제거** — 비소모성 IAP `com.lovewinsall.game.removeads`. 설정(⚙️)에서 구매/복원. StoreKit 2 영수증 검증.
- 광고 ID는 실제 AdMob ID가 설정되어 있습니다. 개발 중 테스트 광고가 필요하면
  AdMob 콘솔에서 기기를 테스트 기기로 등록하거나 `MonetizationConfig.swift`의 주석에 있는 Google 테스트 ID로 잠시 교체하세요.
- IAP 판매를 위해서는 App Store Connect에서 **유료 앱 계약(Paid Apps) + 은행/세금 등록**과 IAP 상품 등록이 선행되어야 합니다.

## 구현 노트 (규칙 해석)

방송 규칙에 명시되지 않은 부분은 다음과 같이 정했습니다 (자세한 근거는 [PLAN.md](PLAN.md)):

- **덱**: 매 라운드 30장 전체를 리셔플 후 3+3장 배분
- **베팅**: 노리밋 헤즈업 — 베팅 상한은 양쪽 스택의 실효 한도(상대가 콜 가능한 만큼). 올인 뒤 남은 베팅 단계는 자동 생략
- **선언**: 오픈한 카드와 모순되지 않는 족보는 무엇이든 선언 가능 (러브를 열고 "믹스" 선언 같은 자기모순만 차단)
- **무승부 세부**: 같은 타입 트리플끼리·믹스끼리도 무승부(팟 이월), 무승부 시 선 유지
- **매치 종료**: 라운드 종료 시 스택이 0인 쪽 패배. 단, 올인 무승부로 이월 팟이 남았으면 앤티·베팅 없이 쇼다운만으로 계속 진행
- **턴 타이머**: 방송 규칙에는 없지만 온라인 잠수 방지를 위해 행동당 60초 (초과 시 체크/폴드, 선언은 실제 족보로 자동 처리)
