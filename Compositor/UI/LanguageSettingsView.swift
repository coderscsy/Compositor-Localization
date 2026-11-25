import SwiftUI

struct LanguageSettingsView: View {
    @State private var selection = InterfaceLanguage.selection

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Interface Language", selection: $selection) {
                Text("System Default").tag("")
                ForEach(InterfaceLanguage.available, id: \.self) { code in
                    Text(verbatim: Locale(identifier: code).localizedString(forIdentifier: code) ?? code).tag(code)
                }
            }
            .pickerStyle(.menu)
            .onChange(of: selection) { _, language in InterfaceLanguage.select(language) }

            Text("Quit and reopen Compositor to apply the language change.")
                .foregroundStyle(.secondary)
        }
        .scenePadding()
        .frame(width: 420)
    }
}

private enum InterfaceLanguage {
    private static let preference = "AppleLanguages"
    static let available = ["en", "zh-Hans", "zh-Hant", "fr", "de", "es", "ja", "ko"].filter { code in
        Bundle.main.localizations.contains(code)
    }

    static var selection: String {
        // The usual defaults lookup would also return the Mac's global language list.
        guard let domain = Bundle.main.bundleIdentifier,
              let languages = UserDefaults.standard.persistentDomain(forName: domain)?[preference] as? [String],
              !languages.isEmpty else { return "" }
        return Bundle.preferredLocalizations(from: available, forPreferences: languages).first ?? ""
    }

    static func select(_ language: String) {
        // The next launch uses the same app preference for SwiftUI, Foundation, and AppKit.
        if language.isEmpty {
            UserDefaults.standard.removeObject(forKey: preference)
        } else {
            UserDefaults.standard.set([language], forKey: preference)
        }
    }
}
