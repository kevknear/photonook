import SwiftUI

@main
struct PhotoNookApp: App {
    @State private var model = SwipeViewModel()

    init() {
        // Alinea las barras del sistema (navegación y pestañas) con la paleta cálida.
        Appearance.configure()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
        }
    }
}
