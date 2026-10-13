import SwiftUI
import UIKit

/// Edit sheet for the Medical ID. Changes are kept in a draft and only saved when
/// the person taps Save; leaving with unsaved changes asks first.
struct MedicalIDEditor: View {
    @EnvironmentObject private var store: MedicalIDStore
    @Environment(\.dismiss) private var dismiss

    @State private var draft: MedicalID
    @State private var original: MedicalID
    @State private var confirmDiscard = false
    @State private var confirmDelete = false

    init(starting: MedicalID? = nil) {
        // Real values are filled in `onAppear` from the store; this keeps the
        // initializer free of environment access.
        let value = starting ?? MedicalID()
        _draft = State(initialValue: value)
        _original = State(initialValue: value)
    }

    private var hasChanges: Bool { draft != original }

    private static let defaultBirthDate: Date = {
        Calendar.current.date(byAdding: .year, value: -30, to: Date()) ?? Date()
    }()

    var body: some View {
        NavigationStack {
            ZStack {
                FlareBackground()
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        Text("Everything here is optional. It is saved only on this phone.")
                            .font(.flareSecondary)
                            .foregroundStyle(FlareColor.secondaryText)

                        aboutYouSection
                        healthSection
                        contactsSection

                        if let message = store.saveErrorMessage {
                            Text(message)
                                .font(.flareSecondary)
                                .foregroundStyle(FlareColor.failure)
                        }

                        if store.hasContent {
                            Button {
                                confirmDelete = true
                            } label: {
                                Text("Delete Medical ID")
                                    .font(.flareBody)
                                    .foregroundStyle(FlareColor.failure)
                                    .frame(maxWidth: .infinity, minHeight: 50)
                                    .cardSurface(cornerRadius: 16)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(20)
                }
                .scrollIndicators(.hidden)
                .scrollDismissesKeyboard(.interactively)
            }
            .navigationTitle("Medical ID")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        if hasChanges { confirmDiscard = true } else { dismiss() }
                    }
                    .font(.flareBody)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if store.save(draft) { dismiss() }
                    }
                    .font(.flareBody)
                    .disabled(draft.hasInvalidPhone)
                }
            }
            .confirmationDialog("Discard your changes?", isPresented: $confirmDiscard, titleVisibility: .visible) {
                Button("Discard changes", role: .destructive) { dismiss() }
                Button("Keep editing", role: .cancel) {}
            }
            .confirmationDialog("Delete your Medical ID from this phone?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete Medical ID", role: .destructive) {
                    if store.erase() { dismiss() }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This can't be undone.")
            }
        }
        .interactiveDismissDisabled(hasChanges)
        .onAppear {
            // Start from what is saved (the sheet is created before the store is read).
            if !hasChanges {
                draft = store.medicalID
                original = store.medicalID
            }
            store.saveErrorMessage = nil
        }
    }

    // MARK: About you

    private var aboutYouSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("About you")

            fieldCard {
                TextField("", text: $draft.fullName,
                          prompt: Text("Full name").foregroundStyle(FlareColor.secondaryText))
                    .textContentType(.name)
                    .font(.flareBody)
                    .foregroundStyle(FlareColor.text)
                    .frame(minHeight: 28)
            }

            fieldCard {
                VStack(alignment: .leading, spacing: 10) {
                    Toggle(isOn: Binding(
                        get: { draft.dateOfBirth != nil },
                        set: { on in
                            draft.dateOfBirth = on
                                ? (draft.dateOfBirth ?? Self.defaultBirthDate) : nil
                        })) {
                        Text("Date of birth")
                            .font(.flareBody)
                            .foregroundStyle(FlareColor.text)
                    }
                    .tint(FlareColor.accent)

                    if draft.dateOfBirth != nil {
                        DatePicker(
                            "Date of birth",
                            selection: Binding(
                                get: { draft.dateOfBirth ?? Self.defaultBirthDate },
                                set: { draft.dateOfBirth = $0 }),
                            in: ...Date(),
                            displayedComponents: .date)
                            .labelsHidden()
                            .datePickerStyle(.compact)
                            .tint(FlareColor.accent)
                    }
                }
            }

            fieldCard {
                HStack {
                    Text("Blood type")
                        .font(.flareBody)
                        .foregroundStyle(FlareColor.text)
                    Spacer()
                    Picker("Blood type", selection: $draft.bloodType) {
                        Text("Not stated").tag(BloodType?.none)
                        ForEach(BloodType.allCases) { type in
                            Text(type.rawValue).tag(BloodType?.some(type))
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(FlareColor.link)
                }
            }

            fieldCard {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Organ donor")
                        .font(.flareBody)
                        .foregroundStyle(FlareColor.text)
                    Picker("Organ donor", selection: $draft.organDonation) {
                        ForEach(OrganDonation.allCases) { option in
                            Text(option.label).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                }
            }
        }
    }

    // MARK: Health

    private var healthSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Health")
            textArea("Allergies", text: $draft.allergies,
                     prompt: "For example: penicillin, peanuts, bee stings")
            textArea("Medical conditions", text: $draft.conditions,
                     prompt: "For example: asthma, diabetes, epilepsy")
            textArea("Medications", text: $draft.medications,
                     prompt: "Name and dose, one per line")
            textArea("Other notes", text: $draft.notes,
                     prompt: "Anything a helper should know")
        }
    }

    private func textArea(_ title: String, text: Binding<String>, prompt: String) -> some View {
        fieldCard {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.flareBody)
                    .foregroundStyle(FlareColor.text)
                TextField("", text: text,
                          prompt: Text(prompt).foregroundStyle(FlareColor.secondaryText),
                          axis: .vertical)
                    .lineLimit(2...8)
                    .font(.flareSecondary)
                    .foregroundStyle(FlareColor.text)
            }
        }
    }

    // MARK: Contacts

    private var contactsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Emergency contacts")

            ForEach($draft.contacts) { $contact in
                contactEditor($contact)
            }

            if draft.contacts.count < MedicalID.maxContacts {
                Button {
                    draft.contacts.append(EmergencyContactPerson())
                } label: {
                    Label("Add emergency contact", systemImage: "plus.circle.fill")
                        .font(.flareBody)
                        .foregroundStyle(FlareColor.link)
                        .frame(maxWidth: .infinity, minHeight: 50)
                        .cardSurface(cornerRadius: 16)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func contactEditor(_ contact: Binding<EmergencyContactPerson>) -> some View {
        fieldCard {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Contact")
                        .font(.flareBody)
                        .foregroundStyle(FlareColor.text)
                    Spacer()
                    Button {
                        let target = contact.wrappedValue.id
                        draft.contacts.removeAll { $0.id == target }
                    } label: {
                        Image(systemName: "trash")
                            .foregroundStyle(FlareColor.failure)
                            .frame(width: 44, height: 44)
                    }
                    .accessibilityLabel("Remove this contact")
                }
                field("Name", text: contact.name, content: .name, keyboard: .default)
                field("Relationship (for example: Mother)", text: contact.relationship,
                      content: nil, keyboard: .default)
                field("Phone number", text: contact.phone, content: .telephoneNumber, keyboard: .phonePad)
                if contact.wrappedValue.hasInvalidPhone {
                    Text("Use only digits, spaces, dashes, brackets and a leading +.")
                        .font(.flareCaption)
                        .foregroundStyle(FlareColor.failure)
                }
            }
        }
    }

    private func field(_ prompt: String, text: Binding<String>,
                       content: UITextContentType?, keyboard: UIKeyboardType) -> some View {
        TextField("", text: text,
                  prompt: Text(prompt).foregroundStyle(FlareColor.secondaryText))
            .textContentType(content)
            .keyboardType(keyboard)
            .font(.flareBody)
            .foregroundStyle(FlareColor.text)
            .padding(.horizontal, 12)
            .frame(minHeight: 44)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.white.opacity(0.06))
            )
    }

    // MARK: Shared pieces

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.flareSection)
            .foregroundStyle(FlareColor.text)
            .accessibilityAddTraits(.isHeader)
    }

    private func fieldCard<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardSurface(cornerRadius: 16)
    }
}
