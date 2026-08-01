import SwiftUI
import Photos
import UIKit

struct SwipeDeckView: View {
    @Environment(SwipeViewModel.self) private var model

    @State private var offset: CGSize = .zero
    @State private var isAnimatingOut = false

    private let threshold: CGFloat = 110

    var body: some View {
        VStack(spacing: 0) {
            StatsBar()
                .padding(.horizontal, Metrics.gutter)
                .padding(.bottom, 14)

            ZStack {
                // Dos cartas de fondo para dar profundidad al mazo.
                if model.nextAsset != nil {
                    RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous)
                        .fill(Theme.surface)
                        .overlay(
                            RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous)
                                .stroke(Theme.hairline.opacity(0.5), lineWidth: 1)
                        )
                        .scaleEffect(0.90)
                        .offset(y: 14)
                        .opacity(0.55)
                }

                if let next = model.nextAsset {
                    PhotoCardView(asset: next)
                        .scaleEffect(0.95)
                        .offset(y: 7)
                        .opacity(0.85)
                        .allowsHitTesting(false)
                }

                if let current = model.currentAsset {
                    PhotoCardView(asset: current)
                        .overlay { decisionOverlay }
                        .offset(x: offset.width, y: offset.height * 0.3)
                        .rotationEffect(.degrees(Double(offset.width) / 24))
                        .gesture(dragGesture)
                        .id(current.localIdentifier)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, Metrics.gutter)
            .padding(.bottom, 6)

            ActionBar(
                onUndo: { performUndo() },
                onDiscard: { animateOut(toLeft: true) },
                onKeep: { animateOut(toLeft: false) }
            )
            .padding(.top, 14)
            .padding(.bottom, 4)
        }
        .padding(.top, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .cozyBackground()
        .overlay(alignment: .bottom) { toast }
    }

    // MARK: - Gesto

    private var dragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                guard !isAnimatingOut else { return }
                offset = value.translation
            }
            .onEnded { value in
                guard !isAnimatingOut else { return }
                if value.translation.width < -threshold {
                    animateOut(toLeft: true)
                } else if value.translation.width > threshold {
                    animateOut(toLeft: false)
                } else {
                    withAnimation(.spring(response: 0.34, dampingFraction: 0.68)) {
                        offset = .zero
                    }
                }
            }
    }

    private func animateOut(toLeft: Bool) {
        guard model.currentAsset != nil, !isAnimatingOut else { return }
        isAnimatingOut = true

        Haptics.impact(toLeft ? .rigid : .soft)

        withAnimation(.easeOut(duration: 0.24)) {
            offset = CGSize(width: toLeft ? -700 : 700, height: offset.height - 40)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.24) {
            if toLeft { model.discard() } else { model.keep() }
            offset = .zero
            isAnimatingOut = false
        }
    }

    private func performUndo() {
        guard model.canUndo else {
            model.infoMessage = model.undoDisabledReason
            Haptics.notify(.warning)
            return
        }
        Haptics.impact(.light)
        withAnimation(.spring(response: 0.36, dampingFraction: 0.78)) {
            model.undo()
        }
    }

    // MARK: - Indicadores de decisión

    private var decisionOverlay: some View {
        let progress = min(abs(offset.width) / threshold, 1)
        let discarding = offset.width < 0
        let tint = discarding ? Theme.discard : Theme.keep

        return RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous)
            .fill(tint.opacity(Double(progress) * 0.16))
            .overlay(
                RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous)
                    .stroke(tint.opacity(Double(progress)), lineWidth: 3)
            )
            .overlay(alignment: discarding ? .topLeading : .topTrailing) {
                stamp(
                    text: discarding
                        ? String(localized: "DELETE")
                        : String(localized: "KEEP"),
                    icon: discarding ? "trash.fill" : "heart.fill",
                    tint: tint
                )
                .rotationEffect(.degrees(discarding ? -10 : 10))
                .padding(26)
                .opacity(Double(progress))
                .scaleEffect(0.85 + Double(progress) * 0.15)
            }
            .allowsHitTesting(false)
    }

    private func stamp(text: String, icon: String, tint: Color) -> some View {
        HStack(spacing: 7) {
            Image(systemName: icon)
                .font(.cozy(17, .bold))
            Text(text)
                .font(.cozy(19, .heavy))
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(Theme.surface.opacity(0.92), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(tint, lineWidth: 3)
        )
    }

    // MARK: - Toast

    @ViewBuilder
    private var toast: some View {
        if let message = model.infoMessage {
            Text(message)
                .font(.cozy(13, .medium))
                .foregroundStyle(Theme.textPrimary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)
                .padding(.vertical, 11)
                .paperSurface(radius: 22, elevation: 10)
                .padding(.horizontal, 28)
                .padding(.bottom, 12)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .task(id: message) {
                    try? await Task.sleep(nanoseconds: 2_600_000_000)
                    withAnimation(.easeOut(duration: 0.25)) { model.infoMessage = nil }
                }
        }
    }
}

// MARK: - Barra de acciones

struct ActionBar: View {
    @Environment(SwipeViewModel.self) private var model

    let onUndo: () -> Void
    let onDiscard: () -> Void
    let onKeep: () -> Void

    var body: some View {
        HStack(spacing: 26) {
            circleButton(
                icon: "trash.fill",
                label: String(localized: "Discard this photo"),
                tint: Theme.discard,
                size: 66,
                action: onDiscard
            )

            circleButton(
                icon: "arrow.uturn.backward",
                label: String(localized: "Undo last swipe"),
                tint: model.canUndo ? Theme.pending : Theme.textSecondary.opacity(0.5),
                size: 50,
                action: onUndo
            )

            circleButton(
                icon: "heart.fill",
                label: String(localized: "Keep this photo"),
                tint: Theme.keep,
                size: 66,
                action: onKeep
            )
        }
    }

    private func circleButton(
        icon: String,
        label: String,
        tint: Color,
        size: CGFloat,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                // Fijo: el círculo tiene tamaño fijo, un glifo que crezca lo desborda.
                .font(.fixed(size * 0.36, .semibold))
                .foregroundStyle(tint)
                .frame(width: size, height: size)
                .background(
                    Circle()
                        .fill(Theme.surface)
                        .shadow(color: Theme.shadow.opacity(0.18), radius: 7, y: 3)
                )
                .overlay(
                    Circle().stroke(tint.opacity(0.35), lineWidth: 1.5)
                )
        }
        .buttonStyle(BouncyButtonStyle())
        .accessibilityLabel(label)
    }
}

/// Un pequeño hundido al pulsar: hace que los botones se sientan físicos.
struct BouncyButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .animation(.spring(response: 0.28, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

// MARK: - Háptica

enum Haptics {
    static func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
        let generator = UIImpactFeedbackGenerator(style: style)
        generator.prepare()
        generator.impactOccurred()
    }

    static func notify(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        UINotificationFeedbackGenerator().notificationOccurred(type)
    }
}
