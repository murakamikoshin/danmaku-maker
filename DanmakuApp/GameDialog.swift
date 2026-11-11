import SwiftUI

/// アプリのデザインに合わせた確認の吹き出し(Apple 標準の alert / confirmationDialog の代わり)。
/// 画面の一番上に、暗くした背景と、テーマの色・字体・角の札を出す。ボタンは縦に並べ、いちばん下が「キャンセル」
struct GameDialogAction: Identifiable {
    enum Role { case normal, destructive, cancel }
    let id = UUID()
    let title: LocalizedStringKey
    var role: Role = .normal
    var action: () -> Void = {}

    static func cancel(_ action: @escaping () -> Void = {}) -> GameDialogAction { GameDialogAction(title: "common.cancel", role: .cancel, action: action) }
    static func ok(_ action: @escaping () -> Void = {}) -> GameDialogAction { GameDialogAction(title: "OK", role: .cancel, action: action) }
}

extension View {
    /// 確認の吹き出しを出す。ボタンを押すと、自動で閉じてから action を呼ぶ
    func gameDialog(_ title: LocalizedStringKey, isPresented: Binding<Bool>, message: LocalizedStringKey? = nil,
                    actions: @escaping () -> [GameDialogAction]) -> some View {
        modifier(GameDialogModifier(title: title, message: message, isPresented: isPresented, actions: actions))
    }
}

private struct GameDialogModifier: ViewModifier {
    let title: LocalizedStringKey
    let message: LocalizedStringKey?
    @Binding var isPresented: Bool
    let actions: () -> [GameDialogAction]

    func body(content: Content) -> some View {
        content.fullScreenCover(isPresented: $isPresented) {
            GameDialogView(title: title, message: message, actions: actions()) { isPresented = false }
                .presentationBackground(.clear)
        }
        // 下からせり上がる標準の動きは使わず、その場でふわっと出す
        .transaction { if isPresented { $0.disablesAnimations = true } }
    }
}

private struct GameDialogView: View {
    let title: LocalizedStringKey
    let message: LocalizedStringKey?
    let actions: [GameDialogAction]
    let close: () -> Void
    @State private var shown = false

    var body: some View {
        ZStack {
            Color.black.opacity(shown ? 0.6 : 0).ignoresSafeArea()
                .onTapGesture { if let c = actions.first(where: { $0.role == .cancel }) { run(c) } }
            VStack(spacing: 14) {
                Text(title).font(.display(18)).foregroundStyle(GameStyle.text)
                    .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                if let message {
                    Text(message).font(.system(size: 13, weight: .semibold)).foregroundStyle(GameStyle.dim)
                        .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                }
                VStack(spacing: 8) {
                    ForEach(sorted) { a in button(a) }
                }
                .padding(.top, 4)
            }
            .padding(.horizontal, 18).padding(.vertical, 20)
            .frame(maxWidth: 340)
            .gamePanel(radius: 18, fill: GameStyle.panel, edge: GameStyle.yellow.opacity(0.6))
            .hardShadow(radius: 18, depth: 5)
            .padding(.horizontal, 28)
            .scaleEffect(shown ? 1 : 0.9).opacity(shown ? 1 : 0)
        }
        .onAppear { withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) { shown = true } }
        .accessibilityAddTraits(.isModal)
    }

    /// キャンセルは一番下
    private var sorted: [GameDialogAction] { actions.filter { $0.role != .cancel } + actions.filter { $0.role == .cancel } }

    private func run(_ a: GameDialogAction) {
        gameTap()
        withAnimation(.easeOut(duration: 0.12)) { shown = false }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            var t = Transaction(); t.disablesAnimations = true
            withTransaction(t) { close() }
            a.action()
        }
    }

    @ViewBuilder private func button(_ a: GameDialogAction) -> some View {
        Button { run(a) } label: {
            Text(a.title).font(.display(15)).lineLimit(2).multilineTextAlignment(.center).minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity).padding(.vertical, 12).padding(.horizontal, 10)
                .modifier(DialogButtonFace(role: a.role))
        }
        .buttonStyle(BounceButtonStyle())
        .accessibilityIdentifier(a.role == .cancel ? "dialog.cancel" : "dialog.action")
    }
}

private struct DialogButtonFace: ViewModifier {
    let role: GameDialogAction.Role
    func body(content: Content) -> some View {
        switch role {
        case .normal: content.keyCap(GameStyle.accent, radius: 12, depth: 3)
        case .destructive: content.keyCap(GameStyle.pinkColor, radius: 12, depth: 3)
        case .cancel:
            content.foregroundStyle(GameStyle.text)
                .background(PixelRect(cornerRadius: 12).fill(GameStyle.panelHi))
                .overlay(PixelRect(cornerRadius: 12).strokeBorder(GameStyle.edge, lineWidth: 1.5))
        }
    }
}
