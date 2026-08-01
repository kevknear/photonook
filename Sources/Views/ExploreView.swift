import SwiftUI
import Photos
import UIKit

/// Pantalla de inicio: catálogo de secciones de la galería.
/// Eliges una y entras al mazo ya filtrado.
struct ExploreView: View {
    @Environment(SwipeViewModel.self) private var model

    @State private var pendingChoice: PhotoSource?
    @State private var showBatchWarning = false

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
    ]

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.backgroundGradient.ignoresSafeArea()

                if model.isLoadingSections && model.sectionGroups.isEmpty {
                    loadingState
                } else if model.sectionGroups.isEmpty {
                    emptyState
                } else {
                    catalog
                }
            }
            .navigationTitle("Explore")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await model.loadSections() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .tint(Theme.discard)
                    .disabled(model.isLoadingSections)
                }
            }
            .confirmationDialog(
                "You have \(model.pendingCount) photos still in the tray",
                isPresented: $showBatchWarning,
                titleVisibility: .visible
            ) {
                Button("Go to the tray and delete them first") {
                    pendingChoice = nil
                    model.selectedTab = .tray
                }
                Button("Switch section anyway", role: .destructive) {
                    if let source = pendingChoice {
                        pendingChoice = nil
                        Task { await model.choose(source: source) }
                    }
                }
                Button("Cancel", role: .cancel) { pendingChoice = nil }
            } message: {
                Text("Switching sections empties the tray. Those photos stay in your gallery — nothing gets deleted.")
            }
        }
    }

    // MARK: - Catálogo

    private var catalog: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 26, pinnedViews: []) {
                ForEach(model.sectionGroups) { group in
                    VStack(alignment: .leading, spacing: 12) {
                        header(for: group)

                        LazyVGrid(columns: columns, spacing: 12) {
                            ForEach(group.sections) { section in
                                Button {
                                    select(section.source)
                                } label: {
                                    SectionCard(
                                        section: section,
                                        isCurrent: section.source == model.filter.source
                                    )
                                }
                                .buttonStyle(BouncyButtonStyle())
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, Metrics.gutter)
            .padding(.top, 4)
            .padding(.bottom, 24)
        }
    }

    private func header(for group: LibrarySectionGroup) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(group.title)
                .font(.cozy(19, .bold))
                .foregroundStyle(Theme.textPrimary)
            if let subtitle = group.subtitle {
                Text(subtitle)
                    .font(.cozy(12))
                    .foregroundStyle(Theme.textSecondary)
            }
        }
    }

    // MARK: - Estados

    private var loadingState: some View {
        VStack(spacing: 16) {
            ProgressView()
                .controlSize(.large)
                .tint(Theme.discard)
            Text("Sorting your gallery…")
                .font(.cozy(15, .medium))
                .foregroundStyle(Theme.textSecondary)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 18) {
            CozyEmblem(systemImage: "photo.on.rectangle.angled", tint: Theme.textSecondary)
            Text("Empty gallery")
                .font(.cozy(21, .bold))
                .foregroundStyle(Theme.textPrimary)
            Text("No photos or videos found on this device.")
                .font(.cozy(14))
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(36)
    }

    // MARK: - Selección

    private func select(_ source: PhotoSource) {
        Haptics.impact(.light)
        // Cambiar de sección recarga el mazo, y eso vacía el lote pendiente.
        if model.pendingCount > 0 && source != model.filter.source {
            pendingChoice = source
            showBatchWarning = true
            return
        }
        Task { await model.choose(source: source) }
    }
}

// MARK: - Tarjeta de sección

struct SectionCard: View {
    let section: LibrarySection
    let isCurrent: Bool

    var body: some View {
        VStack(spacing: 0) {
            cover
            info
        }
        .paperSurface(radius: Metrics.panelRadius, elevation: 5)
        .overlay(
            RoundedRectangle(cornerRadius: Metrics.panelRadius, style: .continuous)
                .stroke(Theme.discard, lineWidth: isCurrent ? 2 : 0)
        )
    }

    private var cover: some View {
        Theme.photoWell
            .aspectRatio(1.25, contentMode: .fit)
            .overlay {
                if let id = section.coverAssetID {
                    AssetCoverImage(identifier: id)
                } else {
                    Image(systemName: section.icon)
                        .font(.fixed(30))
                        .foregroundStyle(Theme.textSecondary.opacity(0.5))
                }
            }
            .overlay(alignment: .topLeading) {
                Image(systemName: section.icon)
                    .font(.fixed(11, .semibold))
                    .foregroundStyle(Theme.textOnAccent)
                    .frame(width: 26, height: 26)
                    .background(Theme.textPrimary.opacity(0.62), in: Circle())
                    .padding(8)
            }
            .overlay(alignment: .topTrailing) {
                if isCurrent {
                    Text("Active")
                        .font(.fixed(9, .bold))
                        .foregroundStyle(Theme.textOnAccent)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Theme.discard, in: Capsule())
                        .padding(8)
                }
            }
            .clipShape(
                .rect(
                    topLeadingRadius: Metrics.panelRadius,
                    bottomLeadingRadius: 0,
                    bottomTrailingRadius: 0,
                    topTrailingRadius: Metrics.panelRadius,
                    style: .continuous
                )
            )
    }

    private var info: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(section.title)
                .font(.cozy(14, .semibold))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(2)
                .minimumScaleFactor(0.8)

            Text(section.count == 1
                 ? String(localized: "1 item")
                 : String(localized: "\(section.count) items"))
                .font(.cozy(11, .medium))
                .foregroundStyle(Theme.textSecondary)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }
}

// MARK: - Portada

/// Miniatura de portada cargada por identificador, con caché en memoria compartida
/// para que volver al explorador sea instantáneo.
struct AssetCoverImage: View {
    let identifier: String

    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .transition(.opacity)
            } else {
                ProgressView()
                    .controlSize(.small)
                    .tint(Theme.textSecondary)
            }
        }
        .task(id: identifier) {
            if let cached = CoverCache.shared.image(for: identifier) {
                image = cached
                return
            }
            let loaded = await PhotoLibraryService.shared.image(
                withIdentifier: identifier,
                targetSize: CGSize(width: 400, height: 400)
            )
            guard !Task.isCancelled else { return }
            if let loaded {
                CoverCache.shared.store(loaded, for: identifier)
            }
            withAnimation(.easeOut(duration: 0.2)) { image = loaded }
        }
    }
}

/// Caché sencilla de portadas. `NSCache` ya es seguro entre hilos.
final class CoverCache: @unchecked Sendable {
    static let shared = CoverCache()

    private let cache = NSCache<NSString, UIImage>()

    private init() {
        cache.countLimit = 120
    }

    func image(for identifier: String) -> UIImage? {
        cache.object(forKey: identifier as NSString)
    }

    func store(_ image: UIImage, for identifier: String) {
        cache.setObject(image, forKey: identifier as NSString)
    }
}
