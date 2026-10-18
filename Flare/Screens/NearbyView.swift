import SwiftUI
import MapKit
import UIKit

/// The Map tab: nearby hospitals, police stations, fire stations and pharmacies.
/// Online it searches Apple Maps live. Offline it shows places saved from earlier searches,
/// and the compass points to the nearest one with no map tiles and no signal.
struct NearbyView: View {
    @EnvironmentObject private var store: EmergencyStore
    @EnvironmentObject private var nearby: NearbyStore
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase

    /// While the Map tab is on screen, Flare asks for a fresh GPS position this often.
    private static let followInterval: Duration = .seconds(60)

    enum Mode: String { case map, compass }

    @State private var mode: Mode = .map
    @State private var position: MapCameraPosition = .userLocation(fallback: .automatic)
    @State private var showAllPlaces = false
    @State private var confirmClear = false

    private var kind: NearbyKind { nearby.selectedKind }
    private var result: NearbyStore.Result { nearby.result(for: kind) }
    private var places: [NearbyPlace] { result.places }
    private var visiblePlaces: [NearbyPlace] { showAllPlaces ? places : Array(places.prefix(6)) }

    /// Changes whenever the set of shown places changes, to re-frame the map.
    private var placesKey: String {
        kind.rawValue + places.prefix(4).map(\.id).joined(separator: ",")
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Nearby")
                    .font(.flareTitle)
                    .foregroundStyle(FlareColor.text)
                    .accessibilityAddTraits(.isHeader)

                kindChips

                Picker("View", selection: $mode) {
                    Text("Map").tag(Mode.map)
                    Text("Compass").tag(Mode.compass)
                }
                .pickerStyle(.segmented)

                if store.location.isDenied && nearby.fix == nil {
                    deniedNotice
                } else if nearby.fix == nil {
                    findingLocation
                } else {
                    statusBanner
                    switch mode {
                    case .map: mapContent
                    case .compass: CompassView(kind: kind)
                    }
                }

                disclaimer
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .onAppear {
            if nearby.fix == nil, let fix = store.location.latestFix { nearby.updateFix(fix) }
            nearby.activate()
            frameMap()
        }
        // A fresh position when the tab opens, then once a minute while it stays open
        // and Flare is in the foreground. Stops by itself when the tab or app is left.
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            while !Task.isCancelled {
                store.location.requestFix()
                try? await Task.sleep(for: Self.followInterval)
            }
        }
        .onChange(of: placesKey) { _, _ in frameMap() }
        .onChange(of: nearby.selectedKind) { _, _ in
            nearby.selectedPlaceID = nil
            showAllPlaces = false
        }
        .confirmationDialog("Delete the places saved on this phone?",
                            isPresented: $confirmClear, titleVisibility: .visible) {
            Button("Delete saved places", role: .destructive) { nearby.clearSavedPlaces() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Flare will save new ones the next time you search while online.")
        }
    }

    // MARK: Kind chips

    private var kindChips: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 10) {
                ForEach(NearbyKind.allCases) { option in
                    let selected = option == kind
                    Button {
                        nearby.selectedKind = option
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: option.systemImage)
                                .font(.system(size: 15, weight: .bold))
                            Text(option.title)
                                .font(.flareBody)
                        }
                        .foregroundStyle(selected ? FlareColor.text : FlareColor.secondaryText)
                        .padding(.horizontal, 14)
                        .frame(minHeight: 44)
                        .background(
                            Capsule().fill(selected ? option.tint.opacity(0.25) : FlareColor.cardFill)
                        )
                        .overlay(
                            Capsule().stroke(selected ? option.tint : FlareColor.cardBorder,
                                             lineWidth: selected ? 1.5 : 1)
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(option.title)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
        }
        .scrollIndicators(.hidden)
    }

    // MARK: Status

    private var deniedNotice: some View {
        NoticeCard(
            systemImage: "location.slash.fill",
            message: "Location is off, so Flare can't find places near you. Turn location on in Settings.") {
            LinkButton(title: "Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
            }
        }
    }

    private var findingLocation: some View {
        VStack(spacing: 12) {
            ProgressView().tint(FlareColor.link)
            Text("Finding where you are\u{2026}")
                .font(.flareBody)
                .foregroundStyle(FlareColor.secondaryText)
        }
        .frame(maxWidth: .infinity, minHeight: 160)
    }

    @ViewBuilder
    private var statusBanner: some View {
        if nearby.searchFailed {
            NoticeCard(
                systemImage: "wifi.slash",
                message: savedMessage) {
                HStack(spacing: 20) {
                    LinkButton(title: "Try again") { searchAgain() }
                    if mode == .map {
                        LinkButton(title: "Open compass") { mode = .compass }
                    }
                }
            }
        } else if nearby.isSearching && places.isEmpty {
            HStack(spacing: 10) {
                ProgressView().tint(FlareColor.link)
                Text("Searching Apple Maps\u{2026}")
                    .font(.flareSecondary)
                    .foregroundStyle(FlareColor.secondaryText)
            }
        } else if case .live(let date) = result.source {
            HStack(spacing: 8) {
                Circle().fill(FlareColor.offlineDot).frame(width: 8, height: 8)
                Text("Live from Apple Maps \u{00B7} updated \(date, style: .relative) ago")
                    .font(.flareCaption)
                    .foregroundStyle(FlareColor.secondaryText)
            }
        } else if !places.isEmpty {
            NoticeCard(
                systemImage: "tray.full.fill",
                message: "Apple Maps found no \(kind.title.lowercased()) nearby just now, so these are places saved from earlier searches.",
                tint: FlareColor.link) { EmptyView() }
        }
    }

    private var savedMessage: String {
        if nearby.savedCount == 0 {
            return "Can't reach Apple Maps, and no places are saved on this phone yet. Open Nearby while you have a connection so Flare can save places for later."
        }
        return "Can't reach Apple Maps right now. Showing places saved from earlier searches within \(Geo.distanceText(NearbyStore.savedRadius)). The compass works without a signal."
    }

    // MARK: Map

    @ViewBuilder
    private var mapContent: some View {
        Map(position: $position, selection: $nearby.selectedPlaceID) {
            UserAnnotation()
            ForEach(places) { place in
                Marker(place.name, systemImage: kind.systemImage, coordinate: place.coordinate)
                    .tint(kind.tint)
                    .tag(place.id)
            }
        }
        .mapStyle(.standard(emphasis: .muted, pointsOfInterest: .excludingAll))
        .mapControls {
            MapUserLocationButton()
            MapCompass()
        }
        .frame(height: 300)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(FlareColor.cardBorder, lineWidth: 1)
        )
        .accessibilityHidden(true)   // the list below carries the same information

        placeList
    }

    @ViewBuilder
    private var placeList: some View {
        if places.isEmpty {
            if nearby.isSearching {
                EmptyView()
            } else {
                emptyState
            }
        } else {
            VStack(alignment: .leading, spacing: 10) {
                Text(kind.listTitle)
                    .font(.flareSection)
                    .foregroundStyle(FlareColor.text)

                ForEach(visiblePlaces) { place in
                    PlaceCard(
                        place: place,
                        from: nearby.fix,
                        showsSavedDate: result.source == .saved,
                        isSelected: nearby.selectedPlaceID == place.id,
                        onSelect: { select(place) })
                }

                if places.count > visiblePlaces.count {
                    LinkButton(title: "Show all \(places.count)") { showAllPlaces = true }
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }

    private var emptyState: some View {
        NoticeCard(
            systemImage: "magnifyingglass",
            message: nearby.searchFailed
                ? "No saved \(kind.title.lowercased()) near here. Flare will not guess. For an emergency, use the numbers on Home."
                : "Apple Maps found no \(kind.title.lowercased()) within about 60 km, and none are saved near here. For an emergency, use the numbers on Home.") {
            LinkButton(title: "Search again") { searchAgain() }
        }
    }

    // MARK: Disclaimer

    private var disclaimer: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Places come from Apple Maps while you are online, or from earlier searches saved on this phone. Flare has not verified them, and a hospital listed here may not have an emergency department. A place's phone number is not an emergency number: in an emergency use the numbers on Home. Searching sends your approximate location to Apple Maps.")
                .font(.flareCaption)
                .foregroundStyle(FlareColor.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            if nearby.savedCount > 0 {
                HStack {
                    Text("\(nearby.savedCount) places saved on this phone")
                        .font(.flareCaption)
                        .foregroundStyle(FlareColor.secondaryText)
                    Spacer()
                    LinkButton(title: "Delete saved places") { confirmClear = true }
                }
            }
        }
    }

    // MARK: Map framing

    private func select(_ place: NearbyPlace) {
        nearby.selectedPlaceID = place.id
        let region = MKCoordinateRegion(
            center: place.coordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02))
        withAnimation { position = .region(region) }
    }

    /// Asks for a new GPS position and searches around it (or around the last one if GPS can't answer).
    private func searchAgain() {
        let canLocate = store.location.isAuthorized
        nearby.refresh(awaitingNewFix: canLocate)
        store.location.requestFix()
    }

    /// Fits the camera around the person and the nearest few places.
    private func frameMap() {
        guard let fix = nearby.fix, !places.isEmpty else { return }
        let points = [fix.coordinate] + places.prefix(3).map(\.coordinate)
        let lats = points.map(\.latitude)
        let lons = points.map(\.longitude)
        guard let minLat = lats.min(), let maxLat = lats.max(),
              let minLon = lons.min(), let maxLon = lons.max() else { return }
        let center = CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2,
                                            longitude: (minLon + maxLon) / 2)
        let span = MKCoordinateSpan(
            latitudeDelta: max((maxLat - minLat) * 1.6, 0.012),
            longitudeDelta: max((maxLon - minLon) * 1.6, 0.012))
        position = .region(MKCoordinateRegion(center: center, span: span))
    }
}

// MARK: - One place

struct PlaceCard: View {
    let place: NearbyPlace
    let from: CLLocation?
    let showsSavedDate: Bool
    let isSelected: Bool
    let onSelect: () -> Void

    @Environment(\.openURL) private var openURL

    private var distanceText: String? {
        guard let from else { return nil }
        return Geo.distanceText(place.distance(from: from))
    }

    private var callURL: URL? {
        guard let phone = place.phone else { return nil }
        return Dialer.telURL(for: phone)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button(action: onSelect) {
                HStack(alignment: .top, spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(place.kind.tint.opacity(0.22))
                        Image(systemName: place.kind.systemImage)
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(place.kind.tint)
                    }
                    .frame(width: 44, height: 44)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(place.name)
                            .font(.flareBodyLarge)
                            .foregroundStyle(FlareColor.text)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                        if let address = place.address {
                            Text(address)
                                .font(.flareSecondary)
                                .foregroundStyle(FlareColor.secondaryText)
                                .multilineTextAlignment(.leading)
                        }
                        if showsSavedDate {
                            Text("Saved \(place.savedAt.formatted(date: .abbreviated, time: .omitted))")
                                .font(.flareCaption)
                                .foregroundStyle(FlareColor.warning)
                        }
                    }
                    Spacer(minLength: 8)
                    if let distanceText {
                        Text(distanceText)
                            .font(.archivo(.extraBold, size: 18, relativeTo: .headline))
                            .foregroundStyle(FlareColor.text)
                            .lineLimit(1)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            HStack(spacing: 10) {
                Button {
                    openDirections()
                } label: {
                    Label("Directions", systemImage: "arrow.triangle.turn.up.right.circle.fill")
                        .font(.flareBody)
                        .foregroundStyle(FlareColor.onFlare)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(Capsule().fill(FlareGradient.flare))
                }
                .buttonStyle(.plain)

                if let callURL {
                    Button {
                        openURL(callURL)
                    } label: {
                        Label("Call place", systemImage: "phone.fill")
                            .font(.flareBody)
                            .foregroundStyle(FlareColor.text)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .background(Capsule().fill(Color.white.opacity(0.14)))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Call \(place.name). This is not an emergency number.")
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous).fill(FlareColor.cardFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(isSelected ? FlareColor.accent : FlareColor.cardBorder,
                        lineWidth: isSelected ? 2 : 1)
        )
        .accessibilityElement(children: .contain)
    }

    private func openDirections() {
        let item = MKMapItem(placemark: MKPlacemark(coordinate: place.coordinate))
        item.name = place.name
        item.openInMaps(launchOptions: [
            MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDefault
        ])
    }
}
