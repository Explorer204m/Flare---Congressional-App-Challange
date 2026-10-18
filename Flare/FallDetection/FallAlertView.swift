import SwiftUI
import MessageUI
import CoreLocation

extension View {
    /// Puts the fall alert over this view. `enabled` is false for a screen that sits under
    /// another one that already shows it (for example under Emergency Mode).
    func fallAlertOverlay(enabled: Bool = true) -> some View {
        modifier(FallAlertOverlay(enabled: enabled))
    }
}

struct FallAlertOverlay: ViewModifier {
    let enabled: Bool
    @ObservedObject private var fall = FallDetectionController.shared

    func body(content: Content) -> some View {
        content.overlay {
            if enabled, let alert = fall.alert {
                FallAlertView(alert: alert)
                    .transition(.opacity)
            }
        }
    }
}

/// "Did you fall?" with a countdown. Big buttons: I'm OK, call, send my location.
struct FallAlertView: View {
    let alert: FallAlert

    @EnvironmentObject private var store: EmergencyStore
    @EnvironmentObject private var medical: MedicalIDStore
    @Environment(\.openURL) private var openURL
    @ObservedObject private var fall = FallDetectionController.shared
    @State private var showMessage = false
    @State private var chooser: ServiceSlot?
    @State private var showMedical = false

    private var here: CLLocation? { store.location.latestFix }

    private enum CallTarget {
        case dial(NumberGroup)
        case choose(ServiceSlot)
    }

    /// What the call button does: the all-emergencies number if there is one, otherwise the
    /// ambulance number. If the dataset lists several for that service, Flare doesn't guess:
    /// the button opens the list. Police and fire are only used when there is no ambulance number.
    private var callTarget: CallTarget? {
        let groups = store.plan.groups
        if let general = groups.first(where: { $0.coversEverything && $0.dialURL != nil }) {
            return .dial(general)
        }
        for category in [ServiceCategory.medical, .police, .fire] {
            let candidates = groups.filter { !$0.coversEverything && $0.categories.contains(category) }
            if candidates.isEmpty { continue }
            if candidates.count == 1, let only = candidates.first, only.dialURL != nil {
                return .dial(only)
            }
            return .choose(ServiceSlot(category: category, groups: candidates))
        }
        return nil
    }

    private var ringFraction: Double {
        Double(alert.secondsLeft) / Double(FallDetectionController.countdownSeconds)
    }

    var body: some View {
        ZStack {
            Color(hex: 0x14060A).ignoresSafeArea()

            ScrollView {
                VStack(spacing: 20) {
                    if alert.isTest { testBanner }

                    Image(systemName: "figure.fall")
                        .font(.system(size: 44, weight: .bold))
                        .foregroundStyle(FlareColor.failure)
                        .padding(.top, alert.isTest ? 0 : 24)
                        .accessibilityHidden(true)

                    Text(alert.timedOut ? "No response" : "Did you fall?")
                        .font(.archivo(.extraBold, size: 34, relativeTo: .largeTitle))
                        .foregroundStyle(FlareColor.text)

                    Text(message)
                        .font(.flareBody)
                        .foregroundStyle(FlareColor.secondaryText)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)

                    if !alert.timedOut { countdownRing }

                    okButton
                    if !alert.isTest {
                        callButton
                        locationButton
                    }
                    if alert.timedOut { helperCard }
                    if alert.isTest {
                        Text("This is only a practice run. Nothing is called or sent.")
                            .font(.flareSecondary)
                            .foregroundStyle(FlareColor.secondaryText)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
        }
        .preferredColorScheme(.dark)
        .accessibilityAddTraits(.isModal)
        .sheet(isPresented: $showMessage) {
            if let here {
                MessageComposer(
                    recipients: medical.medicalID.contacts
                        .filter { !$0.isBlank }
                        .compactMap { Dialer.normalized($0.phone) },
                    body: LocationMessage.body(for: here, placeName: store.selection?.title, reason: .fall),
                    onFinish: { showMessage = false })
                    .ignoresSafeArea()
            }
        }
    }

    /// Shown once nobody has answered: tells anyone nearby what is going on and what to do.
    private var helperCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("If you are helping", systemImage: "person.2.fill")
                .font(.flareSection)
                .foregroundStyle(FlareColor.text)
            Text("This person may have fallen and may not be able to talk. Please call the emergency number, tell them where you are, and stay with the person.")
                .font(.flareSecondary)
                .foregroundStyle(FlareColor.text)
                .fixedSize(horizontal: false, vertical: true)

            if let here {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Where we are")
                        .font(.flareCaption)
                        .foregroundStyle(FlareColor.secondaryText)
                    Text(LocationMessage.coordinateText(here))
                        .font(.archivo(.extraBold, size: 22, relativeTo: .title3))
                        .foregroundStyle(FlareColor.text)
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                    if let code = PlusCode.encode(latitude: here.coordinate.latitude,
                                                  longitude: here.coordinate.longitude) {
                        Text("Plus Code \(code)")
                            .font(.flareBody)
                            .foregroundStyle(FlareColor.text)
                    }
                    if let place = store.selection?.title {
                        Text("Near \(place)")
                            .font(.flareCaption)
                            .foregroundStyle(FlareColor.secondaryText)
                    }
                    Text("Position saved \(here.timestamp, style: .relative) ago")
                        .font(.flareCaption)
                        .foregroundStyle(FlareColor.secondaryText)
                }
            }

            Button {
                showMedical = true
            } label: {
                Label("Medical ID and contacts", systemImage: "person.text.rectangle")
                    .font(.flareBodyLarge)
                    .foregroundStyle(FlareColor.link)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .overlay(Capsule().stroke(FlareColor.link.opacity(0.6), lineWidth: 1.5))
            }
            .buttonStyle(.plain)
            .sheet(isPresented: $showMedical) {
                EmergencyMedicalView(contacts: medical.medicalID.contacts.filter { !$0.isBlank })
                    .environmentObject(medical)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }

    private var message: String {
        if alert.timedOut {
            return alert.isTest
                ? "In a real alert, this is where Flare asks you to call for help."
                : "Flare can't call for you. If you need help, call now."
        }
        return "Flare felt a hard impact and then no movement. If you're fine, tap I'm OK."
    }

    private var testBanner: some View {
        Text("TEST")
            .font(.archivo(.extraBold, size: 14, relativeTo: .caption))
            .tracking(2)
            .foregroundStyle(FlareColor.onFlare)
            .padding(.horizontal, 14)
            .frame(minHeight: 28)
            .background(Capsule().fill(FlareColor.warning))
            .padding(.top, 24)
    }

    private var countdownRing: some View {
        ZStack {
            Circle().stroke(Color.white.opacity(0.12), lineWidth: 10)
            Circle()
                .trim(from: 0, to: ringFraction)
                .stroke(FlareColor.failure, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 1), value: alert.secondsLeft)
            VStack(spacing: 0) {
                Text("\(alert.secondsLeft)")
                    .font(.archivo(.extraBold, size: 56, relativeTo: .largeTitle))
                    .foregroundStyle(FlareColor.text)
                    .monospacedDigit()
                Text("seconds")
                    .font(.flareSecondary)
                    .foregroundStyle(FlareColor.secondaryText)
            }
        }
        .frame(width: 168, height: 168)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(alert.secondsLeft) seconds left to answer")
    }

    private var okButton: some View {
        Button {
            fall.dismissAlert()
        } label: {
            Text(alert.isTest ? "End test" : "I'm OK")
                .font(.archivo(.extraBold, size: 24, relativeTo: .title2))
                .foregroundStyle(FlareColor.onFlare)
                .frame(maxWidth: .infinity, minHeight: 68)
                .background(Capsule().fill(FlareColor.ready))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var callButton: some View {
        switch callTarget {
        case .dial(let group):
            if let url = group.dialURL {
                Button {
                    openURL(url)
                    fall.dismissAlert()
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "phone.fill")
                        Text("Call \(group.displayNumber)")
                    }
                    .font(.archivo(.extraBold, size: 24, relativeTo: .title2))
                    .foregroundStyle(FlareColor.onFlare)
                    .frame(maxWidth: .infinity, minHeight: 68)
                    .background(Capsule().fill(FlareGradient.flare))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Call \(group.displayNumber), \(group.title)")
            }
        case .choose(let slot):
            Button {
                chooser = slot
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "phone.fill")
                    Text("Choose \(slot.title.lowercased()) number")
                }
                .font(.archivo(.extraBold, size: 22, relativeTo: .title2))
                .foregroundStyle(FlareColor.onFlare)
                .frame(maxWidth: .infinity, minHeight: 68)
                .background(Capsule().fill(FlareGradient.flare))
            }
            .buttonStyle(.plain)
            .accessibilityHint("Several numbers are listed. Opens the list to choose from")
            .sheet(item: $chooser) { slot in
                NumberChooserSheet(slot: slot)
            }
        case nil:
            Text("No verified emergency number for this area. Use your phone's built-in emergency call.")
                .font(.flareSecondary)
                .foregroundStyle(FlareColor.warning)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var locationButton: some View {
        if let here {
            if MFMessageComposeViewController.canSendText() {
                EmergencyPillButton(title: "Send my location by SMS", systemImage: "bubble.left") {
                    showMessage = true
                }
            } else {
                ShareLink(item: LocationMessage.body(for: here, placeName: store.selection?.title, reason: .fall)) {
                    EmergencyPillLabel(title: "Share my location", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.plain)
            }
        }
    }
}
