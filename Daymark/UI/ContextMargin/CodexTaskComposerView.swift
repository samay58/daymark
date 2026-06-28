import SwiftUI

// A preview-before-write Codex task composer. Mocked for Milestone 0: nothing is generated or saved.
struct CodexTaskComposerView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Create Codex Task")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(DesignTokens.textPrimary)

            Rectangle().fill(DesignTokens.hairline).frame(height: 1)

            field("Title", value: "Make task rollover deterministic")
            field("Goal", value: "Prevent duplicate rolled-over tasks when prior notes are edited.", lines: 2)
            field("Source", value: "daily/2026/06/2026-06-22.md", mono: true)

            VStack(alignment: .leading, spacing: 8) {
                FieldLabel(text: "Acceptance Criteria")
                VStack(alignment: .leading, spacing: 7) {
                    criterion("Rollover uses stable source identifiers")
                    criterion("Duplicate rollovers are prevented")
                    criterion("Tests cover source hash changes")
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(DesignTokens.surface.opacity(0.6))
                .clipShape(RoundedRectangle(cornerRadius: DesignTokens.cardRadius, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: DesignTokens.cardRadius, style: .continuous)
                        .stroke(DesignTokens.hairline, lineWidth: 1)
                }
            }

            field("File", value: "specs/tasks/2026-06-22-deterministic-rollover.md", mono: true)

            Rectangle().fill(DesignTokens.hairline).frame(height: 1)

            VStack(spacing: 8) {
                Button("Create Task File") {}
                    .buttonStyle(PrimaryButtonStyle())
                    .frame(maxWidth: .infinity)
                HStack(spacing: 8) {
                    Button("Edit") {}
                        .buttonStyle(SecondaryButtonStyle())
                        .frame(maxWidth: .infinity)
                    Button("Cancel") {}
                        .buttonStyle(QuietButtonStyle())
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.7))
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.panelRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: DesignTokens.panelRadius, style: .continuous)
                .stroke(DesignTokens.hairline, lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.05), radius: 10, y: 4)
    }

    private func field(_ label: String, value: String, lines: Int = 1, mono: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            FieldLabel(text: label)
            Text(value)
                .font(mono ? .system(size: 12, design: .monospaced) : .system(size: 13))
                .foregroundStyle(DesignTokens.textPrimary)
                .frame(maxWidth: .infinity, minHeight: CGFloat(lines) * 17, alignment: .topLeading)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(Color.white.opacity(0.55))
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .stroke(DesignTokens.hairline, lineWidth: 1)
                }
        }
    }

    private func criterion(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 9) {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .stroke(DesignTokens.hairline, lineWidth: 1.5)
                .frame(width: 14, height: 14)
                .padding(.top, 1)
            Text(text)
                .font(.system(size: 13))
                .foregroundStyle(DesignTokens.textSecondary)
            Spacer(minLength: 0)
        }
    }
}
