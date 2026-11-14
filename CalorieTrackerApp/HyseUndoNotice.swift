import SwiftUI

struct HyseUndoNotice: View {
    let title: String
    let detail: String?
    let actionTitle: String
    let action: () -> Void

    var body: some View {
        HStack(spacing: HyseSpacing.medium) {
            Image(systemName: "arrow.uturn.backward")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(HyseColor.accent)
                .frame(width: 36, height: 36)
                .background(HyseColor.accent.opacity(0.12), in: Circle())
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                if let detail, !detail.isEmpty {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button(actionTitle, action: action)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(HyseColor.accent)
                .padding(.horizontal, HyseSpacing.large)
                .frame(minHeight: 44)
                .background(HyseColor.accent.opacity(0.12), in: Capsule())
                .buttonStyle(.plain)
        }
        .padding(.leading, HyseSpacing.medium)
        .padding(.trailing, HyseSpacing.small)
        .padding(.vertical, HyseSpacing.small)
        .background(HyseColor.elevatedSurface, in: RoundedRectangle(cornerRadius: HyseRadius.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: HyseRadius.card, style: .continuous).stroke(HyseColor.border))
        .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
        .padding(.horizontal, HyseSpacing.page)
        .accessibilityElement(children: .contain)
    }
}
