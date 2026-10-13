import SwiftUI
import CoreLocation

/// Points to the nearest place of the chosen kind using only GPS and the compass:
/// no map tiles and no connection. It works from live results when online and from
/// saved places when offline. The direction is a straight line, not a route.
struct CompassView: View {
    let kind: NearbyKind

    @EnvironmentObject private var nearby: NearbyStore
    @StateObject private var compass = CompassService()
    @State private var chosenID: String?

    /// Best position we have: live compass updates, else the last one-off fix.
    private var here: CLLocation? { compass.location ?? nearby.fix }

    private var result: NearbyStore.Result { nearby.result(for: kind) }

    /// Candidates sorted by distance from where the person is right now.
    private var candidates: [NearbyPlace] {
        guard let here else { return result.places }
        return result.places.sorted { $0.distance(from: here) < $1.distance(from: here) }
    }

    private var target: NearbyPlace? {
        if let chosenID, let chosen = candidates.first(where: { $0.id == chosenID }) { return chosen }
        return candidates.first
    }

    var body: some View {
        VStack(spacing: 18) {
            if let target, let here {
                guide(to: target, from: here)
                others(except: target, from: here)
            } else {
                NoticeCard(
                    systemImage: "location.north.line.fill",
                    message: "No \(kind.title.lowercased()) is saved near you, so there is nothing to point to. Open the Map view while you have a connection and Flare will save nearby places for later.",
                    tint: FlareColor.link) { EmptyView() }
            }
        }
        .onAppear { compass.start() }
        .onDisappear { compass.stop() }
        .onChange(of: kind) { _, _ in chosenID = nil }
    }

    // MARK: Guide

    private func guide(to place: NearbyPlace, from here: CLLocation) -> some View {
        let distance = place.distance(from: here)
        let bearing = Geo.bearing(from: here.coordinate, to: place.coordinate)
        let arrived = distance < 40
        let accuracyLow = here.horizontalAccuracy < 0 || here.horizontalAccuracy > 100

        return VStack(spacing: 14) {
            ZStack {
                Circle().fill(FlareColor.cardFill)
                Circle().stroke(FlareColor.cardBorder, lineWidth: 1.5)

                if let heading = compass.heading {
                    // "N" stays pointing at north as the phone turns.
                    ZStack {
                        Text("N")
                            .font(.archivo(.extraBold, size: 16, relativeTo: .headline))
                            .foregroundStyle(FlareColor.secondaryText)
                            .offset(y: -108)
                    }
                    .frame(width: 250, height: 250)
                    .rotationEffect(.degrees(-heading))

                    if arrived {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 84, weight: .bold))
                            .foregroundStyle(FlareColor.ready)
                    } else {
                        Image(systemName: "location.north.fill")
                            .font(.system(size: 92, weight: .bold))
                            .foregroundStyle(FlareGradient.flare)
                            .rotationEffect(.degrees(Geo.normalized(bearing - heading)))
                            .animation(.easeOut(duration: 0.2), value: heading)
                    }
                } else {
                    Image(systemName: "safari")
                        .font(.system(size: 64, weight: .regular))
                        .foregroundStyle(FlareColor.secondaryText)
                }
            }
            .frame(width: 250, height: 250)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(arrived
                ? "You are at \(place.name)"
                : "\(place.name) is \(Geo.distanceText(distance)) away, to the \(Geo.cardinal(bearing))")

            VStack(spacing: 4) {
                Text(arrived ? "You're here" : Geo.distanceText(distance))
                    .font(.flareDisplay)
                    .foregroundStyle(FlareColor.text)
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                Text(place.name)
                    .font(.flareBodyLarge)
                    .foregroundStyle(FlareColor.text)
                    .multilineTextAlignment(.center)
                if !arrived {
                    Text("Head \(Geo.cardinal(bearing))")
                        .font(.flareSecondary)
                        .foregroundStyle(FlareColor.secondaryText)
                }
                if result.source == .saved {
                    Text("Saved \(place.savedAt.formatted(date: .abbreviated, time: .omitted))")
                        .font(.flareCaption)
                        .foregroundStyle(FlareColor.warning)
                }
            }

            VStack(spacing: 6) {
                if !compass.headingAvailable {
                    caption("This device has no compass, so Flare can only tell you the direction in words.")
                } else if compass.heading == nil {
                    caption("Waiting for the compass. Hold the phone away from metal and magnets.")
                } else {
                    caption("If the arrow seems wrong, move the phone in a slow figure 8.")
                }
                if accuracyLow {
                    caption("Your location is approximate right now, so distance and direction may be off.")
                }
                caption("This is a straight line, not a route. Roads, water or walls may be in the way. Use Directions on the Map view for a route when you have a signal.")
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    private func caption(_ text: String) -> some View {
        Text(text)
            .font(.flareCaption)
            .foregroundStyle(FlareColor.secondaryText)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: Other places

    @ViewBuilder
    private func others(except current: NearbyPlace, from here: CLLocation) -> some View {
        let rest = candidates.filter { $0.id != current.id }.prefix(4)
        if !rest.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("Point to a different one")
                    .font(.flareSection)
                    .foregroundStyle(FlareColor.text)
                ForEach(Array(rest)) { place in
                    Button {
                        chosenID = place.id
                    } label: {
                        HStack {
                            Text(place.name)
                                .font(.flareBody)
                                .foregroundStyle(FlareColor.text)
                                .multilineTextAlignment(.leading)
                            Spacer(minLength: 8)
                            Text(Geo.distanceText(place.distance(from: here)))
                                .font(.flareBody)
                                .foregroundStyle(FlareColor.secondaryText)
                        }
                        .padding(.horizontal, 14)
                        .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
                        .cardSurface(cornerRadius: 14)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}
