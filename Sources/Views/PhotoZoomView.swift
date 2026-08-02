import SwiftUI
import Photos
import UIKit

/// Visor a pantalla completa con zoom, para mirar el detalle antes de decidir.
///
/// Sin esto no se puede juzgar una captura de pantalla: hay que poder leer lo que
/// pone para saber si merece la pena conservarla. Por eso carga a mayor resolución
/// que la carta, que solo necesita verse bien a tamaño de pantalla.
struct PhotoZoomView: View {
    @Environment(\.dismiss) private var dismiss

    let asset: PHAsset
    /// Decisiones tomadas desde aquí. La vista se cierra antes de aplicarlas.
    let onKeep: () -> Void
    let onDiscard: () -> Void

    @State private var image: UIImage?
    @State private var isLoading = true
    @State private var cloudProgress: Double?

    // Zoom y desplazamiento
    @State private var scale: CGFloat = 1
    @State private var committedScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var committedOffset: CGSize = .zero

    @AppStorage(CloudDownloadPolicy.storageKey)
    private var cloudPolicyRaw = CloudDownloadPolicy.wifiOnly.rawValue

    private let minScale: CGFloat = 1
    private let maxScale: CGFloat = 8

    var body: some View {
        ZStack {
            // Fondo neutro y oscuro: cualquier tinte falsearía los colores de la
            // foto justo cuando el usuario la está juzgando.
            Color.black.ignoresSafeArea()

            content
        }
        .overlay(alignment: .top) { topBar }
        .overlay(alignment: .bottom) { actions }
        .statusBarHidden()
        .task { await load() }
    }

    // MARK: - Imagen

    @ViewBuilder
    private var content: some View {
        if let image {
            GeometryReader { geometry in
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .scaleEffect(scale)
                    .offset(offset)
                    .gesture(magnification)
                    .simultaneousGesture(panning)
                    .onTapGesture(count: 2) { toggleZoom() }
                    .animation(.interactiveSpring(response: 0.3), value: scale)
            }
            .ignoresSafeArea()
        } else if isLoading {
            // Dos ramas y no un ternario sobre el estilo: `.circular` y `.linear`
            // son tipos distintos y no unifican en el mismo `some ProgressViewStyle`.
            VStack(spacing: 14) {
                if let progress = cloudProgress {
                    ProgressView(value: progress)
                        .progressViewStyle(.linear)
                        .tint(.white)
                        .frame(maxWidth: 160)
                    Text("Downloading from iCloud…")
                        .font(.cozy(12))
                        .foregroundStyle(.white.opacity(0.7))
                } else {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(.white)
                }
            }
        } else {
            VStack(spacing: 10) {
                Image(systemName: "icloud.slash")
                    .font(.system(size: 34))
                Text("Couldn't load this one")
                    .font(.cozy(14))
            }
            .foregroundStyle(.white.opacity(0.7))
        }
    }

    // MARK: - Gestos

    private var magnification: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                scale = min(max(committedScale * value.magnification, minScale * 0.6), maxScale)
            }
            .onEnded { _ in
                // Por debajo del tamaño original, vuelve a encajar en pantalla.
                if scale < minScale {
                    resetZoom()
                } else {
                    committedScale = scale
                }
            }
    }

    /// Solo desplaza cuando hay algo que desplazar; si no, se comería el gesto
    /// de cerrar y daría sensación de vista trabada.
    private var panning: some Gesture {
        DragGesture()
            .onChanged { value in
                guard scale > minScale else { return }
                offset = CGSize(
                    width: committedOffset.width + value.translation.width,
                    height: committedOffset.height + value.translation.height
                )
            }
            .onEnded { _ in
                guard scale > minScale else { return }
                committedOffset = offset
            }
    }

    private func toggleZoom() {
        withAnimation(.spring(response: 0.32, dampingFraction: 0.8)) {
            if scale > minScale {
                resetZoom()
            } else {
                scale = 3
                committedScale = 3
            }
        }
    }

    private func resetZoom() {
        scale = minScale
        committedScale = minScale
        offset = .zero
        committedOffset = .zero
    }

    // MARK: - Barras

    private var topBar: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 38, height: 38)
                    .background(.black.opacity(0.45), in: Circle())
            }
            .accessibilityLabel(String(localized: "Close"))

            Spacer()

            if scale > minScale {
                Button { withAnimation { resetZoom() } } label: {
                    Text("Fit")
                        .font(.cozy(13, .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .background(.black.opacity(0.45), in: Capsule())
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    private var actions: some View {
        HStack(spacing: 26) {
            circle(icon: "trash.fill", tint: Theme.discard,
                   label: String(localized: "Discard this photo")) {
                dismiss()
                onDiscard()
            }
            circle(icon: "heart.fill", tint: Theme.keep,
                   label: String(localized: "Keep this photo")) {
                dismiss()
                onKeep()
            }
        }
        .padding(.bottom, 28)
        .opacity(image == nil ? 0 : 1)
    }

    private func circle(
        icon: String,
        tint: Color,
        label: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 60, height: 60)
                .background(.white.opacity(0.92), in: Circle())
        }
        .buttonStyle(BouncyButtonStyle())
        .accessibilityLabel(label)
    }

    // MARK: - Carga

    private func load() async {
        let service = PhotoLibraryService.shared
        // Bastante más grande que la carta: es justo lo que permite leer texto
        // pequeño al ampliar. Acotado para no reventar la memoria con fotos de
        // 48 megapíxeles.
        let target = CGSize(width: 3000, height: 3000)

        let local = await service.localThumbnail(for: asset, targetSize: target)
        guard !Task.isCancelled else { return }
        if let thumb = local.image {
            image = thumb
            isLoading = false
        }

        let policy = CloudDownloadPolicy(rawValue: cloudPolicyRaw) ?? .wifiOnly
        // Al ampliar sí compensa tirar de red aunque la política sea "solo Wi-Fi":
        // el usuario ha pedido ver esta foto en concreto, no es una descarga
        // automática a sus espaldas.
        let allowsNetwork = policy != .never

        if local.isInCloud && allowsNetwork {
            cloudProgress = 0
        }

        let full = await service.fullImage(
            for: asset,
            targetSize: target,
            allowsNetwork: allowsNetwork
        ) { progress in
            Task { @MainActor in
                if cloudProgress != nil { cloudProgress = progress }
            }
        }

        guard !Task.isCancelled else { return }
        cloudProgress = nil
        isLoading = false
        if let full { image = full }
    }
}
