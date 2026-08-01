import SwiftUI

/// Panel de progreso: cuántas van, cuántas quedan y espacio recuperado.
struct StatsBar: View {
    @Environment(SwipeViewModel.self) private var model

    var body: some View {
        VStack(spacing: 11) {
            HStack(alignment: .firstTextBaseline) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(min(model.currentIndex + 1, model.totalCount))")
                        .font(.cozy(24, .bold))
                        .foregroundStyle(Theme.textPrimary)
                        .contentTransition(.numericText())
                    Text("of \(model.totalCount)")
                        .font(.cozy(13, .medium))
                        .foregroundStyle(Theme.textSecondary)
                }
                .lineLimit(1)
                .minimumScaleFactor(0.7)

                Spacer(minLength: 8)

                HStack(spacing: 5) {
                    Image(systemName: "internaldrive")
                        .font(.cozy(12, .semibold))
                    Text(model.formattedBytesFreed)
                        .font(.cozy(14, .bold))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                }
                .foregroundStyle(Theme.info)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Theme.surfaceMuted, in: Capsule())
            }

            progressTrack

            HStack(spacing: 12) {
                counter(icon: "heart.fill", tint: Theme.keep, value: model.keptCount)
                counter(icon: "trash.fill", tint: Theme.discard, value: model.deletedCount)

                Spacer()

                if model.deletionMode.defersDeletion && model.pendingCount > 0 {
                    Button {
                        model.selectedTab = .tray
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "tray.full.fill")
                            Text("Review \(model.pendingCount)")
                            Image(systemName: "chevron.right")
                                .font(.fixed(9, .bold))
                        }
                        .font(.cozy(12, .semibold))
                        .foregroundStyle(Theme.pending)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Theme.pending.opacity(0.14), in: Capsule())
                    }
                    .buttonStyle(BouncyButtonStyle())
                }
            }
        }
        .padding(16)
        .paperSurface(radius: Metrics.panelRadius, elevation: 6)
    }

    /// Barra de progreso propia: más suave y cálida que la del sistema.
    private var progressTrack: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Theme.surfaceMuted)

                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [Theme.keep, Theme.pending],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: max(0, geometry.size.width * model.progress))
                    .animation(.spring(response: 0.4, dampingFraction: 0.8), value: model.progress)
            }
        }
        .frame(height: 7)
    }

    private func counter(icon: String, tint: Color, value: Int) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.cozy(11))
                .foregroundStyle(tint)
            Text("\(value)")
                .font(.cozy(13, .semibold))
                .monospacedDigit()
                .foregroundStyle(Theme.textPrimary)
                .contentTransition(.numericText())
        }
    }
}
