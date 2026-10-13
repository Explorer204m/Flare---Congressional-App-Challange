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
    @StateObject private var medicalStore = MedicalIDStore()
    @StateObject private var nearby = NearbyStore()
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
        .environmentObject(medicalStore)
        .environmentObject(nearby)
        .preferredColorScheme(.dark)
        .task { await store.start() }
        .onChange(of: store.location.latestFix) { _, fix in
            if let fix { nearby.updateFix(fix) }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { store.refreshLocation() }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch tab {
        case .home:
            HomeView(openMap: { tab = .map }, openNumbers: { tab = .numbers })
        case .map:
            NearbyView()
        case .numbers:
            NumbersView()
        case .medicalID:
            MedicalIDView()
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
            ZStack {
                // Frosted glass: blurs whatever scrolls underneath, so text behind
                // the bar is not readable through it.
                Capsule().fill(.regularMaterial)
                // Mostly opaque navy tint: nothing behind the bar shows through, but the edge highlight still reads as glass.
                Capsule().fill(FlareColor.navyMid.opacity(0.94))
                // Soft light along the top edge, like the edge of a glass pane.
                Capsule().fill(
                    LinearGradient(colors: [Color.white.opacity(0.14), Color.white.opacity(0.0)],
                                   startPoint: .top, endPoint: .center))
            }
        )
        .overlay(
            Capsule().stroke(
                LinearGradient(colors: [Color.white.opacity(0.38), Color.white.opacity(0.08)],
                               startPoint: .top, endPoint: .bottom),
                lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.35), radius: 16, y: 6)
        .padding(.horizontal, 24)
        .padding(.bottom, 4)
    }
}
