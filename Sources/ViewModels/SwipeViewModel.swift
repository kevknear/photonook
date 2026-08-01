import Foundation
import Photos
import SwiftUI

/// Estado y lógica de la sesión de limpieza.
@MainActor
@Observable
final class SwipeViewModel {

    // MARK: - Tipos

    /// Secciones navegables de la app.
    enum AppTab: Hashable {
        case explore
        case review
        case tray
        case filters
    }

    enum Phase: Equatable {
        case needsPermission
        case loading
        case ready
        case empty
        case finished
    }

    /// Cuándo se ejecuta el borrado real. iOS muestra una alerta del sistema por cada
    /// llamada a `deleteAssets`, así que menos llamadas = menos alertas.
    enum DeletionMode: String, CaseIterable, Identifiable {
        case immediate
        case chunked
        case endOfSession

        var id: String { rawValue }

        var label: String {
            switch self {
            case .immediate:    return String(localized: "Every swipe")
            case .chunked:      return String(localized: "In batches")
            case .endOfSession: return String(localized: "End of session")
            }
        }

        var explanation: String {
            switch self {
            case .immediate:
                return String(localized: "One system alert per photo. That's iOS behavior and it can't be turned off.")
            case .chunked:
                return String(localized: "Collects discarded photos and deletes them every N: one alert per batch.")
            case .endOfSession:
                return String(localized: "Nothing is deleted until you review the tray. A single alert for everything.")
            }
        }

        var defersDeletion: Bool { self != .immediate }
    }

    /// Una decisión tomada, para poder deshacerla.
    private struct HistoryEntry {
        let asset: PHAsset
        let index: Int
        let wasKept: Bool
        let bytes: Int64
        /// Si el borrado ya se ejecutó en el sistema, la acción no se puede revertir del todo.
        let alreadyCommitted: Bool
    }

    // MARK: - Estado publicado

    var phase: Phase = .loading
    var assets: [PHAsset] = []
    var currentIndex: Int = 0

    var keptCount: Int = 0
    var deletedCount: Int = 0
    var bytesFreed: Int64 = 0

    var filter = FilterOptions()
    var deletionMode: DeletionMode = .endOfSession
    /// Pestaña activa. En el modelo para que cualquier vista pueda navegar.
    var selectedTab: AppTab = .explore

    /// Catálogo del explorador.
    var sectionGroups: [LibrarySectionGroup] = []
    var isLoadingSections = false
    /// Cuántas descartadas se acumulan antes de disparar el borrado en modo `.chunked`.
    var chunkSize: Int = 25
    var errorMessage: String?
    var infoMessage: String?
    var isCommitting: Bool = false

    /// Assets marcados pero aún no borrados (solo en modo lote).
    private(set) var pendingDeletion: [PHAsset] = []

    private var history: [HistoryEntry] = []
    private var sizeCache: [String: Int64] = [:]
    private var sizeTask: Task<Void, Never>?
    private var libraryObserver: PhotoLibraryChangeBroadcaster?
    private var libraryChangeTask: Task<Void, Never>?

    private let service = PhotoLibraryService.shared

    // MARK: - Derivados

    var currentAsset: PHAsset? {
        guard currentIndex >= 0, currentIndex < assets.count else { return nil }
        return assets[currentIndex]
    }

    var nextAsset: PHAsset? {
        let next = currentIndex + 1
        guard next < assets.count else { return nil }
        return assets[next]
    }

    var totalCount: Int { assets.count }

    var reviewedCount: Int { keptCount + deletedCount }

    var progress: Double {
        guard totalCount > 0 else { return 0 }
        return Double(reviewedCount) / Double(totalCount)
    }

    var canUndo: Bool {
        guard let last = history.last else { return false }
        return last.wasKept || !last.alreadyCommitted
    }

    var undoDisabledReason: String? {
        guard let last = history.last else { return String(localized: "Nothing to undo yet.") }
        if !last.wasKept && last.alreadyCommitted {
            return String(localized: "That photo is already in Recently Deleted. Recover it from the Photos app.")
        }
        return nil
    }

    var pendingCount: Int { pendingDeletion.count }

    var pendingBytes: Int64 {
        pendingDeletion.reduce(0) { $0 + (sizeCache[$1.localIdentifier] ?? 0) }
    }

    var formattedBytesFreed: String { Self.format(bytes: bytesFreed) }
    var formattedPendingBytes: String { Self.format(bytes: pendingBytes) }

    static func format(bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useGB, .useKB]
        formatter.countStyle = .file
        // Sin esto, un cero se escribe "Zero KB" en lugar de "0 KB".
        formatter.allowsNonnumericFormatting = false
        return formatter.string(fromByteCount: max(0, bytes))
    }

    // MARK: - Ciclo de vida

    func bootstrap() async {
        switch service.authorizationStatus {
        case .authorized, .limited:
            await start()
        case .notDetermined:
            let status = await service.requestAuthorization()
            if status == .authorized || status == .limited {
                await start()
            } else {
                phase = .needsPermission
            }
        default:
            phase = .needsPermission
        }
    }

    private func start() async {
        observeLibrary()
        // El catálogo primero (es la pantalla de inicio); el mazo se prepara detrás.
        async let catalog: Void = loadSections()
        await loadAssets()
        await catalog
    }

    // MARK: - Cambios en la fototeca

    /// Se suscribe a los cambios de la fototeca para que los recuentos no se queden
    /// viejos si el usuario añade o borra fotos desde fuera de la app.
    private func observeLibrary() {
        guard libraryObserver == nil else { return }
        libraryObserver = PhotoLibraryChangeBroadcaster { [weak self] in
            // `guard let` produce un `let`, no un `var`: evita el error de captura
            // de Swift 6. La clase está aislada al MainActor, luego es Sendable.
            guard let self else { return }
            Task { @MainActor in self.scheduleLibraryRefresh() }
        }
    }

    /// Un solo cambio del usuario puede disparar varias notificaciones seguidas.
    /// Se deja pasar un momento y se atiende solo la última.
    private func scheduleLibraryRefresh() {
        libraryChangeTask?.cancel()
        libraryChangeTask = Task { @MainActor [self] in
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled else { return }
            await handleLibraryChange()
        }
    }

    private func handleLibraryChange() async {
        // Mientras la propia app borra, el estado ya se está actualizando solo.
        guard !isCommitting else { return }

        // El catálogo no guarda estado de sesión: recalcularlo siempre es seguro.
        await loadSections()

        if reviewedCount == 0 || phase == .empty {
            // Sesión sin empezar: recarga limpia para recoger las fotos nuevas.
            await loadAssets()
        } else {
            // Sesión en curso: no la tires abajo. Quita solo lo que ya no existe
            // y que el usuario aún no ha visto.
            pruneUpcomingAssets()
        }
    }

    /// Elimina del tramo pendiente los assets que hayan desaparecido de la fototeca.
    /// Lo ya revisado se deja intacto: los contadores y el historial deben cuadrar
    /// con lo que el usuario hizo, aunque esas fotos ya no existan.
    private func pruneUpcomingAssets() {
        guard currentIndex < assets.count else { return }

        let upcoming = Array(assets[currentIndex...])
        let alive = service.existingIdentifiers(among: upcoming.map(\.localIdentifier))
        guard alive.count != upcoming.count else { return }

        let survivors = upcoming.filter { alive.contains($0.localIdentifier) }
        assets.replaceSubrange(currentIndex..., with: survivors)

        if currentIndex >= assets.count {
            phase = assets.isEmpty ? .empty : .finished
        }
    }

    /// Construye el catálogo del explorador. Solo cruzan tipos de valor, así que
    /// el trabajo pesado (recorrer toda la galería) va en background.
    func loadSections() async {
        isLoadingSections = true
        let groups = await Task.detached(priority: .userInitiated) {
            PhotoLibraryService.shared.librarySections()
        }.value
        sectionGroups = groups
        isLoadingSections = false
    }

    /// Elige un origen desde el explorador y salta al mazo.
    func choose(source: PhotoSource) async {
        filter.source = source
        // Las secciones de fecha ya vienen acotadas: no acumules el rango rápido.
        if source.carriesOwnDateRange {
            filter.dateRange = .anyTime
        }
        if source.isFavoritesAlbum {
            filter.skipFavorites = false
        }
        selectedTab = .review
        await loadAssets()
    }

    func loadAssets() async {
        phase = .loading
        resetCounters()

        // El fetch de Photos es lazy y rápido; lo hacemos en el MainActor para no
        // cruzar objetos PHAsset (no Sendable) entre contextos de concurrencia.
        await Task.yield()
        let fetched = service.fetchAssets(matching: filter)

        assets = fetched
        currentIndex = 0
        phase = fetched.isEmpty ? .empty : .ready

        prefetchSizes()
        warmCache()
    }

    private func resetCounters() {
        keptCount = 0
        deletedCount = 0
        bytesFreed = 0
        pendingDeletion = []
        history = []
        errorMessage = nil
        infoMessage = nil
    }

    // MARK: - Acciones de swipe

    func keep() {
        guard let asset = currentAsset else { return }
        history.append(
            HistoryEntry(
                asset: asset,
                index: currentIndex,
                wasKept: true,
                bytes: 0,
                alreadyCommitted: false
            )
        )
        keptCount += 1
        advance()
    }

    func discard() {
        guard let asset = currentAsset else { return }
        let bytes = sizeCache[asset.localIdentifier] ?? 0
        let index = currentIndex

        deletedCount += 1
        bytesFreed += bytes
        advance()

        switch deletionMode {
        case .chunked, .endOfSession:
            pendingDeletion.append(asset)
            history.append(
                HistoryEntry(asset: asset, index: index, wasKept: false,
                             bytes: bytes, alreadyCommitted: false)
            )
            if deletionMode == .chunked && pendingDeletion.count >= max(1, chunkSize) {
                Task { await commitPendingDeletions() }
            }

        case .immediate:
            history.append(
                HistoryEntry(asset: asset, index: index, wasKept: false,
                             bytes: bytes, alreadyCommitted: true)
            )
            Task { await commitImmediate(asset: asset, bytes: bytes, index: index) }
        }
    }

    private func commitImmediate(asset: PHAsset, bytes: Int64, index: Int) async {
        do {
            try await service.delete(assets: [asset])
        } catch {
            // El usuario canceló la alerta del sistema: revertimos la decisión.
            deletedCount = max(0, deletedCount - 1)
            bytesFreed = max(0, bytesFreed - bytes)
            history.removeAll { $0.asset.localIdentifier == asset.localIdentifier && !$0.wasKept }
            currentIndex = min(currentIndex, index)
            if phase == .finished { phase = .ready }
            infoMessage = String(localized: "Not deleted. You can try again.")
        }
    }

    private func advance() {
        if currentIndex + 1 >= assets.count {
            currentIndex = assets.count
            phase = .finished
        } else {
            currentIndex += 1
            warmCache()
        }
    }

    // MARK: - Deshacer

    func undo() {
        guard let last = history.last else { return }

        if !last.wasKept && last.alreadyCommitted {
            infoMessage = undoDisabledReason
            return
        }

        history.removeLast()

        if last.wasKept {
            keptCount = max(0, keptCount - 1)
        } else {
            deletedCount = max(0, deletedCount - 1)
            bytesFreed = max(0, bytesFreed - last.bytes)
            pendingDeletion.removeAll { $0.localIdentifier == last.asset.localIdentifier }
        }

        currentIndex = last.index
        if phase == .finished { phase = .ready }
    }

    // MARK: - Confirmar lote

    /// Saca fotos del lote: dejan de estar marcadas y pasan a contar como conservadas.
    func rescue(identifiers: Set<String>) {
        guard !identifiers.isEmpty else { return }
        let rescued = pendingDeletion.filter { identifiers.contains($0.localIdentifier) }
        guard !rescued.isEmpty else { return }

        pendingDeletion.removeAll { identifiers.contains($0.localIdentifier) }
        for asset in rescued {
            deletedCount = max(0, deletedCount - 1)
            bytesFreed = max(0, bytesFreed - (sizeCache[asset.localIdentifier] ?? 0))
            keptCount += 1
        }
        history.removeAll { !$0.wasKept && identifiers.contains($0.asset.localIdentifier) }
    }

    /// Devuelve fotos del lote al mazo para decidir más tarde.
    /// A diferencia de `rescue`, no cuenta como conservada: la decisión queda pendiente.
    ///
    /// El asset sigue presente en `assets` en su posición original (ya recorrida), así que
    /// lo añadimos de nuevo al final. La duplicación es inofensiva —el mazo avanza por
    /// índice, no por identificador— y hace que el total a revisar suba, que es lo correcto.
    func requeue(identifiers: Set<String>) {
        guard !identifiers.isEmpty else { return }
        let returning = pendingDeletion.filter { identifiers.contains($0.localIdentifier) }
        guard !returning.isEmpty else { return }

        pendingDeletion.removeAll { identifiers.contains($0.localIdentifier) }
        history.removeAll { !$0.wasKept && identifiers.contains($0.asset.localIdentifier) }

        for asset in returning {
            deletedCount = max(0, deletedCount - 1)
            bytesFreed = max(0, bytesFreed - (sizeCache[asset.localIdentifier] ?? 0))
            assets.append(asset)
        }

        // Si la sesión ya había terminado, `currentIndex` apunta justo al primero
        // de los reencolados, así que basta con reabrir el mazo.
        if phase == .finished || phase == .empty {
            phase = .ready
        }

        infoMessage = returning.count == 1
            ? String(localized: "Returned to the end of the deck.")
            : String(localized: "\(returning.count) returned to the end of the deck.")
    }

    /// Borra el lote pendiente. Si se pasan `identifiers`, solo esas.
    /// Una única llamada a `deleteAssets` ⇒ una única alerta del sistema.
    func commitPendingDeletions(limitedTo identifiers: Set<String>? = nil) async {
        // Evita dos alertas del sistema solapadas si el usuario sigue swipeando.
        guard !isCommitting else { return }

        let batch: [PHAsset]
        if let identifiers {
            batch = pendingDeletion.filter { identifiers.contains($0.localIdentifier) }
        } else {
            batch = pendingDeletion
        }
        guard !batch.isEmpty else { return }

        isCommitting = true
        let ids = Set(batch.map(\.localIdentifier))

        do {
            try await service.delete(assets: batch)
            pendingDeletion.removeAll { ids.contains($0.localIdentifier) }
            // Las ya borradas dejan de ser reversibles.
            history.removeAll { !$0.wasKept && ids.contains($0.asset.localIdentifier) }
            infoMessage = String(localized: "\(batch.count) moved to Recently Deleted.")
        } catch is CancellationError {
            infoMessage = String(localized: "Deletion cancelled. They're still marked.")
        } catch {
            let nsError = error as NSError
            if nsError.code == -1 || error is PhotoLibraryError {
                // El usuario pulsó «Don't Allow»: las dejamos marcadas para reintentar.
                infoMessage = String(localized: "Deletion cancelled. They're still marked.")
            } else {
                errorMessage = String(localized: "Couldn't finish deleting: \(error.localizedDescription)")
            }
        }
        isCommitting = false
    }

    // MARK: - Caché y tamaños

    private func warmCache() {
        let upper = min(currentIndex + 6, assets.count)
        guard currentIndex < upper else { return }
        let window = Array(assets[currentIndex..<upper])
        let size = CGSize(width: 1200, height: 1200)
        service.startCaching(assets: window, targetSize: size)
    }

    /// Calcula los tamaños en background para poder mostrar el espacio recuperado.
    /// Solo se cruzan Strings e Int64 entre contextos, así que es seguro en Swift 6.
    private func prefetchSizes() {
        sizeTask?.cancel()
        let identifiers = assets.map(\.localIdentifier)

        // Captura fuerte con `[self]`: una clase aislada en @MainActor es implícitamente
        // Sendable. Con `[weak self]` la closure anidada capturaría un `var`, que es
        // error en el modo de lenguaje Swift 6.
        sizeTask = Task.detached(priority: .utility) { [self] in
            PhotoLibraryService.shared.fileSizes(forLocalIdentifiers: identifiers) { chunk in
                Task { @MainActor in
                    self.merge(sizes: chunk)
                }
            }
        }
    }

    private func merge(sizes: [String: Int64]) {
        for (key, value) in sizes where sizeCache[key] == nil {
            sizeCache[key] = value
        }
    }

    func size(of asset: PHAsset) -> Int64? {
        sizeCache[asset.localIdentifier]
    }

    // MARK: - Reinicio

    func startNewSession() async {
        await loadAssets()
    }
}
