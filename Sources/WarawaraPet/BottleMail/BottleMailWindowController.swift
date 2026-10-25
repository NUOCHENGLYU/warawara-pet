import AppKit
import SwiftUI

/// Phase 8B user-facing window: device activation (the graphical entry
/// a normal user needs) plus a minimal mailbox listing. This is the
/// temporary 8B UI — the pretty bottle delivery/reading experience is
/// Phase 8C and will reuse the same coordinator.
final class BottleMailWindowController: NSWindowController {
    private let coordinator: BottleMailCoordinator

    init(coordinator: BottleMailCoordinator) {
        self.coordinator = coordinator
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 480),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Bottle Mail"
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.contentView = NSHostingView(rootView: BottleMailView(coordinator: coordinator))
        window.center()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func toggle() {
        guard let window else { return }
        if window.isVisible {
            window.orderOut(nil)
        } else {
            showWindow(nil)
            // Reading the activation code needs real keyboard input, so
            // this window is allowed to become key (explicit user action
            // only — the pet itself never grabs focus).
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
        }
    }
}

struct BottleMailView: View {
    @ObservedObject var coordinator: BottleMailCoordinator
    @State private var code = ""
    @State private var label = ""
    @State private var activationMessage = ""
    @State private var selectedLetter: BottleMailLetter?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            Divider()
            content
            Spacer(minLength: 0)
            footer
        }
        .padding(14)
        .frame(width: 440, height: 480)
    }

    @ViewBuilder
    private var header: some View {
        HStack {
            Image(systemName: "envelope.open.fill")
                .foregroundColor(.accentColor)
            Text("Bottle Mail")
                .font(.headline)
            Spacer()
            Button("立即检查") {
                coordinator.pollNow()
            }
            .disabled(!coordinator.isActivated)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch coordinator.activationState {
        case .notActivated, .activating:
            activationForm
        case .activated(let deviceLabel):
            VStack(alignment: .leading, spacing: 6) {
                Text("已绑定设备：\(deviceLabel)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                letterList
            }
        case .revoked:
            VStack(alignment: .leading, spacing: 8) {
                Label("设备授权已被发送者撤销", systemImage: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
                Text("已收到的信件仍保留在本机。如需继续收信，请向发送者要一个新的激活码并重新绑定。")
                    .font(.caption)
                    .foregroundColor(.secondary)
                activationForm
            }
        }
    }

    private var activationForm: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("在发信网页生成一个激活码，粘贴到这里完成绑定。")
                .font(.caption)
                .foregroundColor(.secondary)
            TextField("激活码", text: $code)
                .textFieldStyle(.roundedBorder)
            TextField("设备名称（可选）", text: $label)
                .textFieldStyle(.roundedBorder)
            Button {
                activate()
            } label: {
                if coordinator.activationState == .activating {
                    ProgressView().controlSize(.small)
                } else {
                    Text("绑定设备")
                }
            }
            .disabled(code.trimmingCharacters(in: .whitespaces).isEmpty
                      || coordinator.activationState == .activating)
            if !activationMessage.isEmpty {
                Text(activationMessage)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    private var letterList: some View {
        List(selection: $selectedLetter) {
            ForEach(coordinator.letters) { letter in
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        if letter.isUnread {
                            Circle().fill(Color.accentColor).frame(width: 7, height: 7)
                        }
                        Text(letter.body.prefix(60))
                            .lineLimit(1)
                            .font(.system(size: 12))
                        Spacer()
                        Text(letter.createdAt)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.vertical, 2)
                .tag(letter)
            }
        }
        .overlay {
            if coordinator.letters.isEmpty {
                Text("还没有收到信件")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    @ViewBuilder
    private var footer: some View {
        HStack {
            Text("未读 \(coordinator.unreadCount) · 共 \(coordinator.letters.count) 封")
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
            if let letter = selectedLetter {
                Button("标为已读") {
                    coordinator.markOpened(letterID: letter.id)
                    if let index = coordinator.letters.firstIndex(where: { $0.id == letter.id }) {
                        selectedLetter = coordinator.letters[index]
                    }
                }
                .disabled(!letter.isUnread)
            }
        }
        if let error = coordinator.lastSyncError {
            Text("同步：\(error)")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        if coordinator.pendingDeliveryCount > 0 {
            Text("有 \(coordinator.pendingDeliveryCount) 封信件等待宠物空闲后送达")
                .font(.caption2)
                .foregroundColor(.orange)
        }
    }

    private func activate() {
        activationMessage = ""
        let trimmedCode = code.trimmingCharacters(in: .whitespacesAndNewlines)
        let deviceLabel = label.trimmingCharacters(in: .whitespaces).isEmpty
            ? "Warawara"
            : label.trimmingCharacters(in: .whitespaces)
        Task {
            do {
                try await coordinator.activate(code: trimmedCode, label: deviceLabel)
                code = ""
            } catch let error as BottleMailActivationError {
                activationMessage = error.message
            } catch {
                activationMessage = "绑定失败，请重试。"
            }
        }
    }
}
