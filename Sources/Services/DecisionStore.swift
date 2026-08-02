import Foundation

/// Guarda en disco qué se ha decidido sobre cada foto, para que el progreso
/// sobreviva a cerrar la app.
///
/// Nadie limpia una galería de 12.000 fotos de una sentada: se hace en ratos
/// sueltos a lo largo de días. Sin esto, cada arranque empezaría de cero y la
/// cuadrícula perdería la mitad de su sentido.
///
/// Va a un archivo JSON en Application Support en vez de a `UserDefaults`:
/// son miles de entradas y `UserDefaults` se carga entero en memoria al arrancar.
enum DecisionStore {

    /// Una decisión con su fecha, para poder podar las viejas.
    struct Entry: Codable, Sendable {
        let decision: String
        let date: Date
    }

    /// Las entradas más antiguas que esto se descartan al cargar. Sin un límite,
    /// el archivo crecería sin fin con fotos que ya ni existen.
    private static let maxAge: TimeInterval = 180 * 24 * 60 * 60

    private static var fileURL: URL? {
        guard let dir = try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ) else { return nil }
        return dir.appendingPathComponent("review-decisions.json")
    }

    /// Lee el archivo y devuelve solo las entradas aún vigentes.
    static func load() -> [String: Entry] {
        guard let url = fileURL,
              let data = try? Data(contentsOf: url),
              let stored = try? JSONDecoder().decode([String: Entry].self, from: data)
        else { return [:] }

        let cutoff = Date().addingTimeInterval(-maxAge)
        return stored.filter { $0.value.date >= cutoff }
    }

    static func save(_ entries: [String: Entry]) {
        guard let url = fileURL else { return }
        guard !entries.isEmpty else {
            try? FileManager.default.removeItem(at: url)
            return
        }
        guard let data = try? JSONEncoder().encode(entries) else { return }
        try? data.write(to: url, options: .atomic)
    }

    static func clear() {
        guard let url = fileURL else { return }
        try? FileManager.default.removeItem(at: url)
    }
}
