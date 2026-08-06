import Foundation
import Observation

/// 2인용 온라인 대전 클라이언트.
/// `server/` 디렉터리의 서버와 WebSocket(JSON)으로 통신한다.
/// 방을 만들면 6자리 방코드를 받고, 상대가 코드로 입장하면 대국이 시작된다.
///
/// 서버는 베팅·선언 무브는 해석 없이 릴레이하고, 카드만 직접 다룬다:
/// 라운드마다 30장을 섞어 각자에게 자기 손패 3장만 보내고(`hand`),
/// 양쪽이 쇼다운을 요청하면 두 손패를 공개한다(`reveal`).
@Observable
@MainActor
final class RoomClient {
    enum ConnectionState: Equatable {
        case idle
        case connecting
        /// 방 생성 완료 — 상대 입장 대기 중
        case waitingForOpponent(code: String)
        /// 매칭 완료 — 내 엔진 플레이어 배정
        case matched(me: Player)
        case opponentLeft
        case failed(String)
    }

    private(set) var state: ConnectionState = .idle
    /// 상대의 무브가 도착하면 호출된다
    var onRemoteMove: ((Move) -> Void)?
    /// 새 라운드의 내 손패가 도착하면 호출된다.
    /// (매칭 직후 서버가 start와 hand를 연달아 보내므로, 뷰모델이 콜백을 등록하기 전에
    ///  도착한 손패는 버퍼에 보관했다가 등록 시점에 전달한다)
    var onHand: (([Card]) -> Void)? {
        didSet {
            if let cards = pendingHand, let onHand {
                pendingHand = nil
                onHand(cards)
            }
        }
    }
    private var pendingHand: [Card]?
    /// 쇼다운 공개(양쪽 손패)가 도착하면 호출된다
    var onReveal: (([[Card]]) -> Void)?
    /// 상대가 방을 나가거나 연결이 끊기면 호출된다
    var onOpponentLeft: (() -> Void)?

    private var task: URLSessionWebSocketTask?
    private var myIndex: Int?

    // MARK: 서버 프로토콜 메시지

    private struct ServerMessage: Decodable {
        let type: String
        let code: String?
        let player: Int?
        let first: Int?
        let move: Move?
        let cards: [Card]?
        let hands: [[Card]]?
        let message: String?
    }

    private struct ClientMessage: Encodable {
        let type: String
        var code: String? = nil
        var move: Move? = nil
    }

    // MARK: 연결

    func createRoom(serverURL: URL) {
        connect(serverURL: serverURL) { [weak self] in
            await self?.send(ClientMessage(type: "create"))
        }
    }

    func joinRoom(code: String, serverURL: URL) {
        let normalized = code.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
        connect(serverURL: serverURL) { [weak self] in
            await self?.send(ClientMessage(type: "join", code: normalized))
        }
    }

    private func connect(serverURL: URL, then onOpen: @escaping () async -> Void) {
        close()
        state = .connecting
        let task = URLSession.shared.webSocketTask(with: serverURL)
        self.task = task
        task.resume()
        Task {
            await onOpen()
            await receiveLoop(task)
        }
    }

    func send(move: Move) {
        Task { await send(ClientMessage(type: "move", move: move)) }
    }

    /// 2차 베팅 종료 — 서버에 손패 공개를 요청한다 (양쪽 요청이 모이면 reveal 수신)
    func requestShowdown() {
        Task { await send(ClientMessage(type: "showdown")) }
    }

    /// 다음 라운드 준비 완료 (양쪽 준비가 모이면 새 hand 수신)
    func sendReady() {
        Task { await send(ClientMessage(type: "ready")) }
    }

    func close() {
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
        myIndex = nil
        pendingHand = nil
        state = .idle
    }

    // MARK: 수신 루프

    private func receiveLoop(_ task: URLSessionWebSocketTask) async {
        while self.task === task {
            do {
                let message = try await task.receive()
                let data: Data
                switch message {
                case .string(let text): data = Data(text.utf8)
                case .data(let d): data = d
                @unknown default: continue
                }
                handle(try JSONDecoder().decode(ServerMessage.self, from: data))
            } catch {
                if self.task === task {
                    if case .matched = state {
                        state = .opponentLeft
                        onOpponentLeft?()
                    } else if case .waitingForOpponent = state {
                        state = .failed("서버와 연결이 끊어졌습니다.")
                    } else if case .connecting = state {
                        state = .failed("서버에 연결할 수 없습니다. 주소를 확인해 주세요.")
                    }
                    self.task = nil
                }
                return
            }
        }
    }

    private func handle(_ msg: ServerMessage) {
        switch msg.type {
        case "room":
            myIndex = msg.player
            if let code = msg.code { state = .waitingForOpponent(code: code) }
        case "joined":
            myIndex = msg.player
        case "start":
            // first = 라운드 1 선의 인덱스. 내가 선이면 엔진의 .first를 맡는다.
            guard let myIndex, let first = msg.first else { return }
            let me: Player = (myIndex == first) ? .first : .second
            state = .matched(me: me)
        case "hand":
            if let cards = msg.cards {
                if let onHand {
                    onHand(cards)
                } else {
                    pendingHand = cards
                }
            }
        case "reveal":
            if let hands = msg.hands, hands.count == 2 { onReveal?(hands) }
        case "move":
            if let move = msg.move { onRemoteMove?(move) }
        case "left":
            state = .opponentLeft
            onOpponentLeft?()
        case "error":
            state = .failed(msg.message ?? "알 수 없는 오류")
        default:
            break
        }
    }

    private func send(_ message: ClientMessage) async {
        guard let task else { return }
        do {
            let data = try JSONEncoder().encode(message)
            try await task.send(.string(String(decoding: data, as: UTF8.self)))
        } catch {
            state = .failed("전송 실패: \(error.localizedDescription)")
        }
    }
}
