import SwiftUI

struct HealthSyncDetailView: View {
    @StateObject private var syncState = HealthSyncState.shared
    @StateObject private var healthKitManager = HealthKitManager.shared
    @State private var statusMessage: String?
    @State private var isRequesting = false

    var body: some View {
        ZStack {
            FitTheme.backgroundGradient
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header

                    HealthSyncCard {
                        VStack(alignment: .leading, spacing: 14) {
                            Toggle(isOn: Binding(
                                get: { syncState.isEnabled },
                                set: { newValue in
                                    updateSyncPreference(newValue)
                                }
                            )) {
                                Text("Sync Apple Health workouts")
                                    .font(FitFont.body(size: 15, weight: .semibold))
                                    .foregroundColor(FitTheme.textPrimary)
                            }
                            .toggleStyle(SwitchToggleStyle(tint: FitTheme.accent))
                            .disabled(!healthKitManager.isHealthDataAvailable)

                            Button(action: {
                                Task { await requestAuthorization() }
                            }) {
                                Text(isRequesting ? "Connecting..." : "Connect Apple Health")
                                    .font(FitFont.body(size: 14, weight: .semibold))
                                    .foregroundColor(FitTheme.buttonText)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                    .background(FitTheme.primaryGradient)
                                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            }
                            .disabled(isRequesting || !healthKitManager.isHealthDataAvailable)

                            if let statusMessage {
                                Text(statusMessage)
                                    .font(FitFont.body(size: 12))
                                    .foregroundColor(FitTheme.textSecondary)
                            }

                            if let lastSync = syncState.lastSyncDate {
                                Text("Last sync: \(lastSync.formatted(date: .abbreviated, time: .shortened))")
                                    .font(FitFont.body(size: 12))
                                    .foregroundColor(FitTheme.textSecondary)
                            }

                            if !healthKitManager.isHealthDataAvailable {
                                Text("Apple Health isn’t available on this device.")
                                    .font(FitFont.body(size: 12))
                                    .foregroundColor(FitTheme.textSecondary)
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 32)
            }
        }
        .navigationTitle("Apple Health")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            healthKitManager.refreshAuthorizationStatus()
            if syncState.isEnabled {
                statusMessage = "Apple Health sync is on."
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Apple Health")
                .font(FitFont.heading(size: 28))
                .foregroundColor(FitTheme.textPrimary)
            Text("Automatically import workouts and keep your streak accurate.")
                .font(FitFont.body(size: 14))
                .foregroundColor(FitTheme.textSecondary)
        }
    }

    private func updateSyncPreference(_ enabled: Bool) {
        if enabled {
            Task { await requestAuthorization() }
        } else {
            syncState.isEnabled = false
            statusMessage = "Apple Health sync is off."
        }
    }

    @MainActor
    private func requestAuthorization() async {
        guard healthKitManager.isHealthDataAvailable else {
            statusMessage = "Apple Health isn’t available on this device."
            syncState.isEnabled = false
            return
        }

        isRequesting = true
        defer { isRequesting = false }

        let granted = await healthKitManager.requestAuthorization()
        syncState.isEnabled = granted
        statusMessage = granted
            ? "Apple Health connected."
            : "Permission not granted. You can enable it later in iOS Settings."

        if granted {
            _ = await healthKitManager.syncWorkoutsIfEnabled()
        }
    }
}

private struct HealthSyncCard<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            content
        }
        .padding(16)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(FitTheme.cardStroke, lineWidth: 1)
        )
    }
}
