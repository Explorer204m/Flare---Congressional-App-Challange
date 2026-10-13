import Foundation
import CoreText

/// Finds files shipped inside the app bundle.
///
/// Depending on how Xcode copies resources, files can end up at the bundle
/// root or keep a subfolder, so a few likely locations are searched.
enum BundleResource {
    private static let subdirectories: [String?] = [
        nil, "Resources", "Fonts", "Resources/Fonts", "Flare/Resources", "Flare/Resources/Fonts"
    ]

    static func url(forResource name: String, withExtension ext: String) -> URL? {
        for subdirectory in subdirectories {
            if let url = Bundle.main.url(forResource: name, withExtension: ext, subdirectory: subdirectory) {
                return url
            }
        }
        return nil
    }

    static func urls(withExtension ext: String) -> [URL] {
        var found = Set<URL>()
        for subdirectory in subdirectories {
            for url in Bundle.main.urls(forResourcesWithExtension: ext, subdirectory: subdirectory) ?? [] {
                found.insert(url)
            }
        }
        return Array(found)
    }
}

enum FontRegistrar {
    /// Registers the bundled Archivo fonts for this process. Call once at launch,
    /// before any text is drawn.
    static func registerBundledFonts() {
        for url in BundleResource.urls(withExtension: "ttf") {
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }
}
