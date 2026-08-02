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

    /// Qué se decidió sobre una foto concreta.
    enum Decision: Equatable {
        case kept
        case discarded
    }

    /// Cómo se está mirando la sección activa.
    enum ReviewMode {
        /// Cuadrícula: se ve la sección entera y se elige por dónde empezar.
        case grid
        /// Mazo: se decide foto a foto.
        case deck
    }

    /// Una decisión tomada, para poder deshacerla.
    private struct HistoryEntry {
        let asset: PHAsset
        let index: Int
        let decision: Decision
        /// Qué había antes: al poder entrar por cualquier punto, una foto puede
        /// revisarse dos veces y deshacer tiene que devolverla a su estado previo,
        /// no simplemente borrar la decisión.
        let previous: Decision?
        let bytes: Int64
        /// Si el borrado ya se ejecutó en el sistema, la acción no se puede revertir del todo.
        let alreadyCommitted: Bool

        var wasKept: Bool { decision == .kept }
    }

    // MARK: - Estado publicado

    var phase: Phase = .loading
    var assets: [PHAsset] = []
    var currentIndex: Int = 0

    var keptCount: Int = 0
    var deletedCount: Int = 0
    var bytesFreed: Int64 = 0

    /// Qué se ha decidido sobre cada foto, por identificador.
    ///
    /// Antes bastaba con `currentIndex` porque el mazo se recorría en orden y
    /// "revisadas" era todo lo que quedaba detrás. Desde que se puede entrar por
    /// cualquier punto de la galería eso ya no vale: hay que saber exactamente
    /// qué fotos tienen decisión, sin importar el orden en que se tomaron.
    private(set) var decisions: [String: Decision] = [:]

    var filter = FilterOptions()
    var deletionMode: DeletionMode = .endOfSession
    /// Pestaña activa. En el modelo para que cualquier vista pueda navegar.
    var selectedTab: AppTab = .explore
    /// Cuadrícula o mazo dentro de la pestaña Revisar.
    var reviewMode: ReviewMode = .grid

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
    /// Decisiones tal como están en disco, de todas las secciones, no solo la actual.
    private var storedDecisions: [String: DecisionStore.Entry] = [:]
    private var saveTask: Task<Void, Never>?

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

    /// Qué se decidió sobre una foto, o `nil` si aún no se ha visto.
    func decision(for asset: PHAsset) -> Decision? {
        decisions[asset.localIdentifier]
    }

    /// Cuántas quedan por decidir en la sección.
    var remainingCount: Int { max(0, totalCount - reviewedCount) }

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
        loadStoredDecisions()
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

    /// Elige un origen desde el explorador y abre su cuadrícula.
    ///
    /// No salta directo al mazo: con una sección de miles de fotos, empezar
    /// siempre por la primera es inservible. La cuadrícula deja elegir el punto
    /// de entrada.
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
        reviewMode = .grid
        await loadAssets()
    }

    // MARK: - Entrar y salir del mazo

    /// Abre el mazo empezando por una foto concreta de la cuadrícula.
    func startDeck(at index: Int) {
        guard assets.indices.contains(index) else { return }
        currentIndex = index
        if phase == .finished { phase = .ready }
        reviewMode = .deck
        warmCache()
    }

    /// Abre el mazo por la primera foto sin decidir, o por el principio si no queda ninguna.
    func startDeckFromFirstUndecided() {
        let index = assets.firstIndex { decisions[$0.localIdentifier] == nil } ?? 0
        startDeck(at: index)
    }

    /// Vuelve a la cuadrícula sin perder nada de la sesión.
    func showGrid() {
        reviewMode = .grid
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

        // Recupera lo decidido en sesiones anteriores sobre estas mismas fotos.
        restoreProgress()

        prefetchSizes()
        warmCache()
    }

    private func resetCounters() {
        keptCount = 0
        deletedCount = 0
        bytesFreed = 0
        decisions = [:]
        pendingDeletion = []
        history = []
        errorMessage = nil
        infoMessage = nil
    }

    // MARK: - Persistencia de las decisiones

    /// Carga del disco lo decidido en sesiones anteriores, de todas las secciones.
    private func loadStoredDecisions() {
        storedDecisions = DecisionStore.load()
    }

    /// Guarda con un pequeño retardo: durante una tanda de swipes esto se llamaría
    /// en cada foto, y escribir miles de entradas cada vez sería absurdo.
    private func scheduleDecisionSave() {
        saveTask?.cancel()
        saveTask = Task { @MainActor [self] in
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            guard !Task.isCancelled else { return }
            let snapshot = storedDecisions
            Task.detached(priority: .utility) { DecisionStore.save(snapshot) }
        }
    }

    private func persist(_ decision: Decision?, for id: String) {
        if let decision {
            storedDecisions[id] = DecisionStore.Entry(
                decision: decision == .kept ? "kept" : "discarded",
                date: Date()
            )
        } else {
            storedDecisions.removeValue(forKey: id)
        }
        scheduleDecisionSave()
    }

    /// Rehace contadores y lote pendiente de la sección recién cargada a partir
    /// de lo que ya estaba decidido.
    ///
    /// El lote no se guarda aparte: si una foto está marcada como descartada y
    /// **sigue existiendo** en la fototeca, es que nunca llegó a borrarse. Esa
    /// invariante basta para reconstruirlo sin almacenar nada más.
    private func restoreProgress() {
        keptCount = 0
        deletedCount = 0
        bytesFreed = 0
        pendingDeletion = []
        decisions = [:]

        for asset in assets {
            let id = asset.localIdentifier
            guard let stored = storedDecisions[id] else { continue }

            let decision: Decision = stored.decision == "kept" ? .kept : .discarded
            decisions[id] = decision

            switch decision {
            case .kept:
                keptCount += 1
            case .discarded:
                deletedCount += 1
                bytesFreed += sizeCache[id] ?? 0
                pendingDeletion.append(asset)
            }
        }
    }

    /// Olvida lo decidido sobre las fotos de la sección actual.
    func forgetProgressForCurrentSection() {
        for asset in assets {
            storedDecisions.removeValue(forKey: asset.localIdentifier)
        }
        scheduleDecisionSave()
        restoreProgress()
        history = []
        currentIndex = 0
        if phase == .finished { phase = .ready }
    }

    /// Olvida todo el historial de revisión, de todas las secciones.
    func forgetAllProgress() {
        storedDecisions = [:]
        saveTask?.cancel()
        DecisionStore.clear()
        restoreProgress()
        history = []
        currentIndex = 0
        if phase == .finished { phase = .ready }
        infoMessage = String(localized: "Review history cleared.")
    }

    // MARK: - Registro de decisiones

    /// Anota la decisión sobre una foto y ajusta los contadores.
    ///
    /// Devuelve la decisión anterior, si la había. Como se puede entrar por
    /// cualquier punto de la cuadrícula, una foto puede revisarse más de una vez:
    /// en ese caso hay que deshacer el efecto de la decisión previa antes de
    /// aplicar la nueva, o los contadores se descuadran.
    @discardableResult
    private func record(_ decision: Decision, for asset: PHAsset, bytes: Int64) -> Decision? {
        let id = asset.localIdentifier
        let previous = decisions[id]

        switch previous {
        case .kept:
            keptCount = max(0, keptCount - 1)
        case .discarded:
            deletedCount = max(0, deletedCount - 1)
            bytesFreed = max(0, bytesFreed - (sizeCache[id] ?? 0))
            pendingDeletion.removeAll { $0.localIdentifier == id }
        case nil:
            break
        }

        decisions[id] = decision
        persist(decision, for: id)

        switch decision {
        case .kept:
            keptCount += 1
        case .discarded:
            deletedCount += 1
            bytesFreed += bytes
        }

        return previous
    }

    // MARK: - Acciones de swipe

    func keep() {
        guard let asset = currentAsset else { return }
        let previous = record(.kept, for: asset, bytes: 0)
        history.append(
            HistoryEntry(
                asset: asset,
                index: currentIndex,
                decision: .kept,
                previous: previous,
                bytes: 0,
                alreadyCommitted: false
            )
        )
        advance()
    }

    func discard() {
        guard let asset = currentAsset else { return }
        let bytes = sizeCache[asset.localIdentifier] ?? 0
        let index = currentIndex

        let previous = record(.discarded, for: asset, bytes: bytes)
        advance()

        switch deletionMode {
        case .chunked, .endOfSession:
            pendingDeletion.append(asset)
            history.append(
                HistoryEntry(asset: asset, index: index, decision: .discarded,
                             previous: previous, bytes: bytes, alreadyCommitted: false)
            )
            if deletionMode == .chunked && pendingDeletion.count >= max(1, chunkSize) {
                Task { await commitPendingDeletions() }
            }

        case .immediate:
            history.append(
                HistoryEntry(asset: asset, index: index, decision: .discarded,
                             previous: previous, bytes: bytes, alreadyCommitted: true)
            )
            Task { await commitImmediate(asset: asset, bytes: bytes, index: index) }
        }
    }

    private func commitImmediate(asset: PHAsset, bytes: Int64, index: Int) async {
        do {
            try await service.delete(assets: [asset])
        } catch {
            // El usuario canceló la alerta del sistema: revertimos la decisión.
            let id = asset.localIdentifier
            let entry = history.last { $0.asset.localIdentifier == id && !$0.wasKept }
            restore(entry?.previous, for: asset, bytes: bytes)
            history.removeAll { $0.asset.localIdentifier == id && !$0.wasKept }
            currentIndex = min(currentIndex, index)
            if phase == .finished { phase = .ready }
            infoMessage = String(localized: "Not deleted. You can try again.")
        }
    }

    /// Devuelve una foto a una decisión anterior, o la deja sin decidir si era `nil`.
    private func restore(_ decision: Decision?, for asset: PHAsset, bytes: Int64) {
        let id = asset.localIdentifier

        switch decisions[id] {
        case .kept:
            keptCount = max(0, keptCount - 1)
        case .discarded:
            deletedCount = max(0, deletedCount - 1)
            bytesFreed = max(0, bytesFreed - bytes)
            pendingDeletion.removeAll { $0.localIdentifier == id }
        case nil:
            break
        }

        guard let decision else {
            decisions.removeValue(forKey: id)
            persist(nil, for: id)
            return
        }

        decisions[id] = decision
        persist(decision, for: id)
        switch decision {
        case .kept:
            keptCount += 1
        case .discarded:
            deletedCount += 1
            bytesFreed += sizeCache[id] ?? 0
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
        // Vuelve al estado que tenía la foto antes de esta decisión, que no
        // siempre es "sin decidir": pudo revisarse ya en otra pasada.
        restore(last.previous, for: last.asset, bytes: last.bytes)

        currentIndex = last.index
        if phase == .finished { phase = .ready }
        // Deshacer implica volver a mirar esa foto, así que abre el mazo.
        reviewMode = .deck
    }

    // MARK: - Confirmar lote

    /// Saca fotos del lote: dejan de estar marcadas y pasan a contar como conservadas.
    func rescue(identifiers: Set<String>) {
        guard !identifiers.isEmpty else { return }
        let rescued = pendingDeletion.filter { identifiers.contains($0.localIdentifier) }
        guard !rescued.isEmpty else { return }

        pendingDeletion.removeAll { identifiers.contains($0.localIdentifier) }
        for asset in rescued {
            // Pasa de descartada a conservada: `record` cuadra los contadores.
            record(.kept, for: asset, bytes: 0)
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
            // Vuelve a quedar sin decidir: no es conservada, es "ya veré".
            restore(nil, for: asset, bytes: sizeCache[asset.localIdentifier] ?? 0)
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
            // Si ya estaba descartada pero aún no sabíamos cuánto pesaba —al
            // restaurar progreso de otra sesión, o al descartar antes de que el
            // cálculo llegase—, súmalo ahora. Solo entra aquí la primera vez que
            // se conoce el tamaño, así que no puede contarse dos veces.
            if decisions[key] == .discarded {
                bytesFreed += value
            }
        }
    }

    func size(of asset: PHAsset) -> Int64? {
        sizeCache[asset.localIdentifier]
    }

    // MARK: - Reinicio

    /// Repasa la sección desde cero: olvida lo decidido sobre sus fotos.
    /// Sin esto, con la persistencia activa recargaría y aparecería todo ya decidido.
    func startNewSession() async {
        reviewMode = .grid
        for asset in assets {
            storedDecisions.removeValue(forKey: asset.localIdentifier)
        }
        scheduleDecisionSave()
        await loadAssets()
    }
}
