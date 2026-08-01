import SwiftUI

@main
struct PhotoNookApp: App {
    @State private var model = SwipeViewModel()

    init() {
        // Alinea las barras del sistema (navegación y pestañas) con la paleta cálida.
        Appearance.configure()
        // Avisa por consola si la tipografía de marca no llegó al bundle.
        BrandFont.logAvailability()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
        }
    }
}
