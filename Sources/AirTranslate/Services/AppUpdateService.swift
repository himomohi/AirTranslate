import CoreServices
import CryptoKit
import Foundation

struct AppUpdateRelease: Hashable, Sendable {
    let version: String
    let notesURL: URL
    let diskImage: DiskImage?

    struct DiskImage: Hashable, Sendable {
        let url: URL
        let size: Int
        let sha256: String

        func verify(file: URL) throws {
            guard try file.resourceValues(forKeys: [.fileSizeKey]).fileSize == size else {
                throw AppUpdateService.Failure.invalidDownload
            }

            let handle = try FileHandle(forReadingFrom: file)
            defer { try? handle.close() }
            var hash = SHA256()
            while let chunk = try handle.read(upToCount: 1024 * 1024), !chunk.isEmpty {
                try Task.checkCancellation()
                hash.update(data: chunk)
            }
            let actual = hash.finalize().map { String(format: "%02x", $0) }.joined()
            guard actual == sha256 else {
                throw AppUpdateService.Failure.invalidDownload
            }
        }
    }
}

enum AppUpdateService {
    static let releasesURL = URL(string: "https://github.com/himomohi/AirTranslate/releases")!
    private static let latestURL = URL(string: "https://api.github.com/repos/himomohi/AirTranslate/releases/latest")!
    private static let assetHosts: Set<String> = ["release-assets.githubusercontent.com", "objects.githubusercontent.com"]
    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        configuration.urlCredentialStorage = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 300
        return URLSession(configuration: configuration, delegate: GitHubRedirects(), delegateQueue: nil)
    }()

    enum Failure: Error {
        case invalidVersion
        case invalidResponse
        case invalidDownload
    }

    static func check(installedVersion: String?) async throws -> AppUpdateRelease? {
        guard let installedVersion, versionParts(installedVersion) != nil else { throw Failure.invalidVersion }
        var request = URLRequest(url: latestURL, timeoutInterval: 15)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200, response.url == latestURL else {
            throw Failure.invalidResponse
        }
        return try availableRelease(in: data, installedVersion: installedVersion)
    }

    static func availableRelease(in data: Data, installedVersion: String) throws -> AppUpdateRelease? {
        let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
        guard !release.draft, !release.prerelease else { return nil }
        let version = String(release.tag_name.dropFirst())
        guard let installed = versionParts(installedVersion), release.tag_name.hasPrefix("v"),
              let latest = versionParts(version) else { throw Failure.invalidVersion }
        guard installed.lexicographicallyPrecedes(latest) else { return nil }

        let name = "AirTranslate-\(version).dmg"
        let url = releasesURL.appending(path: "download/\(release.tag_name)/\(name)")
        let diskImage = release.assets.lazy.compactMap { asset -> AppUpdateRelease.DiskImage? in
            guard asset.name == name, asset.state == "uploaded", (1...1_073_741_824).contains(asset.size),
                  asset.browser_download_url == url.absoluteString,
                  let digest = asset.digest, digest.hasPrefix("sha256:") else { return nil }
            let hash = digest.dropFirst("sha256:".count)
            guard hash.utf8.count == 64, hash.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }) else {
                return nil
            }
            return AppUpdateRelease.DiskImage(url: url, size: asset.size, sha256: String(hash))
        }.first

        return AppUpdateRelease(
            version: version,
            notesURL: releasesURL.appending(path: "tag/\(release.tag_name)"),
            diskImage: diskImage
        )
    }

    @concurrent
    static func download(_ diskImage: AppUpdateRelease.DiskImage) async throws -> URL {
        let (file, response) = try await session.download(from: diskImage.url)
        let fileManager = FileManager.default
        defer { try? fileManager.removeItem(at: file) }
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw Failure.invalidResponse }
        try diskImage.verify(file: file)
        try Task.checkCancellation()

        let directory = fileManager.temporaryDirectory.appending(path: "AirTranslate-Update-\(UUID().uuidString)")
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        var destination = directory.appending(path: diskImage.url.lastPathComponent)
        do {
            try fileManager.moveItem(at: file, to: destination)
            // Finder와 Gatekeeper가 웹에서 받은 파일로 처리할 수 있게 한다.
            var values = URLResourceValues()
            values.quarantineProperties = [
                kLSQuarantineTypeKey as String: kLSQuarantineTypeWebDownload,
                kLSQuarantineDataURLKey as String: diskImage.url,
                kLSQuarantineOriginURLKey as String: releasesURL
            ]
            try destination.setResourceValues(values)
        } catch {
            try? fileManager.removeItem(at: directory)
            throw error
        }
        return destination
    }

    private static func versionParts(_ version: String) -> [Int]? {
        let parts = version.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3 else { return nil }
        let numbers = parts.compactMap { part -> Int? in
            guard let number = Int(part), number >= 0, String(number) == part else { return nil }
            return number
        }
        return numbers.count == parts.count ? numbers : nil
    }

    private final class GitHubRedirects: NSObject, URLSessionTaskDelegate {
        func urlSession(
            _ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
            newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void
        ) {
            guard task.originalRequest?.url?.host() == "github.com", let url = request.url,
                  url.scheme == "https", url.user == nil, url.password == nil, url.port == nil,
                  let host = url.host(), AppUpdateService.assetHosts.contains(host) else {
                completionHandler(nil)
                return
            }
            completionHandler(request)
        }
    }

    private struct GitHubRelease: Decodable {
        let tag_name: String
        let draft: Bool
        let prerelease: Bool
        let assets: [Asset]

        struct Asset: Decodable {
            let name: String
            let state: String
            let size: Int
            let digest: String?
            let browser_download_url: String
        }
    }
}
