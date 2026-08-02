import SwiftUI
import UIKit

/// Contenedor principal. Tres pestañas navegables: revisar (mazo), lote por borrar y filtros.
struct RootView: View {
    @Environment(SwipeViewModel.self) private var model
    @State private var didBootstrap = false
    /// Solo en arranque en frío: `RootView` se construye una vez por proceso,
    /// así que volver desde segundo plano no la repite.
    @State private var showsSplash = true

    @AppStorage(AppearanceMode.storageKey) private var appearanceRaw = AppearanceMode.system.rawValue

    private var appearance: AppearanceMode {
        AppearanceMode(rawValue: appearanceRaw) ?? .system
    }

    private var tab: Binding<SwipeViewModel.AppTab> {
        Binding(
            get: { model.selectedTab },
            set: { model.selectedTab = $0 }
        )
    }

    var body: some View {
        ZStack {
            content

            if showsSplash {
                SplashView {
                    withAnimation(.easeInOut(duration: 0.45)) { showsSplash = false }
                }
                .transition(.opacity)
                .zIndex(1)
            }
        }
    }

    /// El contenido real. Se construye siempre, también mientras la presentación
    /// está encima: así la fototeca se carga durante la animación, no después.
    private var content: some View {
        Group {
            if model.phase == .needsPermission {
                PermissionView()
            } else {
                TabView(selection: tab) {
                    ExploreView()
                        .tabItem {
                            Label("Explore", systemImage: "square.grid.2x2.fill")
                        }
                        .tag(SwipeViewModel.AppTab.explore)

                    ReviewTabView()
                        .tabItem {
                            Label("Review", systemImage: "rectangle.stack.fill")
                        }
                        .tag(SwipeViewModel.AppTab.review)

                    TrashTrayView()
                        .tabItem {
                            Label("To delete", systemImage: "tray.full.fill")
                        }
                        .badge(model.pendingCount)
                        .tag(SwipeViewModel.AppTab.tray)

                    FilterView()
                        .tabItem {
                            Label("Settings", systemImage: "slider.horizontal.3")
                        }
                        .tag(SwipeViewModel.AppTab.filters)
                }
                .tint(Theme.discard)
            }
        }
        .fontDesign(.rounded)
        .tint(Theme.discard)
        .preferredColorScheme(appearance.colorScheme)
        // Red de seguridad: por encima de este tamaño el mazo y la rejilla dejan de
        // caber en pantalla. Cubre todo el rango normal y los dos primeros de
        // accesibilidad, que es lo que usa la inmensa mayoría de la gente.
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
        .task {
            guard !didBootstrap else { return }
            didBootstrap = true
            await model.bootstrap()
        }
        .alert(
            "Something went wrong",
            isPresented: Binding(
                get: { model.errorMessage != nil },
                set: { if !$0 { model.errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "")
        }
    }
}

// MARK: - Pestaña de revisión (el mazo)

struct ReviewTabView: View {
    @Environment(SwipeViewModel.self) private var model

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.backgroundGradient.ignoresSafeArea()

                switch model.phase {
                case .needsPermission:
                    PermissionView()

                case .loading:
                    VStack(spacing: 18) {
                        ProgressView()
                            .controlSize(.large)
                            .tint(Theme.discard)
                        Text("Finding photos…")
                            .font(.cozy(15, .medium))
                            .foregroundStyle(Theme.textSecondary)
                    }

                case .empty:
                    EmptyStateView()

                case .ready, .finished:
                    // La cuadrícula manda: es donde se elige el punto de entrada.
                    // El mazo y el resumen son el segundo paso.
                    if model.reviewMode == .grid {
                        GalleryGridView()
                    } else if model.phase == .finished {
                        SummaryView()
                    } else {
                        SwipeDeckView()
                    }
                }
            }
            .navigationTitle(model.filter.source.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    // En el mazo, atrás lleva a la cuadrícula de la sección.
                    // En la cuadrícula, a elegir otra sección.
                    if model.reviewMode == .deck {
                        Button {
                            model.showGrid()
                        } label: {
                            Label("Gallery", systemImage: "square.grid.3x3")
                        }
                        .tint(Theme.discard)
                    } else {
                        Button {
                            model.selectedTab = .explore
                        } label: {
                            Label("Explore", systemImage: "square.grid.2x2")
                        }
                        .tint(Theme.discard)
                    }
                }
            }
        }
    }
}

// MARK: - Piezas compartidas

/// Ilustración circular grande, para los estados vacíos y de resumen.
struct CozyEmblem: View {
    let systemImage: String
    let tint: Color

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 46, weight: .medium, design: .rounded))
            .foregroundStyle(tint)
            .frame(width: 104, height: 104)
            .background(
                Circle()
                    .fill(tint.opacity(0.13))
                    .overlay(Circle().stroke(tint.opacity(0.22), lineWidth: 1.5))
            )
    }
}

/// Botón principal cálido, ancho completo.
struct CozyButtonLabel: View {
    let title: String
    let icon: String?
    var tint: Color = Theme.discard

    var body: some View {
        HStack(spacing: 8) {
            if let icon {
                Image(systemName: icon)
            }
            Text(title)
        }
        .font(.cozy(16, .semibold))
        .foregroundStyle(Theme.textOnAccent)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 15)
        .background(tint, in: RoundedRectangle(cornerRadius: Metrics.controlRadius, style: .continuous))
        .shadow(color: tint.opacity(0.3), radius: 8, y: 4)
    }
}

/// Botón secundario, contorno sobre papel.
struct CozySecondaryLabel: View {
    let title: String
    let icon: String?
    var tint: Color = Theme.textPrimary

    var body: some View {
        HStack(spacing: 8) {
            if let icon {
                Image(systemName: icon)
            }
            Text(title)
        }
        .font(.cozy(15, .semibold))
        .foregroundStyle(tint)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 13)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Metrics.controlRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Metrics.controlRadius, style: .continuous)
                .stroke(Theme.hairline, lineWidth: 1)
        )
    }
}

// MARK: - Sin resultados

struct EmptyStateView: View {
    @Environment(SwipeViewModel.self) private var model

    var body: some View {
        VStack(spacing: 20) {
            CozyEmblem(systemImage: "checkmark.seal.fill", tint: Theme.keep)

            Text("Nothing to review")
                .font(.handwritten(38, relativeTo: .title2))
                .foregroundStyle(Theme.textPrimary)

            Text("“\(model.filter.source.title)” has no photos matching your current settings.")
                .font(.cozy(14))
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)

            VStack(spacing: 10) {
                Button {
                    model.selectedTab = .explore
                } label: {
                    CozyButtonLabel(
                        title: String(localized: "Pick another section"),
                        icon: "square.grid.2x2.fill"
                    )
                }
                .buttonStyle(BouncyButtonStyle())

                Button {
                    model.selectedTab = .filters
                } label: {
                    CozySecondaryLabel(
                        title: String(localized: "Change settings"),
                        icon: "slider.horizontal.3"
                    )
                }
                .buttonStyle(BouncyButtonStyle())
            }
            .padding(.top, 6)
        }
        .padding(36)
    }
}

// MARK: - Resumen final

struct SummaryView: View {
    @Environment(SwipeViewModel.self) private var model

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                CozyEmblem(systemImage: "sparkles", tint: Theme.pending)
                    .padding(.top, 8)

                VStack(spacing: 5) {
                    Text("All done")
                        .font(.handwritten(42, relativeTo: .title))
                        .foregroundStyle(Theme.textPrimary)
                    Text("Nice work — your gallery is lighter now.")
                        .font(.cozy(13))
                        .foregroundStyle(Theme.textSecondary)
                }

                VStack(spacing: 0) {
                    summaryRow(icon: "heart.fill", tint: Theme.keep,
                               label: String(localized: "Kept"),
                               value: "\(model.keptCount)")
                    Divider().overlay(Theme.hairline)
                    summaryRow(icon: "trash.fill", tint: Theme.discard,
                               label: String(localized: "Discarded"),
                               value: "\(model.deletedCount)")
                    Divider().overlay(Theme.hairline)
                    summaryRow(icon: "internaldrive.fill", tint: Theme.info,
                               label: String(localized: "Space freed"),
                               value: model.formattedBytesFreed)
                }
                .padding(.vertical, 4)
                .paperSurface()

                if model.pendingCount > 0 {
                    VStack(spacing: 10) {
                        Text("\(model.pendingCount) photos waiting in the tray · \(model.formattedPendingBytes)")
                            .font(.cozy(13, .medium))
                            .foregroundStyle(Theme.textSecondary)
                            .multilineTextAlignment(.center)

                        Button {
                            model.selectedTab = .tray
                        } label: {
                            CozyButtonLabel(
                                title: String(localized: "Review and delete"),
                                icon: "tray.full.fill"
                            )
                        }
                        .buttonStyle(BouncyButtonStyle())
                    }
                }

                VStack(spacing: 10) {
                    Button {
                        model.showGrid()
                    } label: {
                        CozySecondaryLabel(
                            title: String(localized: "Back to the gallery"),
                            icon: "square.grid.3x3.fill"
                        )
                    }
                    .buttonStyle(BouncyButtonStyle())

                    Button {
                        model.selectedTab = .explore
                    } label: {
                        CozySecondaryLabel(
                            title: String(localized: "Pick another section"),
                            icon: "square.grid.2x2.fill"
                        )
                    }
                    .buttonStyle(BouncyButtonStyle())

                    Button {
                        Task { await model.startNewSession() }
                    } label: {
                        CozySecondaryLabel(
                            title: String(localized: "Go through this section again"),
                            icon: "arrow.clockwise",
                            tint: Theme.textSecondary
                        )
                    }
                    .buttonStyle(BouncyButtonStyle())
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 28)
        }
    }

    private func summaryRow(icon: String, tint: Color, label: String, value: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.fixed(13))
                .foregroundStyle(tint)
                .frame(width: 30, height: 30)
                .background(tint.opacity(0.14), in: Circle())

            Text(label)
                .font(.cozy(14, .medium))
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(2)
                .minimumScaleFactor(0.75)

            Spacer(minLength: 8)

            Text(value)
                .font(.cozy(16, .bold))
                .monospacedDigit()
                .foregroundStyle(Theme.textPrimary)
                .contentTransition(.numericText())
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

// MARK: - Permisos

struct PermissionView: View {
    @Environment(SwipeViewModel.self) private var model

    var body: some View {
        ZStack {
            Theme.backgroundGradient.ignoresSafeArea()

            VStack(spacing: 20) {
                CozyEmblem(systemImage: "lock.open.fill", tint: Theme.pending)

                Text("PhotoNook needs your photos")
                    .font(.handwritten(38, relativeTo: .title2))
                    .foregroundStyle(Theme.textPrimary)
                    .multilineTextAlignment(.center)

                Text("Without read and write access it can't show you anything or delete what you discard. You can grant it in Settings.")
                    .font(.cozy(14))
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)

                VStack(spacing: 10) {
                    Button {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    } label: {
                        CozyButtonLabel(title: String(localized: "Open Settings"), icon: "gear")
                    }
                    .buttonStyle(BouncyButtonStyle())

                    Button {
                        Task { await model.bootstrap() }
                    } label: {
                        CozySecondaryLabel(
                            title: String(localized: "Check again"),
                            icon: "arrow.clockwise"
                        )
                    }
                    .buttonStyle(BouncyButtonStyle())
                }
                .padding(.top, 6)
            }
            .padding(32)
        }
    }
}
