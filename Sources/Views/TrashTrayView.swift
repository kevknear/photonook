import SwiftUI
import Photos
import UIKit

/// Zona de "staging": todo lo que descartaste con swipe izquierda espera aquí.
/// Puedes sacar del lote lo que quieras salvar y borrar el resto de una sola vez,
/// con una única alerta de confirmación de iOS.
struct TrashTrayView: View {
    @Environment(SwipeViewModel.self) private var model

    /// Guardamos las DES-marcadas, no las marcadas: así lo que llegue nuevo al lote
    /// mientras swipeas en la otra pestaña entra ya seleccionado.
    @State private var deselected: Set<String> = []

    private let columns = [GridItem(.adaptive(minimum: 104), spacing: 6)]

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.backgroundGradient.ignoresSafeArea()

                if model.pendingDeletion.isEmpty {
                    emptyState
                } else {
                    grid
                        .safeAreaInset(edge: .bottom) { bottomBar }
                }
            }
            .navigationTitle("To delete")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if !model.pendingDeletion.isEmpty {
                        // Explícito con String(localized:) porque en un ternario Swift
                        // podría escoger la sobrecarga que NO localiza.
                        Button(allSelected
                               ? String(localized: "None")
                               : String(localized: "All")) {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                if allSelected {
                                    deselected = pendingIDs
                                } else {
                                    deselected.removeAll()
                                }
                            }
                        }
                        .font(.cozy(15, .semibold))
                        .tint(Theme.discard)
                    }
                }
            }
            .onChange(of: model.pendingCount) { _, _ in
                // Limpia referencias a fotos que ya no están en el lote.
                deselected.formIntersection(pendingIDs)
            }
        }
    }

    // MARK: - Rejilla

    private var grid: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(model.pendingDeletion, id: \.localIdentifier) { asset in
                    let id = asset.localIdentifier
                    ThumbnailCell(
                        asset: asset,
                        isSelected: !deselected.contains(id),
                        sizeLabel: sizeLabel(for: asset)
                    )
                    .onTapGesture {
                        Haptics.impact(.light)
                        withAnimation(.spring(response: 0.26, dampingFraction: 0.7)) {
                            if deselected.contains(id) {
                                deselected.remove(id)
                            } else {
                                deselected.insert(id)
                            }
                        }
                    }
                    .contextMenu {
                        Button {
                            Haptics.impact(.light)
                            deselected.remove(id)
                            model.requeue(identifiers: [id])
                        } label: {
                            Label("Send back to the deck", systemImage: "arrow.uturn.backward")
                        }

                        Button {
                            Haptics.impact(.light)
                            deselected.remove(id)
                            model.rescue(identifiers: [id])
                        } label: {
                            Label("Keep and remove from tray", systemImage: "heart.fill")
                        }

                        if deselected.contains(id) {
                            Button {
                                deselected.remove(id)
                            } label: {
                                Label("Mark for deletion", systemImage: "trash")
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.top, 8)
        }
    }

    // MARK: - Barra inferior

    private var bottomBar: some View {
        VStack(spacing: 11) {
            HStack {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(selectedIDs.count)")
                        .font(.cozy(20, .bold))
                        .foregroundStyle(Theme.discard)
                        .contentTransition(.numericText())
                    Text("of \(model.pendingCount) marked")
                        .font(.cozy(13, .medium))
                        .foregroundStyle(Theme.textSecondary)
                }
                .lineLimit(1)
                .minimumScaleFactor(0.7)

                Spacer(minLength: 8)

                Text(SwipeViewModel.format(bytes: selectedBytes))
                    .font(.cozy(14, .bold))
                    .monospacedDigit()
                    .foregroundStyle(Theme.info)
                    .contentTransition(.numericText())
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Theme.surfaceMuted, in: Capsule())
            }

            if !deselected.isEmpty {
                HStack(spacing: 10) {
                    HStack(spacing: 5) {
                        Image(systemName: "heart.fill")
                            .font(.cozy(10))
                        Text("\(deselected.count) unmarked")
                            .font(.cozy(12, .medium))
                    }
                    .foregroundStyle(Theme.keep)

                    Spacer()

                    Button {
                        Haptics.impact(.light)
                        let ids = deselected
                        deselected.removeAll()
                        model.requeue(identifiers: ids)
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "arrow.uturn.backward")
                            Text("Back to deck")
                        }
                        .font(.cozy(12, .semibold))
                        .foregroundStyle(Theme.pending)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 7)
                        .background(Theme.pending.opacity(0.14), in: Capsule())
                    }
                    .buttonStyle(BouncyButtonStyle())
                }
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }

            Button {
                Task { await confirm() }
            } label: {
                HStack(spacing: 8) {
                    if model.isCommitting {
                        ProgressView()
                            .tint(Theme.textOnAccent)
                    } else {
                        Image(systemName: "trash.fill")
                        Text(buttonTitle)
                    }
                }
                .font(.cozy(16, .semibold))
                .foregroundStyle(Theme.textOnAccent)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .background(
                    selectedIDs.isEmpty ? Theme.textSecondary.opacity(0.4) : Theme.discard,
                    in: RoundedRectangle(cornerRadius: Metrics.controlRadius, style: .continuous)
                )
                .shadow(
                    color: selectedIDs.isEmpty ? .clear : Theme.discard.opacity(0.3),
                    radius: 8, y: 4
                )
            }
            .buttonStyle(BouncyButtonStyle())
            .disabled(model.isCommitting || selectedIDs.isEmpty)

            Text("One iOS confirmation for the whole batch. Unmarked photos count as kept; press and hold a photo to send it back to the deck.")
                .font(.cozy(11))
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, Metrics.gutter)
        .padding(.top, 14)
        .padding(.bottom, 10)
        .background(
            Theme.surface
                .overlay(alignment: .top) {
                    Rectangle()
                        .fill(Theme.hairline)
                        .frame(height: 1)
                }
                .ignoresSafeArea(edges: .bottom)
        )
    }

    private var emptyState: some View {
        VStack(spacing: 18) {
            CozyEmblem(systemImage: "tray", tint: Theme.textSecondary)

            Text("The tray is empty")
                .font(.handwritten(36, relativeTo: .title2))
                .foregroundStyle(Theme.textPrimary)

            Text("Photos you discard with a left swipe wait here before being deleted.")
                .font(.cozy(14))
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)

            Button {
                model.selectedTab = .review
            } label: {
                CozyButtonLabel(
                    title: String(localized: "Start reviewing photos"),
                    icon: "rectangle.stack.fill"
                )
            }
            .buttonStyle(BouncyButtonStyle())
            .padding(.top, 6)
        }
        .padding(36)
    }

    // MARK: - Derivados

    private var pendingIDs: Set<String> {
        Set(model.pendingDeletion.map(\.localIdentifier))
    }

    private var selectedIDs: Set<String> {
        pendingIDs.subtracting(deselected)
    }

    private var allSelected: Bool {
        !model.pendingDeletion.isEmpty && deselected.isEmpty
    }

    private var selectedBytes: Int64 {
        model.pendingDeletion
            .filter { !deselected.contains($0.localIdentifier) }
            .reduce(0) { $0 + (model.size(of: $1) ?? 0) }
    }

    private var buttonTitle: String {
        selectedIDs.isEmpty
            ? String(localized: "Nothing selected")
            : String(localized: "Delete \(selectedIDs.count) at once")
    }

    private func sizeLabel(for asset: PHAsset) -> String? {
        guard let bytes = model.size(of: asset), bytes > 0 else { return nil }
        return SwipeViewModel.format(bytes: bytes)
    }

    // MARK: - Acción

    private func confirm() async {
        let toDelete = selectedIDs
        guard !toDelete.isEmpty else { return }

        // Lo que quedó sin marcar se salva y pasa a conservadas.
        model.rescue(identifiers: deselected)
        deselected.removeAll()

        await model.commitPendingDeletions(limitedTo: toDelete)

        // Si el lote quedó vacío, vuelve al mazo.
        if model.pendingDeletion.isEmpty {
            model.selectedTab = .review
        }
    }
}

// MARK: - Celda

private struct ThumbnailCell: View {
    let asset: PHAsset
    let isSelected: Bool
    let sizeLabel: String?

    @State private var image: UIImage?

    var body: some View {
        // El cuadrado se define primero con el color de fondo. Todo lo demás va como
        // `overlay`, que nunca modifica el tamaño del padre: así la celda no puede
        // desbordarse ni solaparse con las vecinas de la rejilla.
        Theme.photoWell
            .aspectRatio(1, contentMode: .fit)
            .overlay {
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
            .overlay {
                // Vela cálido sobre las que se van a salvar.
                if !isSelected {
                    Theme.surface.opacity(0.62)
                }
            }
            .overlay(alignment: .topTrailing) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 19))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(
                        isSelected ? Theme.textOnAccent : Theme.textPrimary.opacity(0.5),
                        isSelected ? Theme.discard : Theme.surface.opacity(0.85)
                    )
                    .shadow(color: Theme.shadow.opacity(0.35), radius: 2)
                    .padding(6)
            }
            .overlay(alignment: .bottomLeading) {
                if let sizeLabel, isSelected {
                    Text(sizeLabel)
                        // Fijo: la celda mide 104pt, aquí no cabe texto escalado.
                        .font(.fixed(9, .semibold))
                        .foregroundStyle(Theme.textOnAccent)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Theme.textPrimary.opacity(0.6), in: Capsule())
                        .padding(6)
                }
            }
            .overlay(alignment: .center) {
                if !isSelected {
                    Image(systemName: "heart.fill")
                        .font(.fixed(20, .bold))
                        .foregroundStyle(Theme.keep)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            // Recorta el desbordamiento de `scaledToFill` al cuadrado de la celda.
            .clipShape(RoundedRectangle(cornerRadius: Metrics.cellRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Metrics.cellRadius, style: .continuous)
                    .stroke(isSelected ? Theme.discard : Theme.hairline,
                            lineWidth: isSelected ? 2 : 1)
            )
            .shadow(color: Theme.shadow.opacity(0.1), radius: 3, y: 2)
            .contentShape(Rectangle())
            .task(id: asset.localIdentifier) {
                // Solo local, sin red: ver la bandeja no debe costar datos.
                let result = await PhotoLibraryService.shared.localThumbnail(
                    for: asset,
                    targetSize: CGSize(width: 320, height: 320)
                )
                guard !Task.isCancelled else { return }
                withAnimation(.easeOut(duration: 0.2)) { image = result.image }
            }
    }
}
