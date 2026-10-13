import Foundation
import AppIntents

/// Whether Emergency Mode is showing. A single shared instance, so the Shortcuts / Siri /
/// Action Button action can turn it on even when the app is launched by it.
@MainActor
final class EmergencyModeController: ObservableObject {
    static let shared = EmergencyModeController()
    @Published var isActive = false
    private init() {}
}

/// "Start Emergency Mode": shows up in the Shortcuts app, Siri, Spotlight and the Action Button.
struct StartEmergencyModeIntent: AppIntent {
    static let title: LocalizedStringResource = "Start Emergency Mode"
    static let description = IntentDescription("Opens Flare's Emergency Mode: emergency number, your coordinates and battery guard.")
    static let openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        EmergencyModeController.shared.isActive = true
        return .result()
    }
}

struct FlareShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StartEmergencyModeIntent(),
            phrases: [
                "Start Emergency Mode in \(.applicationName)",
                "Open \(.applicationName) Emergency Mode"
            ],
            shortTitle: "Emergency Mode",
            systemImageName: "bolt.shield.fill")
    }
}
