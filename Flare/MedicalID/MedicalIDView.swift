import SwiftUI

/// The Medical ID tab: what first responders or a helper need to know, and one-tap
/// calls and messages to the person's emergency contacts. Stored only on this phone.
struct MedicalIDView: View {
    @EnvironmentObject private var store: MedicalIDStore
    @Environment(\.openURL) private var openURL
    @State private var showEditor = false

    private var info: MedicalID { store.medicalID }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header

                if store.loadFailed {
                    unreadableCard
                } else if info.isEmpty {
                    emptyCard
                } else {
                    summaryCard
                    infoSections
                    contactsSection
                }

                lockScreenNote
                privacyNote
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .sheet(isPresented: $showEditor) {
            MedicalIDEditor()
        }
    }

    // MARK: Header

    private var header: some View {
        HStack {
            Text("Medical ID")
                .font(.flareTitle)
                .foregroundStyle(FlareColor.text)
                .accessibilityAddTraits(.isHeader)
            Spacer()
            if !info.isEmpty || store.loadFailed {
                Button {
                    showEditor = true
                } label: {
                    Text(store.loadFailed ? "Start new" : "Edit")
                        .font(.flareBody)
                        .foregroundStyle(FlareColor.text)
                        .padding(.horizontal, 18)
                        .frame(minHeight: 44)
                        .cardSurface(cornerRadius: 22)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: Empty and error states

    private var emptyCard: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle().fill(FlareColor.hospital.opacity(0.22)).frame(width: 72, height: 72)
                Image(systemName: "person.text.rectangle.fill")
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(FlareColor.hospital)
            }
            Text("Set up your Medical ID")
                .font(.flareSection)
                .foregroundStyle(FlareColor.text)
            Text("Add your blood type, allergies, medicines and emergency contacts so you or someone helping you can find them fast. Everything is optional and stays on this phone.")
                .font(.flareSecondary)
                .foregroundStyle(FlareColor.secondaryText)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                showEditor = true
            } label: {
                Text("Create Medical ID")
                    .font(.flareBodyLarge)
                    .foregroundStyle(FlareColor.onFlare)
                    .frame(maxWidth: .infinity, minHeight: 54)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(FlareGradient.flare)
                    )
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .cardSurface()
    }

    private var unreadableCard: some View {
        NoticeCard(
            systemImage: "exclamationmark.triangle.fill",
            message: "Your saved Medical ID could not be read. This can happen if the phone was only just unlocked. Nothing was deleted. Try again, or start a new one (the unreadable file is kept, not erased).") {
            HStack(spacing: 20) {
                LinkButton(title: "Try again") { store.reload() }
                LinkButton(title: "Start new") { showEditor = true }
            }
        }
    }

    // MARK: Summary

    private var summaryCard: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(info.fullName.isEmpty ? "Name not added" : info.fullName)
                    .font(.flareSection)
                    .foregroundStyle(FlareColor.text)
                    .fixedSize(horizontal: false, vertical: true)
                if let dob = info.dateOfBirth {
                    let born = dob.formatted(date: .long, time: .omitted)
                    Text(info.age.map { "Age \($0) \u{00B7} born \(born)" } ?? "Born \(born)")
                        .font(.flareSecondary)
                        .foregroundStyle(FlareColor.secondaryText)
                }
            }
            Spacer(minLength: 8)
            if let blood = info.bloodType {
                VStack(spacing: 2) {
                    Text(blood.rawValue)
                        .font(.archivo(.extraBold, size: 30, relativeTo: .title))
                        .foregroundStyle(FlareColor.onFlare)
                    Text("BLOOD")
                        .font(.archivo(.bold, size: 10, relativeTo: .caption2))
                        .tracking(1)
                        .foregroundStyle(FlareColor.onFlare.opacity(0.8))
                }
                .frame(width: 76, height: 76)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(FlareGradient.flare)
                )
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Blood type \(blood.rawValue)")
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }

    // MARK: Info sections

    @ViewBuilder
    private var infoSections: some View {
        if !info.allergies.isEmpty {
            infoCard(title: "Allergies", systemImage: "exclamationmark.triangle.fill",
                     tint: FlareColor.warning, text: info.allergies)
        }
        if !info.conditions.isEmpty {
            infoCard(title: "Medical conditions", systemImage: "heart.text.square.fill",
                     tint: FlareColor.hospital, text: info.conditions)
        }
        if !info.medications.isEmpty {
            infoCard(title: "Medications", systemImage: "pills.fill",
                     tint: FlareColor.pharmacy, text: info.medications)
        }
        if info.organDonation != .unspecified {
            infoCard(title: "Organ donor", systemImage: "heart.fill",
                     tint: FlareColor.hospital, text: info.organDonation.label)
        }
        if !info.notes.isEmpty {
            infoCard(title: "Other notes", systemImage: "note.text",
                     tint: FlareColor.police, text: info.notes)
        }
    }

    private func infoCard(title: String, systemImage: String, tint: Color, text: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(tint)
                Text(title)
                    .font(.flareBodyLarge)
                    .foregroundStyle(FlareColor.text)
            }
            Text(text)
                .font(.flareBody)
                .foregroundStyle(FlareColor.text)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
        .accessibilityElement(children: .combine)
    }

    // MARK: Emergency contacts

    @ViewBuilder
    private var contactsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Emergency contacts")
                .font(.flareSection)
                .foregroundStyle(FlareColor.text)
            if info.contacts.isEmpty {
                NoticeCard(
                    systemImage: "person.crop.circle.badge.plus",
                    message: "No emergency contact yet. Add someone who can be called if you need help.",
                    tint: FlareColor.link) {
                    LinkButton(title: "Add a contact") { showEditor = true }
                }
            } else {
                ForEach(info.contacts) { contact in
                    ContactActionCard(contact: contact)
                }
            }
        }
    }

    // MARK: Notes

    private var lockScreenNote: some View {
        NoticeCard(
            systemImage: "lock.fill",
            message: "Flare's Medical ID can only be read once your phone is unlocked. For help from someone who can't unlock it, also set up Medical ID in the Health app so it shows from the lock screen under Emergency.",
            tint: FlareColor.link) {
            LinkButton(title: "Open Health app") {
                if let url = URL(string: "x-apple-health://") { openURL(url) }
            }
        }
    }

    private var privacyNote: some View {
        Text("Your Medical ID is saved only on this phone, encrypted while it is locked. Flare never sends it anywhere. It is not a medical record, so keep it up to date yourself.")
            .font(.flareCaption)
            .foregroundStyle(FlareColor.secondaryText)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// One emergency contact with one-tap call and message buttons.
private struct ContactActionCard: View {
    let contact: EmergencyContactPerson
    @Environment(\.openURL) private var openURL

    private var callURL: URL? { Dialer.telURL(for: contact.phone) }
    private var smsURL: URL? { Dialer.smsURL(for: contact.phone) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(contact.displayName)
                    .font(.flareBodyLarge)
                    .foregroundStyle(FlareColor.text)
                if !contact.relationship.isEmpty {
                    Text(contact.relationship)
                        .font(.flareSecondary)
                        .foregroundStyle(FlareColor.secondaryText)
                }
                if !contact.phone.isEmpty {
                    Text(contact.phone)
                        .font(.archivo(.extraBold, size: 22, relativeTo: .title3))
                        .foregroundStyle(FlareColor.text)
                        .padding(.top, 2)
                }
            }

            if let callURL, let smsURL {
                HStack(spacing: 10) {
                    Button {
                        openURL(callURL)
                    } label: {
                        Label("Call", systemImage: "phone.fill")
                            .font(.flareBody)
                            .foregroundStyle(FlareColor.onFlare)
                            .frame(maxWidth: .infinity, minHeight: 46)
                            .background(Capsule().fill(FlareGradient.flare))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Call \(contact.displayName)")

                    Button {
                        openURL(smsURL)
                    } label: {
                        Label("Message", systemImage: "message.fill")
                            .font(.flareBody)
                            .foregroundStyle(FlareColor.text)
                            .frame(maxWidth: .infinity, minHeight: 46)
                            .background(Capsule().fill(Color.white.opacity(0.14)))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Message \(contact.displayName)")
                }
            } else if contact.phone.isEmpty {
                Text("No phone number saved for this contact.")
                    .font(.flareSecondary)
                    .foregroundStyle(FlareColor.warning)
            } else {
                Text("This number can't be dialed automatically. Dial it by hand.")
                    .font(.flareSecondary)
                    .foregroundStyle(FlareColor.warning)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
        .accessibilityElement(children: .contain)
    }
}
