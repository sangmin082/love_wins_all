import SwiftUI
import UIKit

/// 2인용 로비 — 방을 만들어 코드를 공유하거나, 받은 코드로 입장한다.
/// 서버 주소는 앱에 내장되어 있어 사용자에게 노출되지 않는다.
struct OnlineLobbyView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var client = RoomClient()
    @State private var joinCode = ""
    @State private var game: GameViewModel?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Button {
                        if let url = OnlineConfig.resolvedServerURL() {
                            client.createRoom(serverURL: url)
                        }
                    } label: {
                        Label("새 방 만들기", systemImage: "plus.circle.fill")
                    }
                    .disabled(isBusy)

                    if case .waitingForOpponent(let code) = client.state {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("방 코드")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            HStack {
                                Text(code)
                                    .font(.system(size: 34, weight: .black, design: .monospaced))
                                    .kerning(6)
                                    .textSelection(.enabled)
                                Spacer()
                                Button {
                                    UIPasteboard.general.string = code
                                } label: {
                                    Image(systemName: "doc.on.doc")
                                }
                                // 앱이 없는 친구도 바로 설치할 수 있게 스토어 링크를 함께 보낸다
                                ShareLink(item: "러브 윈즈 올 대결 초대! 방 코드: \(code)\n앱 설치: https://apps.apple.com/app/id6800019846") {
                                    Image(systemName: "square.and.arrow.up")
                                }
                            }
                            Label("상대의 입장을 기다리는 중…", systemImage: "hourglass")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("방 만들기")
                } footer: {
                    Text("방을 만들면 6자리 코드가 생성됩니다. 코드를 친구에게 보내주세요.")
                }

                Section("코드로 입장") {
                    HStack {
                        TextField("방 코드 6자리", text: $joinCode)
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()
                            .onChange(of: joinCode) { _, newValue in
                                joinCode = String(newValue.uppercased().prefix(6))
                            }
                        Button("입장") {
                            if let url = OnlineConfig.resolvedServerURL() {
                                client.joinRoom(code: joinCode, serverURL: url)
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(joinCode.count != 6 || isBusy)
                    }
                }

                if case .failed(let message) = client.state {
                    Section {
                        Label(message, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                    }
                }
                if case .connecting = client.state {
                    Section {
                        VStack(alignment: .leading, spacing: 6) {
                            ProgressView("연결 중…")
                            Text("잠시 걸릴 수 있어요. 서버가 쉬고 있었다면 깨우는 데 최대 1분 정도 걸립니다.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("둘이 하기")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("닫기") {
                        client.close()
                        dismiss()
                    }
                }
            }
            .onChange(of: client.state) { _, newState in
                if case .matched = newState {
                    game = GameViewModel(mode: .online(client))
                }
            }
            .fullScreenCover(item: $game) { game in
                GameView(viewModel: game)
                    .onDisappear {
                        // 대국 화면을 벗어나면 연결 종료 (재대국은 새 방으로)
                        client.close()
                        self.game = nil
                    }
            }
        }
        .preferredColorScheme(.dark)
    }

    private var isBusy: Bool {
        switch client.state {
        case .idle, .failed, .opponentLeft: return false
        case .connecting, .waitingForOpponent, .matched: return true
        }
    }
}
