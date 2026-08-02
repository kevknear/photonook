import SwiftUI
import Photos
import UIKit

/// La sección activa vista como cuadrícula, para elegir por dónde empezar.
///
/// Es la respuesta al problema de las galerías enormes: con 12.000 fotos, obligar
/// a recorrer el mazo desde la primera hace la app inservible justo para quien
/// más la necesita. Aquí se ve el conjunto y se entra por donde interese.
struct GalleryGridView: View {
    @Environment(SwipeViewModel.self) private var model

    private let columns = [GridItem(.adaptive(minimum: 108), spacing: 3)]

    var body: some View {
        ZStack {
            Theme.backgroundGradient.ignoresSafeArea()

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 3) {
                        ForEach(Array(model.assets.enumerated()), id: \.offset) { index, asset in
                            Button {
                                Haptics.impact(.light)
                                model.startDeck(at: index)
                            } label: {
                                GalleryCell(
                                    asset: asset,
                                    decision: model.decision(for: asset)
                                )
                            }
                            .buttonStyle(.plain)
                            .id(index)
                        }
                    }
                    .padding(.horizontal, 3)
                    .padding(.top, 6)
                }
                .onAppear {
                    // Al volver del mazo, aterriza donde estabas en vez de arriba.
                    guard model.currentIndex > 0,
                          model.currentIndex < model.assets.count else { return }
                    proxy.scrollTo(model.currentIndex, anchor: .center)
                }
            }
        }
        .safeAreaInset(edge: .top) { summaryBar }
        .safeAreaInset(edge: .bottom) { startBar }
    }

    // MARK: - Barra de progreso

    private var summaryBar: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(model.remainingCount) left to review")
                    .font(.cozy(15, .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                Text("\(model.totalCount) in this section")
                    .font(.cozy(11))
                    .foregroundStyle(Theme.textSecondary)
            }

            Spacer(minLength: 8)

            HStack(spacing: 10) {
                tally(icon: "heart.fill", tint: Theme.keep, value: model.keptCount)
                tally(icon: "trash.fill", tint: Theme.discard, value: model.deletedCount)
            }
        }
        .padding(.horizontal, Metrics.gutter)
        .padding(.vertical, 10)
        .background(
            Theme.surface
                .overlay(alignment: .bottom) {
                    Rectangle().fill(Theme.hairline).frame(height: 1)
                }
                .ignoresSafeArea(edges: .top)
        )
    }

    private func tally(icon: String, tint: Color, value: Int) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.fixed(11))
                .foregroundStyle(tint)
            Text("\(value)")
                .font(.cozy(13, .semibold))
                .monospacedDigit()
                .foregroundStyle(Theme.textPrimary)
                .contentTransition(.numericText())
        }
    }

    // MARK: - Barra inferior

    private var startBar: some View {
        VStack(spacing: 8) {
            Button {
                Haptics.impact(.light)
                model.startDeckFromFirstUndecided()
            } label: {
                CozyButtonLabel(
                    title: model.reviewedCount == 0
                        ? String(localized: "Start from the beginning")
                        : String(localized: "Continue where I left off"),
                    icon: "rectangle.stack.fill"
                )
            }
            .buttonStyle(BouncyButtonStyle())

            Text("Or tap any photo to start there.")
                .font(.cozy(11))
                .foregroundStyle(Theme.textSecondary)
        }
        .padding(.horizontal, Metrics.gutter)
        .padding(.top, 12)
        .padding(.bottom, 10)
        .background(
            Theme.surface
                .overlay(alignment: .top) {
                    Rectangle().fill(Theme.hairline).frame(height: 1)
                }
                .ignoresSafeArea(edges: .bottom)
        )
    }
}

// MARK: - Celda

private struct GalleryCell: View {
    let asset: PHAsset
    let decision: SwipeViewModel.Decision?

    @State private var image: UIImage?
    /// El original vive en iCloud y no está descargado en este dispositivo.
    /// Llega gratis: `localThumbnail` ya lo informa al cargar la miniatura.
    @State private var isInCloud = false

    private var isDecided: Bool { decision != nil }

    private var accessibilityDescription: String {
        var parts: [String] = []
        switch decision {
        case .kept:      parts.append(String(localized: "Kept"))
        case .discarded: parts.append(String(localized: "Discarded"))
        case nil:        parts.append(String(localized: "Not reviewed"))
        }
        if isInCloud { parts.append(String(localized: "Stored in iCloud")) }
        return parts.joined(separator: ", ")
    }

    var body: some View {
        Theme.photoWell
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .transition(.opacity)
                }
            }
            // Las ya decididas se apagan: de un vistazo se ve qué queda.
            .overlay {
                if isDecided {
                    Theme.background.opacity(0.62)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if let decision {
                    Image(systemName: decision == .kept ? "heart.fill" : "trash.fill")
                        .font(.fixed(10, .semibold))
                        .foregroundStyle(Theme.textOnAccent)
                        .frame(width: 22, height: 22)
                        .background(
                            Circle().fill(decision == .kept ? Theme.keep : Theme.discard)
                        )
                        .padding(5)
                }
            }
            // Arriba a la izquierda para no chocar con el icono de la decisión.
            .overlay(alignment: .topLeading) {
                if isInCloud {
                    Image(systemName: "icloud")
                        .font(.fixed(10, .semibold))
                        .foregroundStyle(Theme.textOnAccent)
                        .padding(4)
                        .background(Theme.textPrimary.opacity(0.55), in: Circle())
                        .padding(4)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .contentShape(Rectangle())
            .accessibilityLabel(accessibilityDescription)
            .task(id: asset.localIdentifier) {
                if let cached = CoverCache.shared.image(for: asset.localIdentifier) {
                    image = cached
                    return
                }
                // Solo local: con miles de celdas, permitir red aquí descargaría
                // media galería de iCloud al desplazarse.
                let result = await PhotoLibraryService.shared.localThumbnail(
                    for: asset,
                    targetSize: CGSize(width: 300, height: 300)
                )
                guard !Task.isCancelled else { return }
                if let loaded = result.image {
                    CoverCache.shared.store(loaded, for: asset.localIdentifier)
                }
                isInCloud = result.isInCloud
                withAnimation(.easeOut(duration: 0.18)) { image = result.image }
            }
    }
}
