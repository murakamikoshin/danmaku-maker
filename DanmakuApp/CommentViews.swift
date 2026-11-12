import SwiftUI

/// ステージ詳細の「コメント」。通報・ブロック・削除ができる
struct CommentsSection: View {
    let stageID: String
    let authorUid: String
    @EnvironmentObject private var auth: AuthService
    @ObservedObject private var badges = ProfileBadgeStore.shared
    @EnvironmentObject private var blocks: BlockStore
    @ObservedObject private var handles = HandleStore.shared
    @ObservedObject private var names = DisplayNameStore.shared
    @State private var comments: [StageComment] = []
    /// 「…」を押したコメント(自前の吹き出しで、削除・通報・ブロックを選ぶ)
    @State private var menuFor: StageComment?
    @State private var loading = true
    @State private var failed = false
    @State private var text = ""
    @State private var sending = false
    @State private var errorKey: String?
    @State private var needSignIn = false
    @State private var reporting: StageComment?
    @State private var blocking: StageComment?

    private var visible: [StageComment] { comments.filter { !blocks.isBlocked($0.uid) } }

    var body: some View {
        GamePanel(title: "comment.title", tint: GameStyle.cyanColor) {
            composer
            if let errorKey { Text(LocalizedStringKey(errorKey)).font(.system(size: 12, weight: .semibold)).foregroundStyle(GameStyle.pinkColor) }
            if loading {
                HStack { Spacer(); ProgressView().tint(GameStyle.pinkColor); Spacer() }.padding(.vertical, 8)
            } else if failed {
                Text("error.network").font(.footnote).foregroundStyle(.secondary)
            } else if visible.isEmpty {
                Text("comment.empty").font(.footnote).foregroundStyle(.secondary).padding(.vertical, 6)
            } else {
                VStack(spacing: 8) { ForEach(visible) { row($0) } }
            }
        }
        .task { await load() }
        .sheet(isPresented: $needSignIn) { SignInSheet() }
        .gameDialog("comment.menu.title", isPresented: Binding(get: { menuFor != nil }, set: { if !$0 { menuFor = nil } })) {
            guard let c = menuFor else { return [.cancel()] }
            let mine = c.uid == auth.uid
            var list: [GameDialogAction] = []
            if mine || auth.uid == authorUid { list.append(GameDialogAction(title: "comment.delete", role: .destructive) { Task { await remove(c) } }) }
            if !mine {
                list.append(GameDialogAction(title: "comment.report") { reporting = c })
                list.append(GameDialogAction(title: "comment.block", role: .destructive) { blocking = c })
            }
            return list + [.cancel()]
        }
        .gameDialog("comment.report.title", isPresented: Binding(get: { reporting != nil }, set: { if !$0 { reporting = nil } })) {
            // 押したときの対象を、閉じる前に覚えておく(閉じると reporting が nil になるため)
            let target = reporting
            return [GameDialogAction(title: "report.reason.inappropriate_name") { reporting = target; report("inappropriate_name") },
                    GameDialogAction(title: "report.reason.other") { reporting = target; report("other") }, .cancel()]
        }
        .gameDialog("detail.block.title", isPresented: Binding(get: { blocking != nil }, set: { if !$0 { blocking = nil } }), message: "detail.block.message") {
            let target = blocking
            return [GameDialogAction(title: "detail.block", role: .destructive) { if let c = target { blocks.block(uid: c.uid, name: c.displayName) } }, .cancel()]
        }
    }

    @ViewBuilder private var composer: some View {
        if auth.isMember {
            HStack(alignment: .bottom, spacing: 8) {
                // 改行できる(5行まで)。送るのは右のボタン
                CompatMultilineField(text: $text, prompt: "comment.placeholder", minLines: 1, maxLines: 5)
                    .textFieldStyle(.plain)
                    .font(.system(size: 15, weight: .semibold))
                    .padding(.vertical, 10).padding(.horizontal, 12)
                    .background(GameStyle.panelHi, in: PixelRect(cornerRadius: 12))
                    .overlay(PixelRect(cornerRadius: 12).stroke(GameStyle.edge))
                    .onChange(of: text) { v in
                        let fixed = MultilineText.limited(v, maxLength: CommentService.maxLength, maxLines: CommentService.maxLines)
                        if fixed != v { text = fixed }
                    }
                    .accessibilityIdentifier("comment.field")
                Button { gameTap(); Task { await send() } } label: {
                    Image(systemName: "paperplane.fill").font(.system(size: 16, weight: .heavy)).foregroundStyle(GameStyle.ink)
                        .frame(width: 44, height: 44)
                        .background(KeyCap(fill: GameStyle.accent, radius: 10, depth: 3)).padding(.bottom, 3)
                }
                .buttonStyle(BounceButtonStyle())
                .opacity(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || sending ? 0.4 : 1)
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || sending)
                .accessibilityLabel(Text("comment.send"))
                .accessibilityIdentifier("comment.send")
            }
            Text("comment.rules").font(.system(size: 10)).foregroundStyle(.secondary)
        } else {
            Button { gameTap(); needSignIn = true } label: { Chip(title: L("comment.signin"), selected: true) }.buttonStyle(BounceButtonStyle())
        }
    }

    private func row(_ c: StageComment) -> some View {
        let mine = c.uid == auth.uid
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                BadgedName(name: c.displayName, badge: badges.badge(c.uid), size: 12, weight: .heavy, baseColor: GameStyle.yellow, inlineChip: true)
                if c.uid == authorUid {
                    Text("comment.author").font(.system(size: 9, weight: .heavy)).foregroundStyle(GameStyle.ink)
                        .padding(.horizontal, 6).padding(.vertical, 1).background(GameStyle.pinkColor, in: PixelRect(cornerRadius: 8))
                }
                Spacer()
                if let d = c.createdAt { Text(d, style: .relative).font(.system(size: 10)).foregroundStyle(.secondary) }
                Button { gameTap(); menuFor = c } label: {
                    Image(systemName: "ellipsis").font(.system(size: 13, weight: .bold)).foregroundStyle(.secondary).frame(width: 28, height: 22)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("comment.menu")
            }
            Text(c.text).font(.system(size: 14, weight: .medium)).foregroundStyle(GameStyle.text)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(10)
        .background(mine ? GameStyle.pinkColor.opacity(0.12) : Color.white.opacity(0.05), in: PixelRect(cornerRadius: 12))
    }

    private func load() async {
        loading = true; failed = false
        do { comments = try await CommentService.list(stageID: stageID); badges.request(comments.map(\.uid)) } catch { failed = true }
        loading = false
    }

    private func send() async {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, !sending else { return }
        guard auth.isMember else { needSignIn = true; return }
        sending = true; errorKey = nil
        do {
            try await CommentService.post(stageID: stageID, text: t, handle: handles.handle, name: names.publicName)
            text = ""
            await load()
        } catch CommentError.ngWord { errorKey = "comment.error.ng" }
        catch CommentError.link { errorKey = "comment.error.link" }
        catch CommentError.tooLong { errorKey = "comment.error.length" }
        catch CommentError.tooFast { errorKey = "comment.error.tooFast" }
        catch CommentError.badName { errorKey = "name.error.invalid" }
        catch CommentError.signIn { needSignIn = true }
        catch { errorKey = "error.network" }
        sending = false
    }

    private func remove(_ c: StageComment) async {
        try? await CommentService.delete(stageID: stageID, commentID: c.id)
        await load()
    }

    private func report(_ reason: String) {
        guard let c = reporting else { return }
        Task {
            if !auth.isMember { needSignIn = true; return }
            try? await CommentService.report(stageID: stageID, commentID: c.id, reason: reason)
            await load()
        }
    }
}
