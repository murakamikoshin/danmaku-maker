import PhotosUI
import SwiftUI
import UIKit

// iOS 15・16 の古い iPhone / iPad(iPad mini 4・iPhone 6s など)でも動かすための、新旧の書き方の切り替え。
// iOS 16 以降は標準の部品をそのまま使い、それより古い iOS では、同じことをする古い書き方に置き換える。
// 画面のコードは、ここの名前(compat〜)を使う。

extension View {
    /// 数字が変わるときに、くるっと切り替わる動き(iOS 16 以降だけ。古い iOS では普通に切り替わる)
    @ViewBuilder func compatNumericTransition() -> some View {
        if #available(iOS 16.0, *) { self.contentTransition(.numericText()) } else { self }
    }

    /// 中身が画面に収まるときは、引っぱっても弾まない(iOS 16.4 以降だけ)
    @ViewBuilder func compatBounceBasedOnSize() -> some View {
        if #available(iOS 16.4, *) { self.scrollBounceBehavior(.basedOnSize) } else { self }
    }

    /// スクロールすると、キーボードが下がる(iOS 16 以降だけ)
    @ViewBuilder func compatDismissKeyboardOnScroll() -> some View {
        if #available(iOS 16.0, *) { self.scrollDismissesKeyboard(.interactively) } else { self }
    }

    /// 上のナビゲーションバーを隠す
    @ViewBuilder func compatHideNavigationBar() -> some View {
        if #available(iOS 16.0, *) { self.toolbar(.hidden, for: .navigationBar) } else { self.navigationBarHidden(true) }
    }

    /// 下から出る画面を、半分の高さにする(iOS 15 では全体の高さで出る)
    @ViewBuilder func compatMediumSheet() -> some View {
        if #available(iOS 16.0, *) { self.presentationDetents([.medium]) } else { self }
    }

    /// 下から出る画面を、全体の高さにする(iOS 15 は、もともと全体の高さ)
    @ViewBuilder func compatLargeSheet() -> some View {
        if #available(iOS 16.0, *) { self.presentationDetents([.large]) } else { self }
    }

    /// 全画面で出す画面の背景を透明にする(後ろの画面が透けて見える)
    @ViewBuilder func compatClearPresentationBackground() -> some View {
        if #available(iOS 16.4, *) { self.presentationBackground(.clear) } else { self.background(ClearPresentationBackground()) }
    }

    /// 文字入力欄(TextEditor)の白い背景を消す
    @ViewBuilder func compatHideTextEditorBackground() -> some View {
        if #available(iOS 16.0, *) {
            self.scrollContentBackground(.hidden)
        } else {
            self.onAppear { UITextView.appearance().backgroundColor = .clear }
        }
    }
}

/// iOS 16.4 より前で、全画面の画面の背景を透明にする(表示された画面の、外側の入れ物の背景を消す)
private struct ClearPresentationBackground: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView { Probe() }
    func updateUIView(_ uiView: UIView, context: Context) {}

    private final class Probe: UIView {
        override func didMoveToWindow() {
            super.didMoveToWindow()
            DispatchQueue.main.async { [weak self] in
                var v = self?.superview
                while let view = v {
                    view.backgroundColor = .clear
                    if view.next is UIViewController { break }
                    v = view.superview
                }
            }
        }
    }
}

/// 画面の移動の入れ物(iOS 16 以降は NavigationStack、古い iOS は NavigationView を1列で使う)
struct CompatNavigationStack<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        if #available(iOS 16.0, *) {
            NavigationStack(root: content)
        } else {
            NavigationView(content: content).navigationViewStyle(.stack)
        }
    }
}

/// 共有ボタン(iOS 16 以降は ShareLink、古い iOS は共有シートを直接出す)
struct CompatShareLink<Label: View>: View {
    private let text: String?
    private let url: URL?
    private let message: String?
    private let label: () -> Label

    init(item: String, @ViewBuilder label: @escaping () -> Label) {
        self.text = item; self.url = nil; self.message = nil; self.label = label
    }

    init(item: URL, message: String, @ViewBuilder label: @escaping () -> Label) {
        self.text = nil; self.url = item; self.message = message; self.label = label
    }

    var body: some View {
        if #available(iOS 16.0, *) {
            if let url {
                ShareLink(item: url, message: Text(message ?? ""), label: label)
            } else {
                ShareLink(item: text ?? "", label: label)
            }
        } else {
            Button {
                let items: [Any] = [message as Any?, url as Any?, text as Any?].compactMap { $0 }
                LegacyShareSheet.present(items)
            } label: { label() }
        }
    }
}

extension View {
    /// 読み上げ(VoiceOver)で「切り替えボタン」と伝える(iOS 17 以降だけ)
    @ViewBuilder func compatToggleTrait() -> some View {
        if #available(iOS 17.0, *) { self.accessibilityAddTraits(.isToggle) } else { self }
    }
}

/// 画面の部品を画像にする(iOS 16 以降は ImageRenderer、古い iOS は画面の外で描いて写す)
@MainActor func compatRenderImage<V: View>(_ view: V, scale: CGFloat) -> UIImage? {
    if #available(iOS 16.0, *) {
        let r = ImageRenderer(content: view)
        r.scale = scale
        return r.uiImage
    }
    let host = UIHostingController(rootView: view)
    let size = host.sizeThatFits(in: CGSize(width: 2000, height: 2000))
    guard size.width > 0, size.height > 0 else { return nil }
    host.view.bounds = CGRect(origin: .zero, size: size)
    host.view.backgroundColor = .clear
    host.view.layoutIfNeeded()
    let format = UIGraphicsImageRendererFormat()
    format.scale = scale
    return UIGraphicsImageRenderer(size: size, format: format).image { _ in
        host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true)
    }
}

/// メインスレッドで呼ばれていると分かっている所で、画面用(MainActor)の値を読む。
/// iOS 17 以降は標準の MainActor.assumeIsolated。古い iOS では、メインスレッドかを確かめてからそのまま呼ぶ
func compatAssumeMainActor<T: Sendable>(_ body: @MainActor () throws -> T) rethrows -> T {
    if #available(iOS 17.0, *) { return try MainActor.assumeIsolated(body) }
    precondition(Thread.isMainThread, "メインスレッド以外から呼ばれた")
    return try withoutActuallyEscaping(body) { fn in
        try unsafeBitCast(fn, to: (() throws -> T).self)()
    }
}

@MainActor
private enum LegacyShareSheet {
    static func present(_ items: [Any]) {
        guard let top = AdsService.topViewController() else { return }
        let sheet = UIActivityViewController(activityItems: items, applicationActivities: nil)
        // iPad では、吹き出しの出どころを指定しないと落ちる。画面の下の真ん中から出す
        if let pop = sheet.popoverPresentationController {
            pop.sourceView = top.view
            pop.sourceRect = CGRect(x: top.view.bounds.midX, y: top.view.bounds.maxY - 80, width: 1, height: 1)
            pop.permittedArrowDirections = []
        }
        top.present(sheet, animated: true)
    }
}

/// 写真を1枚選ぶ画面(iOS 14 から使える PHPicker。iOS 15 でも 17 でも同じ画面)
/// 選んだら onPick に画像(読めなかったときは nil)を渡す。何も選ばずに閉じたときは、onPick を呼ばない
struct PhotoPickerSheet: UIViewControllerRepresentable {
    @Binding var isPresented: Bool
    let onPick: (UIImage?) -> Void

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration()
        config.filter = .images
        config.selectionLimit = 1
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let parent: PhotoPickerSheet
        init(parent: PhotoPickerSheet) { self.parent = parent }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            parent.isPresented = false
            let onPick = parent.onPick
            // 何も選ばずに閉じたときは、何もしない
            guard let provider = results.first?.itemProvider else { return }
            guard provider.canLoadObject(ofClass: UIImage.self) else { onPick(nil); return }
            provider.loadObject(ofClass: UIImage.self) { obj, _ in
                let image = obj as? UIImage
                DispatchQueue.main.async { onPick(image) }
            }
        }
    }
}
