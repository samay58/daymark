import SwiftUI

struct SidebarView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            wordmark
                .padding(.top, 34)
                .padding(.horizontal, 18)
                .padding(.bottom, 18)

            VStack(spacing: 3) {
                ForEach(SampleData.primaryRows) { row in
                    SidebarRowView(row: row, isSelected: appState.selectedSidebarItem == row.item) {
                        appState.selectedSidebarItem = row.item
                    }
                }
            }
            .padding(.horizontal, 10)

            Divider()
                .overlay(DesignTokens.hairline)
                .padding(.horizontal, 18)
                .padding(.vertical, 14)

            VStack(spacing: 3) {
                ForEach(SampleData.secondaryRows) { row in
                    SidebarRowView(row: row, isSelected: appState.selectedSidebarItem == row.item) {
                        appState.selectedSidebarItem = row.item
                    }
                }
            }
            .padding(.horizontal, 10)

            Spacer(minLength: 0)

            storageCard
                .padding(16)
        }
        .background(.regularMaterial)
    }

    private var wordmark: some View {
        HStack(spacing: 9) {
            Image(systemName: "location.north.circle.fill")
                .font(.system(size: 16))
                .foregroundStyle(DesignTokens.accent)
            Text("Daymark")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(DesignTokens.textPrimary)
        }
    }

    private var storageCard: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(DesignTokens.success)
                        .frame(width: 6, height: 6)
                    Text("Stored locally")
                        .font(DesignType.metadata)
                        .foregroundStyle(DesignTokens.textSecondary)
                }
                Text(appState.workspaceRoot.rawPath)
                    .font(.system(size: 12, weight: .regular, design: .monospaced))
                    .foregroundStyle(DesignTokens.textTertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 0)
            Image(systemName: "slider.horizontal.3")
                .font(.system(size: 12))
                .foregroundStyle(DesignTokens.textTertiary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.4))
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.cardRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: DesignTokens.cardRadius, style: .continuous)
                .stroke(DesignTokens.hairline.opacity(0.7), lineWidth: 1)
        }
    }
}

private struct SidebarRowView: View {
    let row: SampleData.SidebarRow
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: row.symbol)
                    .font(.system(size: 13))
                    .frame(width: 18)
                    .foregroundStyle(isSelected ? DesignTokens.textPrimary : DesignTokens.textSecondary)
                Text(row.title)
                    .font(DesignType.sidebar)
                    .foregroundStyle(isSelected ? DesignTokens.textPrimary : DesignTokens.textSecondary)
                Spacer(minLength: 0)
                if let count = row.count {
                    Text("\(count)")
                        .font(.system(size: 12))
                        .foregroundStyle(DesignTokens.textTertiary)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(rowBackground)
            .clipShape(RoundedRectangle(cornerRadius: DesignTokens.cardRadius, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(DesignMotion.hover) { isHovering = hovering }
        }
    }

    private var rowBackground: Color {
        if isSelected {
            // accentSoft alone washes out over the translucent sidebar material; a light
            // sage tint reads clearly as "selected" while staying quiet.
            return DesignTokens.accent.opacity(0.18)
        }
        return isHovering ? Color.black.opacity(0.045) : .clear
    }
}
