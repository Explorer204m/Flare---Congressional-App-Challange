import SwiftUI

enum AppTab: String, CaseIterable, Identifiable {
    case home, map, numbers, medicalID

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: return "Home"
        case .map: return "Map"
        case .numbers: return "Numbers"
        case .medicalID: return "Medical ID"
        }
    }

    var systemImage: String {
        switch self {
        case .home: return "house.fill"
        case .map: return "map"
        case .numbers: return "list.bullet"
        case .medicalID: return "person.fill"
        }
    }
}

struct RootView: View {
    @StateObject private var store = EmergencyStore()
    @State private var tab: AppTab = .home
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            FlareBackground()
            content
        }
        .safeAreaInset(edge: .bottom) {
            FlareTabBar(selection: $tab)
        }
        .environmentObject(store)
        .preferredColorScheme(.dark)
        .task { await store.start() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { store.refreshLocation() }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch tab {
        case .home:
            HomeView(openMap: { tab = .map })
        case .map:
            ComingSoonView(
                title: "Nearby map",
                systemImage: "map",
                message: "An offline map with hospitals, police stations, fire stations and pharmacies is designed but not built yet.")
        case .numbers:
            ComingSoonView(
                title: "Numbers",
                systemImage: "list.bullet",
                message: "A searchable directory of emergency numbers by country is designed but not built yet. For now, tap \u{201C}All numbers and details\u{201D} on Home.")
        case .medicalID:
            ComingSoonView(
                title: "Medical ID",
                systemImage: "person.fill",
                message: "Medical ID with one-tap calls to emergency contacts is designed but not built yet.")
        }
    }
}

/// Floating navigation bar from the design: home is highlighted in flare orange.
struct FlareTabBar: View {
    @Binding var selection: AppTab

    var body: some View {
        HStack(spacing: 0) {
            ForEach(AppTab.allCases) { tab in
                Button {
                    selection = tab
                } label: {
                    ZStack {
                        if selection == tab {
                            Circle().fill(FlareGradient.flare)
                        }
                        Image(systemName: tab.systemImage)
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(selection == tab ? FlareColor.onFlare : FlareColor.secondaryText)
                    }
                    .frame(width: 52, height: 52)
                    .frame(maxWidth: .infinity, minHeight: 56)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tab.title)
                .accessibilityAddTraits(selection == tab ? .isSelected : [])
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule().fill(Color.black.opacity(0.35))
        )
        .overlay(Capsule().stroke(FlareColor.cardBorder, lineWidth: 1))
        .padding(.horizontal, 24)
        .padding(.bottom, 4)
    }
}
