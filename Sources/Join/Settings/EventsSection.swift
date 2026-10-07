import SwiftUI
import JoinCore

/// What Join! does with events nobody else is on and with out-of-office events, a pop-up for each,
/// then the keywords that make an event out of office. One section, as the user picked from the
/// settings design's options; 1.1 had a switch here and a separate Out of office section with two.
@MainActor
struct EventsSection: View {
    @Environment(AppModel.self) private var model
    /// Held here so Restore Defaults can drop a half-typed keyword before the field commits it.
    @State private var keywordDraft = ""

    var body: some View {
        @Bindable var preferences = model.preferences

        SettingsSection(title: SettingsOptions.eventsSectionTitle) {
            visibilityRow(SettingsOptions.eventsWithoutParticipantsTitle, selection: $preferences.eventsWithoutParticipants, separator: false)
            visibilityRow(SettingsOptions.outOfOfficeEventsTitle, selection: $preferences.outOfOfficeEvents)
            SettingsSeparator()
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 12) {
                    Text(SettingsOptions.outOfOfficeKeywordsTitle)
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
                Text(SettingsOptions.eventsFootnote)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 8)
            .padding(.bottom, 12)
        }
    }

    /// Show and alert, Show in the list only or Exclude, for one kind of event.
    private func visibilityRow(_ title: String, selection: Binding<EventVisibility>, separator: Bool = true) -> some View {
        SettingsRow(title: title, separator: separator) {
            Picker(title, selection: selection) {
                ForEach(EventVisibility.allCases, id: \.self) { choice in
                    Text(choice.title).tag(choice)
                }
            }
            .labelsHidden()
            .fixedSize()
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
