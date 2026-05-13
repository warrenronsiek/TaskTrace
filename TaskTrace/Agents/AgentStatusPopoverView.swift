import SwiftUI

struct AgentStatusPopoverView: View {
    @ObservedObject var activityStore: ActivityStore
    let onToggleRecording: () -> Void
    let onOpenTaskTrace: () -> Void
    let onQuitTaskTrace: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            VStack(spacing: 12) {
                Button {
                    onToggleRecording()
                } label: {
                    Image(systemName: activityStore.isRecording ? "stop.fill" : "play.fill")
                        .font(.system(size: 46, weight: .semibold))
                        .frame(width: 138, height: 138)
                }
                .buttonStyle(.glassProminent)
                .buttonBorderShape(.circle)
                .tint(activityStore.isRecording ? AppColors.recordActive : AppColors.recordIdle)
                .disabled(activityStore.playStopButtonDisabled)

                Text(activityStore.isRecording ? "Recording" : "Stopped")
                    .font(Styles.Fonts.headline)
                    .foregroundStyle(AppColors.textPrimary)
            }
            .frame(maxWidth: .infinity)

            HStack(spacing: 10) {
                Button {
                    onOpenTaskTrace()
                } label: {
                    Image("TrayIcon")
                        .resizable()
                        .scaledToFit()
                        .padding(12)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(Color.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.14), lineWidth: 0.8)
                )

                Button {
                    onQuitTaskTrace()
                } label: {
                    Image(systemName: "power")
                        .font(.system(size: 22, weight: .semibold))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .foregroundStyle(AppColors.textPrimary)
                .background(Color.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.14), lineWidth: 0.8)
                )
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.14), lineWidth: 0.8)
            )
        }
        .padding(18)
        .frame(width: 280, alignment: .top)
        .background(Color.clear)
    }
}
