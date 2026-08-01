import Foundation
import Photos
import UIKit

/// Los objetos de Photos (PHAsset, PHFetchResult) son inmutables y seguros de leer
/// desde cualquier hilo, así que marcamos el servicio como `@unchecked Sendable`.
final class PhotoLibraryService: @unchecked Sendable {

    static let shared = PhotoLibraryService()

    private let imageManager = PHCachingImageManager()

    private init() {}

    // MARK: - Permisos

    var authorizationStatus: PHAuthorizationStatus {
        PHPhotoLibrary.authorizationStatus(for: .readWrite)
    }

    func requestAuthorization() async -> PHAuthorizationStatus {
        await withCheckedContinuation { continuation in
            PHPhotoLibrary.requestAuthorization(for: .readWrite) { status in
                continuation.resume(returning: status)
            }
        }
    }

    // MARK: - Fetch de assets

    /// Predicado base: qué tipos de medio entran.
    private func mediaPredicate(includeVideos: Bool) -> NSPredicate {
        includeVideos
            ? NSPredicate(
                format: "mediaType == %d OR mediaType == %d",
                PHAssetMediaType.image.rawValue,
                PHAssetMediaType.video.rawValue
              )
            : NSPredicate(format: "mediaType == %d", PHAssetMediaType.image.rawValue)
    }

    /// Devuelve los assets que cumplen los filtros, ya materializados en un array.
    /// Aislado al MainActor porque `PHAsset` no es `Sendable`.
    @MainActor
    func fetchAssets(matching filter: FilterOptions) -> [PHAsset] {
        let options = PHFetchOptions()
        options.sortDescriptors = [
            NSSortDescriptor(key: "creationDate", ascending: filter.sortOrder.ascending)
        ]

        var predicates: [NSPredicate] = [mediaPredicate(includeVideos: filter.includeVideos)]

        // El rango rápido solo se aplica si el origen no trae ya el suyo.
        if !filter.source.carriesOwnDateRange {
            let bounds = filter.dateRange.bounds
            if let from = bounds.from {
                predicates.append(NSPredicate(format: "creationDate >= %@", from as NSDate))
            }
            if let to = bounds.to {
                predicates.append(NSPredicate(format: "creationDate <= %@", to as NSDate))
            }
        }

        // Proteger favoritas no tiene sentido dentro del propio álbum de favoritas.
        if filter.skipFavorites && !filter.source.isFavoritesAlbum {
            predicates.append(NSPredicate(format: "favorite == NO"))
        }

        switch filter.source {
        case .allPhotos:
            options.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
            return materialize(PHAsset.fetchAssets(with: options))

        case .smartAlbum(let raw, _, _):
            options.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
            guard let subtype = PHAssetCollectionSubtype(rawValue: raw),
                  let collection = smartAlbum(subtype)
            else { return [] }
            return materialize(PHAsset.fetchAssets(in: collection, options: options))

        case .album(let id, _, _):
            options.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
            let collections = PHAssetCollection.fetchAssetCollections(
                withLocalIdentifiers: [id], options: nil
            )
            guard let collection = collections.firstObject else { return [] }
            return materialize(PHAsset.fetchAssets(in: collection, options: options))

        case .dateBucket(_, _, let from, let to, _):
            if let from {
                predicates.append(NSPredicate(format: "creationDate >= %@", from as NSDate))
            }
            if let to {
                predicates.append(NSPredicate(format: "creationDate < %@", to as NSDate))
            }
            options.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
            return materialize(PHAsset.fetchAssets(with: options))
        }
    }

    private func materialize(_ result: PHFetchResult<PHAsset>) -> [PHAsset] {
        var assets: [PHAsset] = []
        assets.reserveCapacity(result.count)
        result.enumerateObjects { asset, _, _ in assets.append(asset) }
        return assets
    }

    private func smartAlbum(_ subtype: PHAssetCollectionSubtype) -> PHAssetCollection? {
        PHAssetCollection.fetchAssetCollections(
            with: .smartAlbum, subtype: subtype, options: nil
        ).firstObject
    }

    // MARK: - Catálogo de secciones

    /// Álbumes inteligentes que vale la pena ofrecer, en orden de utilidad para limpiar.
    private static var smartAlbumSpecs: [(PHAssetCollectionSubtype, String, String)] {
        [
            (.smartAlbumScreenshots,   String(localized: "Screenshots"),    "iphone.gen3"),
            (.smartAlbumVideos,        String(localized: "Videos"),         "video.fill"),
            (.smartAlbumSelfPortraits, String(localized: "Selfies"),        "person.crop.square"),
            (.smartAlbumBursts,        String(localized: "Bursts"),         "square.stack.3d.down.right.fill"),
            (.smartAlbumLivePhotos,    String(localized: "Live Photos"),    "livephoto"),
            (.smartAlbumPanoramas,     String(localized: "Panoramas"),      "pano.fill"),
            (.smartAlbumDepthEffect,   String(localized: "Portraits"),      "person.crop.circle.fill"),
            (.smartAlbumSlomoVideos,   String(localized: "Slo-mo"),         "slowmo"),
            (.smartAlbumTimelapses,    String(localized: "Time-lapse"),     "timelapse"),
            (.smartAlbumAnimated,      String(localized: "GIFs"),           "rectangle.stack.fill"),
            (.smartAlbumRecentlyAdded, String(localized: "Recently Added"), "clock.arrow.circlepath"),
            (.smartAlbumFavorites,     String(localized: "Favorites"),      "heart.fill"),
        ]
    }

    /// Apps que suelen crear su propio álbum. Se detectan por nombre.
    private static let messagingApps = [
        "whatsapp", "telegram", "messenger", "signal", "line", "wechat",
        "viber", "skype", "discord", "slack", "imo", "kakao",
    ]
    private static let socialApps = [
        "instagram", "facebook", "tiktok", "snapchat", "twitter", "x app",
        "threads", "pinterest", "reddit", "linkedin", "tumblr", "bereal",
    ]
    private static let toolApps = [
        "chrome", "safari", "gmail", "outlook", "drive", "dropbox", "onedrive",
        "vsco", "lightroom", "snapseed", "canva", "capcut", "shazam", "spotify",
        "zoom", "teams", "notion", "pinterest",
    ]

    private static func appIcon(for name: String) -> String? {
        let lower = name.lowercased()
        if messagingApps.contains(where: lower.contains) {
            return "bubble.left.and.text.bubble.right.fill"
        }
        if socialApps.contains(where: lower.contains) {
            return "person.2.fill"
        }
        if toolApps.contains(where: lower.contains) {
            return "square.grid.2x2.fill"
        }
        return nil
    }

    /// Construye todo el catálogo del explorador.
    /// Devuelve solo tipos de valor, así que es seguro llamarlo desde una tarea en background.
    func librarySections() -> [LibrarySectionGroup] {
        var groups: [LibrarySectionGroup] = []

        let media = mediaPredicate(includeVideos: true)

        // --- Toda la galería -------------------------------------------------
        let allOptions = PHFetchOptions()
        allOptions.predicate = media
        allOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        let allAssets = PHAsset.fetchAssets(with: allOptions)

        if allAssets.count > 0 {
            groups.append(
                LibrarySectionGroup(
                    id: "group.all",
                    title: String(localized: "Your whole library"),
                    subtitle: nil,
                    sections: [
                        LibrarySection(
                            id: PhotoSource.allPhotos.id,
                            title: String(localized: "All Photos"),
                            icon: "photo.on.rectangle.angled",
                            count: allAssets.count,
                            source: .allPhotos,
                            coverAssetID: allAssets.firstObject?.localIdentifier
                        )
                    ]
                )
            )
        }

        // --- Por tipo --------------------------------------------------------
        var typeSections: [LibrarySection] = []
        for (subtype, title, icon) in Self.smartAlbumSpecs {
            guard let collection = smartAlbum(subtype) else { continue }
            let options = PHFetchOptions()
            options.predicate = media
            options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
            let result = PHAsset.fetchAssets(in: collection, options: options)
            guard result.count > 0 else { continue }

            let source = PhotoSource.smartAlbum(
                subtype: subtype.rawValue, title: title, icon: icon
            )
            typeSections.append(
                LibrarySection(
                    id: source.id,
                    title: title,
                    icon: icon,
                    count: result.count,
                    source: source,
                    coverAssetID: result.firstObject?.localIdentifier
                )
            )
        }
        if !typeSections.isEmpty {
            groups.append(
                LibrarySectionGroup(
                    id: "group.types",
                    title: String(localized: "By type"),
                    subtitle: String(localized: "Smart albums iOS keeps up to date"),
                    sections: typeSections
                )
            )
        }

        // --- Álbumes: separar los de apps de los tuyos ------------------------
        var appSections: [LibrarySection] = []
        var mineSections: [LibrarySection] = []

        let albumOptions = PHFetchOptions()
        albumOptions.sortDescriptors = [NSSortDescriptor(key: "localizedTitle", ascending: true)]
        let albums = PHAssetCollection.fetchAssetCollections(
            with: .album, subtype: .any, options: albumOptions
        )

        albums.enumerateObjects { collection, _, _ in
            let title = collection.localizedTitle ?? String(localized: "Untitled album")
            let options = PHFetchOptions()
            options.predicate = media
            options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
            let result = PHAsset.fetchAssets(in: collection, options: options)
            guard result.count > 0 else { return }

            let detectedIcon = Self.appIcon(for: title)
            let icon = detectedIcon ?? "rectangle.stack.fill"
            let source = PhotoSource.album(
                id: collection.localIdentifier, title: title, icon: icon
            )
            let section = LibrarySection(
                id: source.id,
                title: title,
                icon: icon,
                count: result.count,
                source: source,
                coverAssetID: result.firstObject?.localIdentifier
            )

            if detectedIcon != nil {
                appSections.append(section)
            } else {
                mineSections.append(section)
            }
        }

        // Los álbumes de apps suelen ser los más gordos: ordénalos por tamaño.
        appSections.sort { $0.count > $1.count }

        if !appSections.isEmpty {
            groups.append(
                LibrarySectionGroup(
                    id: "group.apps",
                    title: String(localized: "By app"),
                    subtitle: String(localized: "Albums created by other apps"),
                    sections: appSections
                )
            )
        }
        if !mineSections.isEmpty {
            groups.append(
                LibrarySectionGroup(
                    id: "group.mine",
                    title: String(localized: "My albums"),
                    subtitle: nil,
                    sections: mineSections
                )
            )
        }

        // --- Por tiempo ------------------------------------------------------
        groups.append(contentsOf: timeGroups(from: allAssets))

        return groups
    }

    /// Una sola pasada sobre la galería para calcular todos los recuentos temporales.
    private func timeGroups(from assets: PHFetchResult<PHAsset>) -> [LibrarySectionGroup] {
        guard assets.count > 0 else { return [] }

        let calendar = Calendar.current
        let now = Date()
        let startOfToday = calendar.startOfDay(for: now)
        let startOfWeek = calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? startOfToday
        let startOfMonth = calendar.dateInterval(of: .month, for: now)?.start ?? startOfToday

        var todayCount = 0, todayCover: String?
        var weekCount = 0, weekCover: String?
        var monthCount = 0, monthCover: String?

        var yearCounts: [Int: Int] = [:]
        var yearCovers: [Int: String] = [:]
        var monthCounts: [DateComponents: Int] = [:]
        var monthCovers: [DateComponents: String] = [:]

        assets.enumerateObjects { asset, _, _ in
            guard let date = asset.creationDate else { return }
            let id = asset.localIdentifier

            if date >= startOfToday {
                todayCount += 1
                if todayCover == nil { todayCover = id }
            }
            if date >= startOfWeek {
                weekCount += 1
                if weekCover == nil { weekCover = id }
            }
            if date >= startOfMonth {
                monthCount += 1
                if monthCover == nil { monthCover = id }
            }

            let parts = calendar.dateComponents([.year, .month], from: date)
            guard let year = parts.year else { return }

            yearCounts[year, default: 0] += 1
            if yearCovers[year] == nil { yearCovers[year] = id }

            let monthKey = DateComponents(year: year, month: parts.month)
            monthCounts[monthKey, default: 0] += 1
            if monthCovers[monthKey] == nil { monthCovers[monthKey] = id }
        }

        var groups: [LibrarySectionGroup] = []

        // Reciente
        var recent: [LibrarySection] = []
        func addRecent(_ id: String, _ title: String, _ icon: String,
                       _ count: Int, _ cover: String?, from: Date) {
            guard count > 0 else { return }
            let source = PhotoSource.dateBucket(
                id: id, title: title, from: from, to: nil, icon: icon
            )
            recent.append(
                LibrarySection(id: source.id, title: title, icon: icon,
                               count: count, source: source, coverAssetID: cover)
            )
        }
        addRecent("today", String(localized: "Today"), "sun.max.fill",
                  todayCount, todayCover, from: startOfToday)
        addRecent("week", String(localized: "This week"), "calendar.badge.clock",
                  weekCount, weekCover, from: startOfWeek)
        addRecent("month", String(localized: "This month"), "calendar",
                  monthCount, monthCover, from: startOfMonth)

        if !recent.isEmpty {
            groups.append(
                LibrarySectionGroup(id: "group.recent", title: String(localized: "Recent"),
                                    subtitle: nil, sections: recent)
            )
        }

        // Por año
        let yearSections: [LibrarySection] = yearCounts.keys.sorted(by: >).compactMap { year in
            guard let count = yearCounts[year], count > 0,
                  let from = calendar.date(from: DateComponents(year: year, month: 1, day: 1)),
                  let to = calendar.date(from: DateComponents(year: year + 1, month: 1, day: 1))
            else { return nil }

            let source = PhotoSource.dateBucket(
                id: "year.\(year)", title: "\(year)", from: from, to: to, icon: "calendar"
            )
            return LibrarySection(
                id: source.id, title: "\(year)", icon: "calendar",
                count: count, source: source, coverAssetID: yearCovers[year]
            )
        }
        if !yearSections.isEmpty {
            groups.append(
                LibrarySectionGroup(id: "group.years", title: String(localized: "By year"),
                                    subtitle: nil, sections: yearSections)
            )
        }

        // Por mes: los últimos 12 con contenido.
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.setLocalizedDateFormatFromTemplate("MMMM yyyy")

        let sortedMonths = monthCounts.keys.sorted { lhs, rhs in
            (lhs.year ?? 0, lhs.month ?? 0) > (rhs.year ?? 0, rhs.month ?? 0)
        }
        let monthSections: [LibrarySection] = sortedMonths.prefix(12).compactMap { key in
            guard let count = monthCounts[key], count > 0,
                  let year = key.year, let month = key.month,
                  let from = calendar.date(from: DateComponents(year: year, month: month, day: 1)),
                  let to = calendar.date(byAdding: .month, value: 1, to: from)
            else { return nil }

            let title = formatter.string(from: from).capitalized
            let source = PhotoSource.dateBucket(
                id: "month.\(year)-\(month)", title: title,
                from: from, to: to, icon: "calendar"
            )
            return LibrarySection(
                id: source.id, title: title, icon: "calendar",
                count: count, source: source, coverAssetID: monthCovers[key]
            )
        }
        if !monthSections.isEmpty {
            groups.append(
                LibrarySectionGroup(id: "group.months", title: String(localized: "By month"),
                                    subtitle: String(localized: "The last 12 months with photos"),
                                    sections: monthSections)
            )
        }

        return groups
    }

    // MARK: - Imágenes

    /// Carga la imagen de un asset en alta calidad. Un único callback garantizado.
    @MainActor
    func image(for asset: PHAsset, targetSize: CGSize) async -> UIImage? {
        await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.deliveryMode = .highQualityFormat
            options.resizeMode = .fast
            options.isNetworkAccessAllowed = true
            options.isSynchronous = false

            imageManager.requestImage(
                for: asset,
                targetSize: targetSize,
                contentMode: .aspectFit,
                options: options
            ) { image, _ in
                continuation.resume(returning: image)
            }
        }
    }

    /// Carga una imagen a partir de su identificador. Útil para portadas del explorador.
    @MainActor
    func image(withIdentifier identifier: String, targetSize: CGSize) async -> UIImage? {
        let fetched = PHAsset.fetchAssets(withLocalIdentifiers: [identifier], options: nil)
        guard let asset = fetched.firstObject else { return nil }
        return await image(for: asset, targetSize: targetSize)
    }

    /// Pre-carga en caché las imágenes de los próximos assets para que el deck vaya fluido.
    @MainActor
    func startCaching(assets: [PHAsset], targetSize: CGSize) {
        guard !assets.isEmpty else { return }
        imageManager.startCachingImages(
            for: assets, targetSize: targetSize, contentMode: .aspectFit, options: nil
        )
    }

    @MainActor
    func stopCachingAll() {
        imageManager.stopCachingImagesForAllAssets()
    }

    // MARK: - Tamaño en disco

    /// Tamaño aproximado en bytes. Llamar fuera del main thread: es una operación lenta.
    func fileSize(of asset: PHAsset) -> Int64 {
        let resources = PHAssetResource.assetResources(for: asset)
        for resource in resources {
            if let size = resource.value(forKey: "fileSize") as? Int64 {
                return size
            }
            if let size = resource.value(forKey: "fileSize") as? NSNumber {
                return size.int64Value
            }
        }
        return 0
    }

    /// Calcula tamaños a partir de identificadores (tipos Sendable, apto para background).
    /// Reporta resultados parciales por lotes vía `onChunk`.
    func fileSizes(
        forLocalIdentifiers identifiers: [String],
        chunkSize: Int = 40,
        onChunk: @escaping @Sendable ([String: Int64]) -> Void
    ) {
        for slice in identifiers.chunked(into: chunkSize) {
            guard !Task.isCancelled else { return }
            let fetched = PHAsset.fetchAssets(withLocalIdentifiers: slice, options: nil)
            var partial: [String: Int64] = [:]
            fetched.enumerateObjects { asset, _, _ in
                partial[asset.localIdentifier] = self.fileSize(of: asset)
            }
            onChunk(partial)
        }
    }

    // MARK: - Borrado

    /// Envía los assets a "Eliminados recientemente".
    /// iOS muestra su propia alerta de confirmación en cada llamada.
    @MainActor
    func delete(assets: [PHAsset]) async throws {
        guard !assets.isEmpty else { return }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.deleteAssets(assets as NSArray)
            } completionHandler: { success, error in
                if success {
                    continuation.resume()
                } else if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(throwing: PhotoLibraryError.cancelled)
                }
            }
        }
    }
}

extension Array {
    func chunked(into size: Int) -> [[Element]] {
        guard size > 0 else { return [self] }
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0 ..< Swift.min($0 + size, count)])
        }
    }
}

enum PhotoLibraryError: LocalizedError {
    case cancelled

    var errorDescription: String? {
        switch self {
        case .cancelled: return String(localized: "Deletion cancelled.")
        }
    }
}
