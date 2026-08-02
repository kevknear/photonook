import Foundation
import Network
import SwiftUI

/// Qué tipo de conexión hay ahora mismo.
///
/// Solo interesa una cosa: si la red le cuesta dinero al usuario. iOS lo resuelve
/// con `isExpensive`, que es `true` en datos móviles y en "Compartir Internet", así
/// que no hace falta adivinar por el tipo de interfaz.
///
/// No requiere ningún permiso ni entitlement: es informativo.
@MainActor
@Observable
final class NetworkStatus {

    static let shared = NetworkStatus()

    /// La conexión actual tiene coste para el usuario (datos móviles, hotspot).
    /// Se asume `false` hasta que el monitor diga lo contrario.
    private(set) var isExpensive = false

    /// Hay conexión de algún tipo.
    private(set) var isConnected = true

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "photonook.network-status")

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            // Llega en una cola propia; los valores son tipos simples, así que
            // basta con saltar al MainActor para publicarlos.
            let expensive = path.isExpensive
            let connected = path.status == .satisfied
            Task { @MainActor in
                self?.isExpensive = expensive
                self?.isConnected = connected
            }
        }
        monitor.start(queue: queue)
    }

    deinit {
        monitor.cancel()
    }
}

/// Cuándo puede la app descargar originales desde iCloud.
enum CloudDownloadPolicy: String, CaseIterable, Identifiable {
    case always
    case wifiOnly
    case never

    var id: String { rawValue }

    static let storageKey = "cloudDownloadPolicy"

    var label: String {
        switch self {
        case .always:   return String(localized: "Always")
        case .wifiOnly: return String(localized: "Wi-Fi only")
        case .never:    return String(localized: "Never")
        }
    }

    var explanation: String {
        switch self {
        case .always:
            return String(localized: "Full-quality photos download whenever needed, including on cellular. Smoothest, but it can use a lot of data.")
        case .wifiOnly:
            return String(localized: "On cellular you'll see the local preview and can tap to load full quality for a specific photo.")
        case .never:
            return String(localized: "Only previews already on your device. Nothing is ever downloaded automatically.")
        }
    }

    /// ¿Se permite descargar automáticamente con la conexión actual?
    func allowsAutomaticDownload(isExpensive: Bool) -> Bool {
        switch self {
        case .always:   return true
        case .wifiOnly: return !isExpensive
        case .never:    return false
        }
    }
}
