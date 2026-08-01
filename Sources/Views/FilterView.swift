import SwiftUI

/// Ajustes de la sesión. La elección del origen vive en Explorar;
/// aquí solo se afina lo que se aplica encima.
struct FilterView: View {
    @Environment(SwipeViewModel.self) private var model

    @State private var draft = FilterOptions()
    @State private var mode: SwipeViewModel.DeletionMode = .endOfSession
    @State private var chunk: Int = 25
    @State private var showResetWarning = false

    @AppStorage(AppearanceMode.storageKey) private var appearanceRaw = AppearanceMode.system.rawValue

    private var appearance: Binding<AppearanceMode> {
        Binding(
            get: { AppearanceMode(rawValue: appearanceRaw) ?? .system },
            set: { appearanceRaw = $0.rawValue }
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Button {
                        model.selectedTab = .explore
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: draft.source.systemImage)
                                .font(.fixed(13))
                                .foregroundStyle(Theme.textOnAccent)
                                .frame(width: 32, height: 32)
                                .background(Circle().fill(Theme.discard))

                            VStack(alignment: .leading, spacing: 2) {
                                Text(draft.source.title)
                                    .font(.cozy(16, .semibold))
                                    .foregroundStyle(Theme.textPrimary)
                                Text("Tap to change section")
                                    .font(.cozy(11))
                                    .foregroundStyle(Theme.textSecondary)
                            }

                            Spacer()

                            Image(systemName: "chevron.right")
                                .font(.cozy(12, .semibold))
                                .foregroundStyle(Theme.textSecondary)
                        }
                        .padding(.vertical, 4)
                    }
                } header: {
                    Text("Active section")
                }

                Section {
                    Picker("Age", selection: $draft.dateRange) {
                        ForEach(DateRange.allCases) { range in
                            Text(range.label).tag(range)
                        }
                    }
                    .disabled(draft.source.carriesOwnDateRange)

                    Picker("Order", selection: $draft.sortOrder) {
                        ForEach(SortOrder.allCases) { order in
                            Text(order.label).tag(order)
                        }
                    }
                } header: {
                    Text("Date and order")
                } footer: {
                    if draft.source.carriesOwnDateRange {
                        Text("This section is already limited by date, so the age filter doesn't apply.")
                    }
                }

                Section {
                    Toggle("Include videos", isOn: $draft.includeVideos)
                    Toggle("Protect favorites", isOn: $draft.skipFavorites)
                        .disabled(draft.source.isFavoritesAlbum)
                } footer: {
                    Text("Protected favorites never show up in the deck.")
                }

                Section {
                    Picker("Appearance", selection: appearance) {
                        ForEach(AppearanceMode.allCases) { option in
                            // En un picker segmentado conviene texto plano:
                            // con `Label` iOS muestra solo el icono.
                            Text(option.label).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                } header: {
                    Text("Appearance")
                } footer: {
                    Text("“System” follows your iPhone's Display & Brightness setting. Changes apply instantly and are remembered.")
                }

                Section {
                    Picker("Delete", selection: $mode) {
                        ForEach(SwipeViewModel.DeletionMode.allCases) { option in
                            Text(option.label).tag(option)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()

                    if mode == .chunked {
                        Stepper(value: $chunk, in: 5...100, step: 5) {
                            HStack {
                                Text("Batch size")
                                Spacer()
                                Text("\(chunk)")
                                    .font(.cozy(15, .bold))
                                    .foregroundStyle(Theme.discard)
                                    .monospacedDigit()
                                    .contentTransition(.numericText())
                            }
                        }
                    }
                } header: {
                    Text("Deletion mode")
                } footer: {
                    Text(mode.explanation + "\n\n"
                         + String(localized: "iOS shows a confirmation alert for every delete operation and there's no way to turn it off. Grouping photos into batches is the only way to reduce them."))
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.backgroundGradient.ignoresSafeArea())
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 8) {
                    if hasChanges {
                        Text("Applying reloads the deck and resets the counters.")
                            .font(.cozy(11))
                            .foregroundStyle(Theme.textSecondary)
                    }
                    Button {
                        apply()
                    } label: {
                        CozyButtonLabel(
                            title: hasChanges
                                ? String(localized: "Apply and review")
                                : String(localized: "Go to review"),
                            icon: hasChanges ? "checkmark" : "rectangle.stack.fill"
                        )
                    }
                    .buttonStyle(BouncyButtonStyle())
                }
                .padding(.horizontal, Metrics.gutter)
                .padding(.top, 12)
                .padding(.bottom, 10)
                .background(
                    Theme.surface
                        .overlay(alignment: .top) {
                            Rectangle().fill(Theme.hairline).frame(height: 1)
                        }
                        .ignoresSafeArea(edges: .bottom)
                )
            }
            .onAppear {
                draft = model.filter
                mode = model.deletionMode
                chunk = model.chunkSize
            }
            .confirmationDialog(
                "You have \(model.pendingCount) photos still in the tray",
                isPresented: $showResetWarning,
                titleVisibility: .visible
            ) {
                Button("Go to the tray and delete them first") {
                    model.selectedTab = .tray
                }
                Button("Discard the tray and reload", role: .destructive) {
                    performApply(reload: true)
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Reloading now empties the tray. Those photos stay in your gallery — nothing gets deleted.")
            }
        }
    }

    /// ¿Los ajustes en pantalla difieren de los aplicados?
    private var hasChanges: Bool {
        draft != model.filter
    }

    private func apply() {
        let changed = draft != model.filter
        let shouldReload = changed || model.phase == .finished || model.phase == .empty

        // Recargar vacía el lote pendiente sin borrar nada. Avisa antes de perderlo.
        if shouldReload && model.pendingCount > 0 {
            showResetWarning = true
            return
        }
        performApply(reload: shouldReload)
    }

    private func performApply(reload: Bool) {
        model.filter = draft
        model.deletionMode = mode
        model.chunkSize = chunk
        model.selectedTab = .review

        if reload {
            Task { await model.loadAssets() }
        }
    }
}
