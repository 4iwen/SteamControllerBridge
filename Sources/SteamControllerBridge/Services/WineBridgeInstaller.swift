import Foundation

struct WineBridgeInstallStatus: Equatable {
    var selectedPrefixPath: String?
    var message: String

    static let initial = WineBridgeInstallStatus(
        selectedPrefixPath: nil,
        message: "Not installed"
    )
}

enum WineBridgeInstallerError: LocalizedError {
    case missingBundledArtifacts(URL)
    case invalidPrefix(URL)

    var errorDescription: String? {
        switch self {
        case let .missingBundledArtifacts(url):
            return "Bundled Wine bridge DLLs were not found at \(url.path). Build them with Sources/SteamControllerBridge/Resources/WineBridge/build-wine-bridge.sh before packaging the app."
        case let .invalidPrefix(url):
            return "\(url.path) does not look like a Wine prefix."
        }
    }
}

final class WineBridgeInstaller {
    static let dllNames = ["xinput1_3.dll", "xinput1_4.dll", "xinput9_1_0.dll"]
    private static let overrideValue = "native,builtin"
    private static let dllOverridesSection = "[Software\\\\Wine\\\\DllOverrides]"

    func install(into prefixURL: URL) throws -> WineBridgeInstallStatus {
        let system32URL = prefixURL
            .appendingPathComponent("drive_c", isDirectory: true)
            .appendingPathComponent("windows", isDirectory: true)
            .appendingPathComponent("system32", isDirectory: true)

        guard FileManager.default.fileExists(atPath: system32URL.path) else {
            throw WineBridgeInstallerError.invalidPrefix(prefixURL)
        }

        let sourceURL = try bundledArtifactsURL()
        for name in Self.dllNames {
            let source = sourceURL.appendingPathComponent(name)
            let destination = system32URL.appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.copyItem(at: source, to: destination)
        }

        try updateDllOverrides(in: prefixURL)

        return WineBridgeInstallStatus(
            selectedPrefixPath: prefixURL.path,
            message: "Installed \(Self.dllNames.joined(separator: ", ")) into \(system32URL.path) and set Wine DLL overrides to native,builtin."
        )
    }

    private func bundledArtifactsURL() throws -> URL {
        let bundleURL = Bundle.main.resourceURL?
            .appendingPathComponent("WineBridge", isDirectory: true)
            ?? Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/WineBridge", isDirectory: true)

        guard FileManager.default.fileExists(atPath: bundleURL.appendingPathComponent(Self.dllNames[0]).path) else {
            throw WineBridgeInstallerError.missingBundledArtifacts(bundleURL)
        }

        return bundleURL
    }

    private func updateDllOverrides(in prefixURL: URL) throws {
        let userRegURL = prefixURL.appendingPathComponent("user.reg")
        let overrideLines = Self.dllNames
            .map { $0.replacingOccurrences(of: ".dll", with: "") }
            .map { "\"\($0)\"=\"\(Self.overrideValue)\"" }

        var registryText: String
        if FileManager.default.fileExists(atPath: userRegURL.path) {
            registryText = try String(contentsOf: userRegURL, encoding: .utf8)
        } else {
            registryText = "WINE REGISTRY Version 2\n"
        }

        var lines = registryText.components(separatedBy: .newlines)
        let sectionIndex = lines.firstIndex { line in
            line.hasPrefix(Self.dllOverridesSection)
        }

        if let sectionIndex {
            var endIndex = lines.count
            var index = sectionIndex + 1
            while index < lines.count {
                if lines[index].hasPrefix("[") {
                    endIndex = index
                    break
                }
                index += 1
            }

            let overrideNames = Set(Self.dllNames.map { $0.replacingOccurrences(of: ".dll", with: "") })
            let preservedLines = lines[(sectionIndex + 1)..<endIndex].filter { line in
                !overrideNames.contains { name in line.hasPrefix("\"\(name)\"=") }
            }

            lines.replaceSubrange(
                (sectionIndex + 1)..<endIndex,
                with: overrideLines + preservedLines
            )
        } else {
            if lines.last?.isEmpty == false {
                lines.append("")
            }
            lines.append(Self.dllOverridesSection)
            lines.append(contentsOf: overrideLines)
        }

        try lines.joined(separator: "\n").write(to: userRegURL, atomically: true, encoding: .utf8)
    }
}
