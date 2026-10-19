import Foundation
import CoreText
import UIKit

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
    /// before any text is drawn. Calling it again does nothing.
    static func registerBundledFonts() {
        _ = availableArchivoFonts
    }

    /// PostScript names of the Archivo weights that loaded. Worked out once, right after
    /// registering, so `Font.archivo` doesn't look the font up again for every piece of text.
    /// Using it also registers the fonts, so it can't be read before registration.
    static let availableArchivoFonts: Set<String> = {
        for url in BundleResource.urls(withExtension: "ttf") {
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
        return Set(ArchivoWeight.allCases
            .map(\.postScriptName)
            .filter { UIFont(name: $0, size: 17) != nil })
    }()
}
