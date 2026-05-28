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
    case missingSystemDirectory(URL)

    var errorDescription: String? {
        switch self {
        case let .missingBundledArtifacts(url):
            return "Bundled Wine bridge DLLs were not found at \(url.path). Build them with Sources/SteamControllerBridge/Resources/WineBridge/build-wine-bridge.sh before packaging the app."
        case let .invalidPrefix(url):
            return "\(url.path) does not look like a Wine prefix."
        case let .missingSystemDirectory(url):
            return "Wine system directory was not found at \(url.path)."
        }
    }
}

final class WineBridgeInstaller {
    static let dllNames = [
        "xinput1_1.dll",
        "xinput1_2.dll",
        "xinput1_3.dll",
        "xinput1_4.dll",
        "xinput9_1_0.dll",
        "xinputuap.dll"
    ]
    private static let overrideValue = "native,builtin"
    private static let dllOverridesSection = "[Software\\\\Wine\\\\DllOverrides]"
    private static let appDefaultExecutables = [
        "steam.exe",
        "steamwebhelper.exe",
        "gameoverlayui.exe"
    ]

    func install(into prefixURL: URL) throws -> WineBridgeInstallStatus {
        let windowsURL = prefixURL
            .appendingPathComponent("drive_c", isDirectory: true)
            .appendingPathComponent("windows", isDirectory: true)
        let system32URL = windowsURL.appendingPathComponent("system32", isDirectory: true)
        let sysWOW64URL = windowsURL.appendingPathComponent("syswow64", isDirectory: true)

        guard FileManager.default.fileExists(atPath: system32URL.path) else {
            throw WineBridgeInstallerError.invalidPrefix(prefixURL)
        }

        let sourceURL = try bundledArtifactsURL()
        try installDLLs(
            from: sourceURL.appendingPathComponent("win64", isDirectory: true),
            to: system32URL
        )

        var installedTargets = ["64-bit DLLs into \(system32URL.path)"]
        if FileManager.default.fileExists(atPath: sysWOW64URL.path) {
            try installDLLs(
                from: sourceURL.appendingPathComponent("win32", isDirectory: true),
                to: sysWOW64URL
            )
            installedTargets.append("32-bit DLLs into \(sysWOW64URL.path)")
        }

        try updateDllOverrides(in: prefixURL)

        return WineBridgeInstallStatus(
            selectedPrefixPath: prefixURL.path,
            message: "Installed \(installedTargets.joined(separator: ", ")) and set global plus Steam app DLL overrides to native,builtin. Quit all Wine/Steam processes and relaunch Steam so the prefix reloads user.reg."
        )
    }

    private func bundledArtifactsURL() throws -> URL {
        let bundleURL = Bundle.main.resourceURL?
            .appendingPathComponent("WineBridge", isDirectory: true)
            ?? Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/WineBridge", isDirectory: true)

        guard FileManager.default.fileExists(
            atPath: bundleURL
                .appendingPathComponent("win64", isDirectory: true)
                .appendingPathComponent(Self.dllNames[0]).path
        ) else {
            throw WineBridgeInstallerError.missingBundledArtifacts(bundleURL)
        }

        return bundleURL
    }

    private func installDLLs(from sourceURL: URL, to destinationURL: URL) throws {
        guard FileManager.default.fileExists(atPath: destinationURL.path) else {
            throw WineBridgeInstallerError.missingSystemDirectory(destinationURL)
        }

        for name in Self.dllNames {
            let source = sourceURL.appendingPathComponent(name)
            let destination = destinationURL.appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.copyItem(at: source, to: destination)
        }
    }

    private func updateDllOverrides(in prefixURL: URL) throws {
        let userRegURL = prefixURL.appendingPathComponent("user.reg")
        let baseOverrideNames = Self.dllNames.map { $0.replacingOccurrences(of: ".dll", with: "") }
        let overrideNames = overrideNames(for: baseOverrideNames)
        let overrideLines = overrideNames.map { "\"\($0)\"=\"\(Self.overrideValue)\"" }

        var registryText: String
        if FileManager.default.fileExists(atPath: userRegURL.path) {
            registryText = try String(contentsOf: userRegURL, encoding: .utf8)
        } else {
            registryText = "WINE REGISTRY Version 2\n"
        }

        var lines = registryText.components(separatedBy: .newlines)
        lines = upsertOverrideSection(
            Self.dllOverridesSection,
            overrideNames: overrideNames,
            overrideLines: overrideLines,
            in: lines
        )

        for executable in Self.appDefaultExecutables {
            lines = upsertOverrideSection(
                "[Software\\\\Wine\\\\AppDefaults\\\\\(executable)\\\\DllOverrides]",
                overrideNames: overrideNames,
                overrideLines: overrideLines,
                in: lines
            )
        }

        try lines.joined(separator: "\n").write(to: userRegURL, atomically: true, encoding: .utf8)
        try overrideRegFileText(baseOverrideNames: baseOverrideNames)
            .write(
                to: prefixURL.appendingPathComponent("scb-xinput-overrides.reg"),
                atomically: true,
                encoding: .utf8
            )
    }

    private func overrideNames(for baseOverrideNames: [String]) -> [String] {
        baseOverrideNames + baseOverrideNames.map { "*\($0)" }
    }

    private func upsertOverrideSection(
        _ sectionName: String,
        overrideNames: [String],
        overrideLines: [String],
        in registryLines: [String]
    ) -> [String] {
        var lines = registryLines
        let sectionIndex = lines.firstIndex { line in
            line.hasPrefix(sectionName)
        }

        guard let sectionIndex else {
            if lines.last?.isEmpty == false {
                lines.append("")
            }
            lines.append(sectionName)
            lines.append(contentsOf: overrideLines)
            return lines
        }

        var endIndex = lines.count
        var index = sectionIndex + 1
        while index < lines.count {
            if lines[index].hasPrefix("[") {
                endIndex = index
                break
            }
            index += 1
        }

        let overrideNameSet = Set(overrideNames)
        let preservedLines = lines[(sectionIndex + 1)..<endIndex].filter { line in
            !overrideNameSet.contains { name in line.hasPrefix("\"\(name)\"=") }
        }

        lines.replaceSubrange(
            (sectionIndex + 1)..<endIndex,
            with: overrideLines + preservedLines
        )
        return lines
    }

    private func overrideRegFileText(baseOverrideNames: [String]) -> String {
        let overrideLines = overrideNames(for: baseOverrideNames)
            .map { "\"\($0)\"=\"\(Self.overrideValue)\"" }

        var lines = [
            "REGEDIT4",
            "",
            "[HKEY_CURRENT_USER\\Software\\Wine\\DllOverrides]"
        ] + overrideLines

        for executable in Self.appDefaultExecutables {
            lines += [
                "",
                "[HKEY_CURRENT_USER\\Software\\Wine\\AppDefaults\\\(executable)\\DllOverrides]"
            ] + overrideLines
        }

        return lines.joined(separator: "\n") + "\n"
    }
}
