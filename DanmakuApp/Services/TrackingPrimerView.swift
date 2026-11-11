import SwiftUI

/// トラッキング許可(ATT)の前に1回だけ出す説明画面。
/// Apple の決まりに合わせて、ボタンは「続ける」1つだけ(押すと必ず OS の許可ダイアログに進む)。
/// 許可しないと遊べない・ごほうびがもらえる、のような誘導はしない。OS のダイアログに似せた絵も出さない。
struct TrackingPrimerView: View {
    let onContinue: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "sparkles")
                .font(.system(size: 54, weight: .bold))
                .foregroundStyle(GameStyle.yellow)
            Text("att.primer.title")
                .font(.display(22)).foregroundStyle(GameStyle.text)
                .multilineTextAlignment(.center)
            VStack(alignment: .leading, spacing: 14) {
                row("gamecontroller.fill", "att.primer.free")
                row("person.crop.circle.badge.checkmark", "att.primer.allow")
                row("checkmark.shield.fill", "att.primer.optional")
            }
            .padding(16)
            .background(GameStyle.panel, in: PixelRect(cornerRadius: 14))
            GameActionButton(title: "att.primer.continue", systemImage: "arrow.right", fill: GameStyle.gold, action: onContinue)
                .accessibilityIdentifier("att.primer.continue")
            Spacer()
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: 520)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(GameStyle.night.ignoresSafeArea())
    }

    private func row(_ symbol: String, _ text: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .bold)).foregroundStyle(GameStyle.cyanColor)
                .frame(width: 26)
            Text(text)
                .font(.system(size: 15, weight: .semibold)).foregroundStyle(GameStyle.text.opacity(0.9))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
