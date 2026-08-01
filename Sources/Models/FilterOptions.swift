import Foundation
import Photos

/// De dónde salen las fotos que vamos a revisar.
///
/// Guardamos el subtipo de álbum inteligente como `Int` (su `rawValue`, que en Photos
/// es un `NS_ENUM(NSInteger)`) en lugar del enum, para que `PhotoSource` sea un valor
/// puro y pueda cruzar contextos de concurrencia sin fricción.
enum PhotoSource: Hashable, Sendable, Identifiable {
    /// Toda la galería.
    case allPhotos
    /// Un álbum inteligente de iOS: capturas, selfies, vídeos, ráfagas…
    case smartAlbum(subtype: Int, title: String, icon: String)
    /// Un álbum normal: creado por ti o por una app (WhatsApp, Instagram…).
    case album(id: String, title: String, icon: String)
    /// Un rango de fechas: hoy, este mes, un año concreto…
    case dateBucket(id: String, title: String, from: Date?, to: Date?, icon: String)

    var id: String {
        switch self {
        case .allPhotos:
            return "src.all"
        case .smartAlbum(let subtype, _, _):
            return "src.smart.\(subtype)"
        case .album(let id, _, _):
            return "src.album.\(id)"
        case .dateBucket(let id, _, _, _, _):
            return "src.date.\(id)"
        }
    }

    var title: String {
        switch self {
        case .allPhotos:                          return String(localized: "All Photos")
        case .smartAlbum(_, let title, _):        return title
        case .album(_, let title, _):             return title
        case .dateBucket(_, let title, _, _, _):  return title
        }
    }

    var systemImage: String {
        switch self {
        case .allPhotos:                        return "photo.on.rectangle.angled"
        case .smartAlbum(_, _, let icon):       return icon
        case .album(_, _, let icon):            return icon
        case .dateBucket(_, _, _, _, let icon): return icon
        }
    }

    /// El álbum de favoritas es un caso especial: ahí el filtro "proteger favoritas"
    /// dejaría el mazo vacío, así que se ignora.
    var isFavoritesAlbum: Bool {
        if case .smartAlbum(let subtype, _, _) = self {
            return subtype == PHAssetCollectionSubtype.smartAlbumFavorites.rawValue
        }
        return false
    }

    /// Los rangos de fecha ya vienen acotados por la propia sección.
    var carriesOwnDateRange: Bool {
        if case .dateBucket = self { return true }
        return false
    }

    // Atajos usados por la app.
    static let screenshots = PhotoSource.smartAlbum(
        subtype: PHAssetCollectionSubtype.smartAlbumScreenshots.rawValue,
        title: String(localized: "Screenshots"),
        icon: "iphone.gen3"
    )
    static let favorites = PhotoSource.smartAlbum(
        subtype: PHAssetCollectionSubtype.smartAlbumFavorites.rawValue,
        title: String(localized: "Favorites"),
        icon: "heart.fill"
    )
}

// MARK: - Catálogo de secciones

/// Una tarjeta del explorador: un origen con su recuento y su portada.
struct LibrarySection: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let icon: String
    let count: Int
    let source: PhotoSource
    /// `localIdentifier` de la foto más reciente, para usarla de portada.
    let coverAssetID: String?
}

/// Un grupo de tarjetas con su encabezado ("Por tipo", "Por app"…).
struct LibrarySectionGroup: Identifiable, Sendable {
    let id: String
    let title: String
    let subtitle: String?
    let sections: [LibrarySection]
}

// MARK: - Filtros complementarios

/// Rango temporal rápido, aplicable sobre cualquier origen.
///
/// Los `rawValue` son identificadores estables (nunca se muestran); el texto visible
/// sale de `label`, que sí pasa por el catálogo de traducciones.
enum DateRange: String, CaseIterable, Identifiable, Sendable {
    case anyTime
    case lastMonth
    case lastSixMonths
    case lastYear
    case olderThanYear

    var id: String { rawValue }

    var label: String {
        switch self {
        case .anyTime:       return String(localized: "Any date")
        case .lastMonth:     return String(localized: "Past month")
        case .lastSixMonths: return String(localized: "Past 6 months")
        case .lastYear:      return String(localized: "Past year")
        case .olderThanYear: return String(localized: "Older than a year")
        }
    }

    /// Devuelve (desde, hasta). `nil` significa sin límite en ese extremo.
    var bounds: (from: Date?, to: Date?) {
        let now = Date()
        let cal = Calendar.current
        switch self {
        case .anyTime:       return (nil, nil)
        case .lastMonth:     return (cal.date(byAdding: .month, value: -1, to: now), nil)
        case .lastSixMonths: return (cal.date(byAdding: .month, value: -6, to: now), nil)
        case .lastYear:      return (cal.date(byAdding: .year, value: -1, to: now), nil)
        case .olderThanYear: return (nil, cal.date(byAdding: .year, value: -1, to: now))
        }
    }
}

enum SortOrder: String, CaseIterable, Identifiable, Sendable {
    case newestFirst
    case oldestFirst

    var id: String { rawValue }
    var ascending: Bool { self == .oldestFirst }

    var label: String {
        switch self {
        case .newestFirst: return String(localized: "Newest first")
        case .oldestFirst: return String(localized: "Oldest first")
        }
    }
}

/// Configuración de la sesión de limpieza.
struct FilterOptions: Equatable, Sendable {
    var source: PhotoSource = .allPhotos
    var dateRange: DateRange = .anyTime
    var sortOrder: SortOrder = .newestFirst
    /// Incluir vídeos además de fotos.
    var includeVideos: Bool = true
    /// Saltarse las favoritas, para no borrarlas por error.
    var skipFavorites: Bool = true
}
