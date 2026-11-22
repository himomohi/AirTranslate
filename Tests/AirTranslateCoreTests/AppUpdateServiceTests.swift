import Foundation
import Testing
@testable import AirTranslate

struct AppUpdateServiceTests {
    private let digest = "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
    private let assetURL = "https://github.com/himomohi/AirTranslate/releases/download/v1.19.0/AirTranslate-1.19.0.dmg"

    @Test
    func comparesStableVersionsNumericallyAndUsesTheVersionedInstaller() throws {
        let available = try AppUpdateService.availableRelease(in: response(), installedVersion: "1.9.12")
        let release = try #require(available)
        #expect(release.version == "1.19.0")
        #expect(release.notesURL.absoluteString == "https://github.com/himomohi/AirTranslate/releases/tag/v1.19.0")
        #expect(release.diskImage?.url.absoluteString == assetURL)
        #expect(release.diskImage?.sha256 == digest)
        #expect(try AppUpdateService.availableRelease(in: response(), installedVersion: "1.19.0") == nil)
        #expect(try AppUpdateService.availableRelease(in: response(), installedVersion: "1.19.1") == nil)
    }

    @Test
    func refusesDraftPrereleaseAndMalformedTags() throws {
        #expect(try AppUpdateService.availableRelease(in: response(draft: true), installedVersion: "1.18.1") == nil)
        #expect(try AppUpdateService.availableRelease(in: response(prerelease: true), installedVersion: "1.18.1") == nil)
        for tag in ["v1.19.0-beta.1", "v1.19", "1.19.0", "v01.19.0", "v1.19.0/../../test"] {
            #expect(throws: AppUpdateService.Failure.invalidVersion) {
                try AppUpdateService.availableRelease(in: response(tag: tag), installedVersion: "1.18.1")
            }
        }
    }

    @Test
    func missingOrUnexpectedInstallerLeavesOnlyOfficialReleaseNotes() throws {
        for url in ["https://example.com/AirTranslate-1.19.0.dmg", assetURL + "?extra=1",
                    assetURL.replacingOccurrences(of: "v1.19.0", with: "v1.18.1")] {
            let available = try AppUpdateService.availableRelease(in: response(url: url), installedVersion: "1.18.1")
            let release = try #require(available)
            #expect(release.diskImage == nil)
            #expect(release.notesURL.host() == "github.com")
        }
        for digest in ["null", "\"sha256:123\"", "\"sha256:\(String(repeating: "z", count: 64))\""] {
            let available = try AppUpdateService.availableRelease(in: response(digestJSON: digest), installedVersion: "1.18.1")
            let release = try #require(available)
            #expect(release.diskImage == nil)
        }
        for data in [response(size: 0), response(state: "starter")] {
            #expect(try AppUpdateService.availableRelease(in: data, installedVersion: "1.18.1")?.diskImage == nil)
        }
    }

    @Test
    func verifiesDiskImageLengthAndHashBeforeOpening() throws {
        let available = try AppUpdateService.availableRelease(in: response(), installedVersion: "1.18.1")
        let release = try #require(available)
        let image = try #require(release.diskImage)
        let file = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: file) }

        try Data("abc".utf8).write(to: file)
        try image.verify(file: file)

        try Data("abd".utf8).write(to: file)
        #expect(throws: AppUpdateService.Failure.invalidDownload) { try image.verify(file: file) }
        try Data("ab".utf8).write(to: file)
        #expect(throws: AppUpdateService.Failure.invalidDownload) { try image.verify(file: file) }
    }

    private func response(
        tag: String = "v1.19.0", draft: Bool = false, prerelease: Bool = false,
        url: String? = nil, digestJSON: String? = nil, size: Int = 3, state: String = "uploaded"
    ) -> Data {
        let jsonDigest = digestJSON ?? "\"sha256:\(digest)\""
        return Data("""
        {
          "tag_name": "\(tag)", "draft": \(draft), "prerelease": \(prerelease),
          "assets": [
            {"name": "AirTranslate-1.19.0.dmg", "state": "\(state)", "size": \(size),
              "digest": \(jsonDigest), "browser_download_url": "\(url ?? assetURL)"}
          ]
        }
        """.utf8)
    }
}
