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

    private func load(targetSize: CGSize) async {
        let scale = min(UITraitCollection.current.displayScale, 3)
        let size = CGSize(
            width: max(targetSize.width, 300) * scale,
            height: max(targetSize.height, 300) * scale
        )
        let loaded = await PhotoLibraryService.shared.image(for: asset, targetSize: size)
        guard !Task.isCancelled else { return }
        withAnimation(.easeOut(duration: 0.2)) {
            image = loaded
        }
    }
}
