import SwiftUI
import UIKit

// MARK: - Utilidades de color

extension UIColor {
    /// `UIColor(hex: 0xF5EFE6)`
    convenience init(hex: UInt32) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}

extension Color {
    /// Color que cambia solo según el modo claro/oscuro del sistema.
    static func adaptive(light: UInt32, dark: UInt32) -> Color {
        Color(UIColor { traits in
            UIColor(hex: traits.userInterfaceStyle == .dark ? dark : light)
        })
    }
}

// MARK: - Paleta

/// Paleta "papel cálido": crema y arena en claro, carbón cálido y ámbar en oscuro.
/// Todo el color de la app sale de aquí; ninguna vista define tonos propios.
enum Theme {

    // Fondos
    /// Fondo general de la app.
    static let background = Color.adaptive(light: 0xF5EFE6, dark: 0x17130F)
    /// Fondo secundario, un paso más profundo que el general.
    static let backgroundDeep = Color.adaptive(light: 0xEDE4D6, dark: 0x100D0A)

    // Superficies (tarjetas, barras, celdas)
    /// Papel: la superficie sobre la que descansa el contenido.
    static let surface = Color.adaptive(light: 0xFFFBF5, dark: 0x241D17)
    /// Superficie sutil, para agrupar sin llamar la atención.
    static let surfaceMuted = Color.adaptive(light: 0xF0E7D9, dark: 0x2E2620)
    /// Hueco donde va la foto dentro de la tarjeta.
    static let photoWell = Color.adaptive(light: 0xE6DAC8, dark: 0x120F0C)

    // Texto
    static let textPrimary = Color.adaptive(light: 0x3B322C, dark: 0xF2E9DC)
    static let textSecondary = Color.adaptive(light: 0x8A7B6D, dark: 0xA99C8C)
    static let textOnAccent = Color.adaptive(light: 0xFFFBF5, dark: 0x17130F)

    // Acentos semánticos
    /// Terracota: descartar / borrar.
    static let discard = Color.adaptive(light: 0xC4703F, dark: 0xE08A5B)
    /// Salvia: conservar.
    static let keep = Color.adaptive(light: 0x6F8563, dark: 0x9FB08A)
    /// Miel: deshacer, avisos, pendiente.
    static let pending = Color.adaptive(light: 0xB08832, dark: 0xD9B45F)
    /// Azul apagado: información neutra (espacio, contadores).
    static let info = Color.adaptive(light: 0x6A7F94, dark: 0x93A9BE)

    // Detalles
    /// Bordes y separadores.
    static let hairline = Color.adaptive(light: 0xDCCDB6, dark: 0x3D342A)
    /// Sombra suave y cálida.
    static let shadow = Color.adaptive(light: 0x8A6A45, dark: 0x000000)

    /// Degradado de fondo, muy leve, para que la pantalla no se vea plana.
    static var backgroundGradient: LinearGradient {
        LinearGradient(
            colors: [background, backgroundDeep],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}

// MARK: - Apariencia elegida por el usuario

/// Permite forzar claro u oscuro dentro de la app, o dejar que mande el sistema.
/// Se guarda en `UserDefaults` bajo la clave `appearanceMode`.
enum AppearanceMode: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: return String(localized: "System")
        case .light:  return String(localized: "Light")
        case .dark:   return String(localized: "Dark")
        }
    }

    /// `nil` significa "no impongas nada, hereda del sistema".
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light:  return .light
        case .dark:   return .dark
        }
    }

    var icon: String {
        switch self {
        case .system: return "iphone"
        case .light:  return "sun.max.fill"
        case .dark:   return "moon.fill"
        }
    }

    static let storageKey = "appearanceMode"
}

// MARK: - Métricas

/// Espaciado y radios en una escala consistente.
enum Metrics {
    static let cardRadius: CGFloat = 26
    static let wellRadius: CGFloat = 18
    static let panelRadius: CGFloat = 20
    static let cellRadius: CGFloat = 12
    static let controlRadius: CGFloat = 16

    static let gutter: CGFloat = 16
    static let tight: CGFloat = 8
}

// MARK: - Tipografía

extension Font {
    /// Tipografía redondeada de la app. **Escala con Dynamic Type.**
    ///
    /// Se pasa un tamaño en puntos por comodidad al maquetar, pero internamente se
    /// traduce al estilo de texto del sistema más cercano. Eso es lo que hace que el
    /// texto crezca cuando el usuario sube el tamaño en Ajustes → Pantalla y brillo.
    /// Un `.system(size:)` a pelo ignora ese ajuste por completo.
    static func cozy(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        let style: Font.TextStyle
        switch size {
        case ..<11.5: style = .caption2
        case ..<12.5: style = .caption
        case ..<14:   style = .footnote
        case ..<15.5: style = .subheadline
        case ..<16.5: style = .callout
        case ..<18:   style = .body
        case ..<21:   style = .title3
        case ..<23:   style = .title2
        case ..<28:   style = .title
        default:      style = .largeTitle
        }
        return .system(style, design: .rounded, weight: weight)
    }

    /// Tamaño fijo que **no** escala. Solo para glifos e insignias que viven dentro de
    /// un marco de tamaño fijo, donde crecer rompería la composición.
    static func fixed(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }
}

// MARK: - Modificadores reutilizables

/// Superficie de papel con sombra cálida: la usan las tarjetas y paneles.
struct PaperSurface: ViewModifier {
    var radius: CGFloat = Metrics.panelRadius
    var elevation: CGFloat = 6

    func body(content: Content) -> some View {
        content
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(Theme.hairline.opacity(0.7), lineWidth: 1)
            )
            .shadow(color: Theme.shadow.opacity(0.14), radius: elevation, y: elevation / 2)
    }
}

extension View {
    func paperSurface(
        radius: CGFloat = Metrics.panelRadius,
        elevation: CGFloat = 6
    ) -> some View {
        modifier(PaperSurface(radius: radius, elevation: elevation))
    }

    /// Fondo cálido a pantalla completa.
    func cozyBackground() -> some View {
        background(Theme.backgroundGradient.ignoresSafeArea())
    }
}

// MARK: - Apariencia de las barras del sistema

enum Appearance {
    /// Alinea la barra de navegación y la de pestañas con la paleta.
    static func configure() {
        let surface = UIColor { traits in
            UIColor(hex: traits.userInterfaceStyle == .dark ? 0x241D17 : 0xFFFBF5)
        }
        let title = UIColor { traits in
            UIColor(hex: traits.userInterfaceStyle == .dark ? 0xF2E9DC : 0x3B322C)
        }
        let rounded: (CGFloat, UIFont.Weight) -> UIFont = { size, weight in
            let base = UIFont.systemFont(ofSize: size, weight: weight)
            guard let descriptor = base.fontDescriptor.withDesign(.rounded) else { return base }
            return UIFont(descriptor: descriptor, size: size)
        }

        let navBar = UINavigationBarAppearance()
        navBar.configureWithOpaqueBackground()
        navBar.backgroundColor = surface
        navBar.shadowColor = .clear
        navBar.titleTextAttributes = [
            .foregroundColor: title,
            .font: rounded(17, .semibold),
        ]
        navBar.largeTitleTextAttributes = [
            .foregroundColor: title,
            .font: rounded(34, .bold),
        ]
        UINavigationBar.appearance().standardAppearance = navBar
        UINavigationBar.appearance().scrollEdgeAppearance = navBar
        UINavigationBar.appearance().compactAppearance = navBar

        let tabBar = UITabBarAppearance()
        tabBar.configureWithOpaqueBackground()
        tabBar.backgroundColor = surface
        tabBar.shadowColor = UIColor { traits in
            UIColor(hex: traits.userInterfaceStyle == .dark ? 0x3D342A : 0xDCCDB6)
        }
        UITabBar.appearance().standardAppearance = tabBar
        UITabBar.appearance().scrollEdgeAppearance = tabBar
    }
}
