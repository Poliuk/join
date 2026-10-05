import SwiftUI
import JoinCore

/// The out-of-office switch and title keywords. On the General pane by the user's choice;
/// the settings design drew it on Calendars.
@MainActor
struct OutOfOfficeSection: View {
    @Environment(AppModel.self) private var model
    /// Held here so Restore Defaults can drop a half-typed keyword before the field commits it.
    @State private var keywordDraft = ""

    var body: some View {
        @Bindable var preferences = model.preferences

        SettingsSection(title: "Out of office") {
            SettingsSwitchRow(title: "Alert for out-of-office events", isOn: $preferences.alertForOutOfOffice, separator: false)
            SettingsSwitchRow(title: "Show out-of-office events in the list", isOn: $preferences.showOutOfOfficeInList)
            SettingsSeparator()
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 12) {
                    Text("Title keywords")
                    Spacer(minLength: 0)
                    Button("Restore Defaults") {
                        keywordDraft = ""
                        preferences.resetOutOfOfficeKeywords()
                    }
                    .buttonStyle(.link)
                    .font(.callout)
                    .disabled(preferences.outOfOfficeKeywords == OutOfOfficeDetector.defaultKeywords)
                }
                KeywordTokenField(keywords: $preferences.outOfOfficeKeywords, draft: $keywordDraft)
                Text("An event counts as out of office when its title contains any of these words. It only alerts when the first option is on, and shows dimmed in the menu bar list when the second is on. Press Return to add a keyword.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 8)
            .padding(.bottom, 12)
        }
    }
}

/// The out-of-office keywords as removable tokens, with a field that adds one on Return or comma.
private struct KeywordTokenField: View {
    @Binding var keywords: [String]
    @Binding var draft: String
    @FocusState private var fieldFocused: Bool

    var body: some View {
        SettingsFlowLayout(spacing: 6) {
            ForEach(Array(keywords.enumerated()), id: \.offset) { index, keyword in
                KeywordToken(text: keyword) { keywords.remove(at: index) }
            }
            TextField("Add keyword", text: $draft)
                .textFieldStyle(.plain)
                .font(.callout)
                .padding(.horizontal, 4)
                .frame(height: 22)
                .focused($fieldFocused)
                .onSubmit(commitDraft)
                .onChange(of: draft) { _, newValue in
                    let split = KeywordList.splittingDraft(newValue, into: keywords)
                    guard split.draft != newValue else { return }
                    keywords = split.keywords
                    draft = split.draft
                }
                .onChange(of: fieldFocused) { _, focused in
                    if !focused { commitDraft() }
                }
                .onKeyPress(.delete) {
                    guard draft.isEmpty, !keywords.isEmpty else { return .ignored }
                    keywords.removeLast()
                    return .handled
                }
                .layoutValue(key: SettingsFlowFill.self, value: 120)
        }
        .padding(6)
        .background(SettingsPalette.field, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(SettingsPalette.fieldBorder, lineWidth: 0.5)
        }
        .overlay {
            if fieldFocused {
                RoundedRectangle(cornerRadius: 8.5, style: .continuous)
                    .stroke(Color(nsColor: .keyboardFocusIndicatorColor), lineWidth: 3)
                    .padding(-1.5)
                    .allowsHitTesting(false)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { fieldFocused = true }
    }

    private func commitDraft() {
        keywords = KeywordList.adding(draft, to: keywords)
        draft = ""
    }
}

private struct KeywordToken: View {
    let text: String
    let remove: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 2) {
            Text(text)
                .font(.callout)
                .lineLimit(1)
                .truncationMode(.tail)
            Button(action: remove) {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .frame(width: 16, height: 16)
                    .foregroundStyle(hovering ? .primary : .secondary)
                    .background(hovering ? SettingsPalette.chip : .clear, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { hovering = $0 }
            .help("Remove “\(text)”")
            .accessibilityLabel("Remove \(text)")
        }
        .padding(.leading, 8)
        .padding(.trailing, 3)
        .frame(height: 22)
        .background(SettingsPalette.chip, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
    }
}
