import SwiftUI

@main
struct FlareApp: App {
    @UIApplicationDelegateAdaptor(FlareAppDelegate.self) private var appDelegate

    init() {
        // Must run before any text is drawn.
        FontRegistrar.registerBundledFonts()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}
