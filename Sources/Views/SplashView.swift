import SwiftUI

/// Presentación breve al abrir la app.
///
/// No retrasa nada: el contenido real ya se está construyendo debajo y la carga
/// de la fototeca corre en paralelo, así que esta animación ocupa un tiempo que
/// de todos modos había que esperar. Se puede saltar tocando la pantalla.
struct SplashView: View {
    let onFinish: () -> Void

    /// Con "Reducir movimiento" activo no hay animación por letras: aparece entero.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Cuánto del nombre se ha "escrito", de 0 a 1.
    @State private var revealed: Double = 0
    @State private var showsTagline = false
    @State private var isLeaving = false

    var body: some View {
        ZStack {
            Theme.backgroundGradient.ignoresSafeArea()

            VStack(spacing: 14) {
                wordmark
                tagline
            }
            .padding(.horizontal, 32)
        }
        .contentShape(Rectangle())
        .onTapGesture { finish() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("PhotoNook. Clean and cozy.")
        .task { await run() }
    }

    // MARK: - Piezas

    /// El nombre revelado de izquierda a derecha, como si se escribiera.
    ///
    /// Una sola vista de texto, no una por letra: en una manuscrita los trazos
    /// se enlazan y sobresalen de la caja nominal de cada glifo, así que partirla
    /// recorta los rasgos (la P pierde el asta y parece una F) y además rompe el
    /// kerning. La máscara respeta la palabra entera.
    /// La palabra en sí.
    ///
    /// El espacio final del literal no es un descuido: `Text` mide su marco con
    /// los anchos de avance tipográficos, no con la tinta real. En Caveat la "k"
    /// remata en un bucle que se sale de su avance, y ese sobrante queda fuera
    /// del marco y se recorta al componer. Un espacio extra ensancha el marco lo
    /// justo para que el bucle quepa dentro.
    ///
    /// Va con `verbatim` porque es un nombre de marca: no se traduce.
    private var wordmarkText: some View {
        Text(verbatim: "PhotoNook ")
            // 60 en vez de 68: a 68 rozaba el ancho disponible en los iPhone
            // estrechos y entraba `minimumScaleFactor`.
            .font(.handwritten(60, relativeTo: .largeTitle))
            .foregroundStyle(Theme.textPrimary)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
    }

    /// Ya escrita, la máscara desaparece del todo en vez de volverse opaca.
    /// Cualquier máscara compone dentro del marco, así que la única forma de
    /// garantizar que no recorta nada es que deje de existir.
    @ViewBuilder
    private var wordmark: some View {
        if revealed >= 1 {
            wordmarkText
        } else {
            wordmarkText.mask(alignment: .leading) { revealMask }
        }
    }

    /// Borde suave en la punta del trazo: da sensación de pluma en movimiento
    /// en lugar de una cortina dura. Solo se usa mientras `revealed < 1`.
    private var revealMask: some View {
        let soft = min(1, max(0, revealed - 0.05))
        let hard = min(1, max(soft, revealed + 0.03))

        return LinearGradient(
            stops: [
                .init(color: .black, location: 0),
                .init(color: .black, location: soft),
                .init(color: .clear, location: hard),
                .init(color: .clear, location: 1),
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    /// Por encima de 1 para que la animación cruce el umbral con holgura y la
    /// máscara desaparezca de forma limpia al final del trazo.
    private let revealEnd: Double = 1.12

    private var tagline: some View {
        Text("Clean and cozy.")
            .font(.cozy(16, .medium))
            .foregroundStyle(Theme.textSecondary)
            .opacity(showsTagline ? 1 : 0)
            .offset(y: showsTagline ? 0 : 6)
    }

    // MARK: - Secuencia

    private func run() async {
        if reduceMotion {
            revealed = revealEnd
            showsTagline = true
            try? await Task.sleep(for: .seconds(0.9))
        } else {
            // Arranca algo más rápido y frena al final, como un trazo de verdad.
            withAnimation(.easeInOut(duration: 1.05)) { revealed = revealEnd }
            // El lema espera a que el trazo haya terminado del todo, no antes:
            // si se solapan, parece que la última letra aún se está escribiendo.
            try? await Task.sleep(for: .seconds(1.15))
            withAnimation(.easeOut(duration: 0.45)) { showsTagline = true }
            try? await Task.sleep(for: .seconds(0.9))
        }
        finish()
    }

    private func finish() {
        guard !isLeaving else { return }
        isLeaving = true
        onFinish()
    }
}
