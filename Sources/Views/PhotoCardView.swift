import SwiftUI
import Photos
import UIKit

/// Una "carta" del mazo: tarjeta de papel con la foto enmarcada y su ficha debajo.
/// La foto se muestra completa (`scaledToFit`) porque para decidir si la borras
/// necesitas verla entera, no un recorte.
struct PhotoCardView: View {
    @Environment(SwipeViewModel.self) private var model

    let asset: PHAsset

    @State private var image: UIImage?
    /// Descargando el original desde iCloud, con su avance de 0 a 1.
    @State private var cloudProgress: Double?
    @State private var cloudFailed = false
    /// El original está en iCloud y la política actual no permite bajarlo solo.
    @State private var awaitingManualDownload = false
    @State private var lastTargetSize: CGSize = .zero

    @AppStorage(CloudDownloadPolicy.storageKey)
    private var cloudPolicyRaw = CloudDownloadPolicy.wifiOnly.rawValue

    private var cloudPolicy: CloudDownloadPolicy {
        CloudDownloadPolicy(rawValue: cloudPolicyRaw) ?? .wifiOnly
    }

    var body: some View {
        VStack(spacing: 12) {
            photoWell
            caption
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .paperSurface(radius: Metrics.cardRadius, elevation: 14)
    }

    // MARK: - Foto

    private var photoWell: some View {
        GeometryReader { geometry in
            Theme.photoWell
                .overlay {
                    if let image {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .transition(.opacity)
                    } else {
                        ProgressView()
                            .tint(Theme.textSecondary)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: Metrics.wellRadius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Metrics.wellRadius, style: .continuous)
                        .stroke(Theme.hairline.opacity(0.5), lineWidth: 1)
                )
                .overlay(alignment: .topTrailing) { tags }
                .overlay(alignment: .bottom) { cloudStatus }
                .task(id: asset.localIdentifier) {
                    await load(targetSize: geometry.size)
                }
        }
    }

    private var tags: some View {
        VStack(alignment: .trailing, spacing: 6) {
            if asset.mediaType == .video {
                tag(icon: "video.fill", text: durationText)
            }
            if asset.mediaSubtypes.contains(.photoScreenshot) {
                tag(icon: "iphone.gen3", text: String(localized: "Screenshot"))
            }
            if asset.isFavorite {
                tag(icon: "heart.fill", text: String(localized: "Favorite"))
            }
        }
        .padding(10)
    }

    /// Estado de la foto respecto a iCloud: descargando, esperando permiso, o fallida.
    @ViewBuilder
    private var cloudStatus: some View {
        if let progress = cloudProgress {
            capsule(background: Theme.textPrimary.opacity(0.78)) {
                ProgressView(value: max(0.02, progress))
                    .progressViewStyle(.circular)
                    .controlSize(.mini)
                    .tint(Theme.textOnAccent)
                Text("Downloading from iCloud…")
            }
            .transition(.opacity)

        } else if awaitingManualDownload {
            // La política del usuario impide bajarla sola, pero puede pedir esta.
            Button {
                Task { await fetchFull(size: lastTargetSize, allowsNetwork: true) }
            } label: {
                capsule(background: Theme.info.opacity(0.92)) {
                    Image(systemName: "icloud.and.arrow.down")
                    Text("Load full quality")
                }
            }
            .buttonStyle(BouncyButtonStyle())

        } else if cloudFailed {
            capsule(background: Theme.discard.opacity(0.9)) {
                Image(systemName: "icloud.slash")
                Text("Couldn't load this one")
            }
        }
    }

    private func capsule<Content: View>(
        background: Color,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(spacing: 7) { content() }
            .font(.fixed(11, .medium))
            .foregroundStyle(Theme.textOnAccent)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(background, in: Capsule())
            .padding(.bottom, 14)
    }

    private func tag(icon: String, text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
            Text(text)
        }
        // Fijo: insignia flotante sobre la foto, no debe invadir la imagen.
        .font(.fixed(10, .semibold))
        .foregroundStyle(Theme.textOnAccent)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Theme.textPrimary.opacity(0.72), in: Capsule())
    }

    // MARK: - Ficha inferior

    private var caption: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 3) {
                Text(dateText)
                    .font(.cozy(15, .semibold))
                    .foregroundStyle(Theme.textPrimary)

                Text("\(asset.pixelWidth) × \(asset.pixelHeight)")
                    .font(.cozy(11))
                    .foregroundStyle(Theme.textSecondary)
            }

            Spacer()

            if let bytes = model.size(of: asset), bytes > 0 {
                Text(SwipeViewModel.format(bytes: bytes))
                    .font(.cozy(13, .semibold))
                    .monospacedDigit()
                    .foregroundStyle(Theme.info)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Theme.surfaceMuted, in: Capsule())
            }
        }
        .padding(.horizontal, 4)
        .padding(.bottom, 2)
    }

    private var dateText: String {
        guard let date = asset.creationDate else { return String(localized: "No date") }
        return date.formatted(date: .abbreviated, time: .shortened)
    }

    private var durationText: String {
        let total = Int(asset.duration.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    // MARK: - Carga

    /// Carga en dos fases.
    ///
    /// Primero la miniatura que ya está en el dispositivo, que aparece al instante
    /// aunque sea de baja resolución. Solo después se pide el original, que con
    /// "Optimizar almacenamiento" puede venir de iCloud y tardar. Así nunca se ve
    /// una carta en blanco esperando a la red.
    private func load(targetSize: CGSize) async {
        let service = PhotoLibraryService.shared
        let scale = min(UITraitCollection.current.displayScale, 3)
        let size = CGSize(
            width: max(targetSize.width, 300) * scale,
            height: max(targetSize.height, 300) * scale
        )
        lastTargetSize = size

        // Fase 1: lo que haya en local, ya.
        let local = await service.localThumbnail(for: asset, targetSize: size)
        guard !Task.isCancelled else { return }
        if let thumb = local.image {
            withAnimation(.easeOut(duration: 0.15)) { image = thumb }
        }

        // Si el original está en iCloud, decide la política del usuario, no la app.
        if local.isInCloud {
            let allowed = cloudPolicy.allowsAutomaticDownload(
                isExpensive: NetworkStatus.shared.isExpensive
            )
            guard allowed else {
                awaitingManualDownload = true
                if local.image == nil { cloudFailed = true }
                return
            }
        }

        await fetchFull(size: size, allowsNetwork: true)
    }

    /// Trae el original. Se usa tanto en la carga automática como al pulsar
    /// "Ver en alta calidad".
    private func fetchFull(size: CGSize, allowsNetwork: Bool) async {
        awaitingManualDownload = false
        cloudFailed = false
        cloudProgress = 0

        let full = await PhotoLibraryService.shared.fullImage(
            for: asset,
            targetSize: size,
            allowsNetwork: allowsNetwork
        ) { progress in
            Task { @MainActor in
                // Solo interesa mientras siga siendo la misma carta.
                if cloudProgress != nil { cloudProgress = progress }
            }
        }

        guard !Task.isCancelled else { return }
        cloudProgress = nil

        if let full {
            withAnimation(.easeOut(duration: 0.2)) { image = full }
        } else if image == nil {
            // Ni local ni descarga: no hay nada que enseñar.
            cloudFailed = true
        } else {
            // Hay miniatura pero la descarga falló: deja reintentar.
            awaitingManualDownload = true
        }
    }
}
