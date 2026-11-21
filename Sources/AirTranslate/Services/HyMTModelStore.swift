import CryptoKit
import Foundation

actor HyMTModelStore {
    static let shared = HyMTModelStore()
    nonisolated static let revision = "a0c709d9fac510f2c807aa3af52872340dc37a4a"
    nonisolated static let repository = "tencent/Hy-MT2-1.8B-GGUF"
    nonisolated static let modelFileName = "Hy-MT2-1.8B-Q4_K_M.gguf"
    nonisolated static let totalBytes: Int64 = 1_133_080_448
    nonisolated static let minimumFreeDiskBytes: Int64 = 2_500_000_000
    nonisolated static let manifest = EmbeddingGemmaModelFile(
        relativePath: modelFileName, byteCount: totalBytes,
        sha256: "dc5f44fcf1fa496ee7ad725982c0c8c553a4de00259b53af84c4b89fb0c06699"
    )
    nonisolated static let modelDirectory: URL = {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AirTranslate/Models/HyMT2", isDirectory: true)
            .appendingPathComponent(revision, isDirectory: true)
    }()

    private let directory: URL
    private let file: EmbeddingGemmaModelFile
    private let client: any EmbeddingGemmaModelDownloadClient
    private let availableCapacity: @Sendable (URL) throws -> Int64
    private var verifiedFingerprint: FileFingerprint?

    init(
        directory: URL = HyMTModelStore.modelDirectory,
        manifest: EmbeddingGemmaModelFile = HyMTModelStore.manifest,
        client: any EmbeddingGemmaModelDownloadClient = HyMTModelURLSessionClient(),
        availableCapacity: @escaping @Sendable (URL) throws -> Int64 = { location in
            let values = try location.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
            if let available = values.volumeAvailableCapacityForImportantUsage { return available }
            let attributes = try FileManager.default.attributesOfFileSystem(forPath: location.path)
            return (attributes[.systemFreeSize] as? NSNumber)?.int64Value ?? 0
        }
    ) {
        // Foundation의 표준화는 /private/var를 /var로 바꾸므로 실제 경로를 보존한다.
        self.directory = directory
        self.file = manifest
        self.client = client
        self.availableCapacity = availableCapacity
    }

    func installedModel() async throws -> URL? {
        do {
            try Task.checkCancellation()
            try validateManifest()
            let url = try Self.fileURL(for: file.relativePath, inside: directory)
            let fingerprint = try Self.fingerprint(of: url, expectedSize: file.byteCount)
            if verifiedFingerprint != fingerprint {
                try Self.verify(file, inside: directory)
                guard try Self.fingerprint(of: url, expectedSize: file.byteCount) == fingerprint else {
                    throw HyMTModelStoreError.verificationFailed
                }
                verifiedFingerprint = fingerprint
            }
            return url
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            verifiedFingerprint = nil
            return nil
        }
    }

    func install(progress: @escaping @Sendable (Double) -> Void = { _ in }) async throws -> URL {
        try Task.checkCancellation()
        let key = directory.resolvingSymlinksInPath().path
        guard await HyMTModelMutationCoordinator.shared.acquire(key) else { throw HyMTModelStoreError.operationInProgress }
        do {
            let result = try await installExclusively(progress: progress)
            await HyMTModelMutationCoordinator.shared.release(key)
            return result
        } catch {
            await HyMTModelMutationCoordinator.shared.release(key)
            throw error
        }
    }

    func remove() async throws {
        try Task.checkCancellation()
        let key = directory.resolvingSymlinksInPath().path
        guard await HyMTModelMutationCoordinator.shared.acquire(key) else { throw HyMTModelStoreError.operationInProgress }
        do {
            try Task.checkCancellation()
            try validateManifest()
            try Self.rejectSymbolicLinks(in: directory)
            if FileManager.default.fileExists(atPath: directory.path) {
                try FileManager.default.removeItem(at: directory)
            }
            verifiedFingerprint = nil
            await HyMTModelMutationCoordinator.shared.release(key)
        } catch {
            await HyMTModelMutationCoordinator.shared.release(key)
            throw error
        }
    }

    private func installExclusively(progress: @escaping @Sendable (Double) -> Void) async throws -> URL {
        try Task.checkCancellation()
        try validateManifest()
        try Self.rejectSymbolicLinks(in: directory)
        if let installed = try await installedModel() {
            progress(1)
            return installed
        }
        let manager = FileManager.default
        let parent = directory.deletingLastPathComponent()
        try manager.createDirectory(at: parent, withIntermediateDirectories: true)
        try Self.rejectSymbolicLinks(in: parent)
        guard try availableCapacity(parent) >= Self.minimumFreeDiskBytes else {
            throw HyMTModelStoreError.insufficientDiskSpace
        }
        let staging = parent.appendingPathComponent(".hymt-download-\(UUID().uuidString)", isDirectory: true)
        try manager.createDirectory(at: staging, withIntermediateDirectories: false)
        defer { try? manager.removeItem(at: staging) }
        let destination = try Self.fileURL(for: file.relativePath, inside: staging)
        try manager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        let expected = file.byteCount
        progress(0)
        try await client.download(try Self.downloadRequest(for: file.relativePath), to: destination, expectedByteCount: expected) { bytes in
            progress(min(0.99, Double(max(0, min(bytes, expected))) / Double(expected)))
        }
        try Task.checkCancellation()
        try Self.verify(file, inside: staging)
        try Task.checkCancellation()
        try Self.rejectSymbolicLinks(in: directory)

        // 모델 검증 후 교체하며, 실패하면 이전 설치를 복구한다.
        let backup = parent.appendingPathComponent(".hymt-previous-\(UUID().uuidString)", isDirectory: true)
        let hadPrevious = manager.fileExists(atPath: directory.path)
        if hadPrevious { try manager.moveItem(at: directory, to: backup) }
        do {
            try manager.moveItem(at: staging, to: directory)
        } catch {
            if hadPrevious { try? manager.moveItem(at: backup, to: directory) }
            throw error
        }
        if hadPrevious { try? manager.removeItem(at: backup) }
        let installed = try Self.fileURL(for: file.relativePath, inside: directory)
        verifiedFingerprint = try Self.fingerprint(of: installed, expectedSize: expected)
        progress(1)
        return installed
    }

    private func validateManifest() throws {
        guard directory.isFileURL, !directory.path.isEmpty, directory.path != "/",
              file.byteCount > 0, file.sha256.count == 64,
              file.sha256.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }) else {
            throw HyMTModelStoreError.invalidManifest
        }
        _ = try Self.fileURL(for: file.relativePath, inside: directory)
    }

    nonisolated static func fileURL(for path: String, inside root: URL) throws -> URL {
        let components = path.split(separator: "/", omittingEmptySubsequences: false)
        guard !components.isEmpty, components.allSatisfy({ component in
            !component.isEmpty && component != "." && component != ".." && component.utf8.allSatisfy {
                (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0)
                    || $0 == 45 || $0 == 46 || $0 == 95
            }
        }) else { throw HyMTModelStoreError.invalidPath }
        return components.reduce(root) { $0.appendingPathComponent(String($1)) }
    }

    nonisolated static func downloadRequest(for path: String = modelFileName) throws -> URLRequest {
        let base = URL(string: "https://huggingface.co/\(repository)/resolve/\(revision)")!
        var request = URLRequest(url: try fileURL(for: path, inside: base))
        request.httpMethod = "GET"
        request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
        request.cachePolicy = .reloadIgnoringLocalCacheData
        return request
    }

    private struct FileFingerprint: Equatable {
        let size: Int64
        let modificationDate: Date
        let inode: UInt64
        let device: UInt64
    }

    nonisolated private static func rejectSymbolicLinks(in url: URL) throws {
        let components = url.path.split(separator: "/", omittingEmptySubsequences: true)
        guard url.isFileURL, url.path.hasPrefix("/"),
              components.allSatisfy({ $0 != "." && $0 != ".." }) else {
            throw HyMTModelStoreError.invalidPath
        }
        // URL 루트의 parent 비교 대신 유한한 구성요소를 순회한다.
        var current = ""
        for component in components {
            current += "/" + component
            do {
                let attributes = try FileManager.default.attributesOfItem(atPath: current)
                guard attributes[.type] as? FileAttributeType != .typeSymbolicLink else {
                    throw HyMTModelStoreError.invalidPath
                }
            } catch let error as NSError where error.domain == NSCocoaErrorDomain && [NSFileNoSuchFileError, NSFileReadNoSuchFileError].contains(error.code) {
                // 아직 없는 설치 디렉터리도 기존 상위 경로는 끝까지 확인한다.
            }
        }
    }

    nonisolated private static func fingerprint(of url: URL, expectedSize: Int64) throws -> FileFingerprint {
        try rejectSymbolicLinks(in: url)
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        guard attributes[.type] as? FileAttributeType == .typeRegular,
              let size = (attributes[.size] as? NSNumber)?.int64Value, size == expectedSize,
              let date = attributes[.modificationDate] as? Date,
              let inode = (attributes[.systemFileNumber] as? NSNumber)?.uint64Value,
              let device = (attributes[.systemNumber] as? NSNumber)?.uint64Value else {
            throw HyMTModelStoreError.verificationFailed
        }
        return FileFingerprint(size: size, modificationDate: date, inode: inode, device: device)
    }

    nonisolated private static func verify(_ file: EmbeddingGemmaModelFile, inside directory: URL) throws {
        let url = try fileURL(for: file.relativePath, inside: directory)
        let before = try fingerprint(of: url, expectedSize: file.byteCount)
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hash = SHA256()
        while let chunk = try handle.read(upToCount: 1_048_576), !chunk.isEmpty {
            try Task.checkCancellation()
            hash.update(data: chunk)
        }
        try Task.checkCancellation()
        let digest = hash.finalize().map { String(format: "%02x", $0) }.joined()
        guard digest == file.sha256, try fingerprint(of: url, expectedSize: file.byteCount) == before else {
            throw HyMTModelStoreError.verificationFailed
        }
    }
}

enum HyMTModelStoreError: Error, Equatable, LocalizedError {
    case invalidManifest
    case invalidPath
    case verificationFailed
    case downloadFailed(Int)
    case invalidResponse
    case operationInProgress
    case insufficientDiskSpace

    var errorDescription: String? {
        switch self {
        case .invalidManifest, .invalidPath:
            AppText.localized(english: "The Hy-MT2 model location or file list is invalid.", korean: "Hy-MT2 모델 경로나 파일 정보가 올바르지 않습니다.")
        case .verificationFailed:
            AppText.localized(english: "Hy-MT2 model verification failed. Download the model again.", korean: "Hy-MT2 모델 무결성 확인에 실패했습니다. 모델을 다시 다운로드하세요.")
        case .downloadFailed, .invalidResponse:
            AppText.localized(english: "The Hy-MT2 model download failed. Check the connection and try again.", korean: "Hy-MT2 모델 다운로드에 실패했습니다. 연결을 확인하고 다시 시도하세요.")
        case .operationInProgress:
            AppText.localized(english: "Another Hy-MT2 model operation is running.", korean: "다른 Hy-MT2 모델 작업이 진행 중입니다.")
        case .insufficientDiskSpace:
            AppText.localized(english: "At least 2.5 GB of free space is required to install Hy-MT2.", korean: "Hy-MT2를 설치하려면 여유 공간이 2.5GB 이상 필요합니다.")
        }
    }
}

private actor HyMTModelMutationCoordinator {
    static let shared = HyMTModelMutationCoordinator()
    private var activePaths: Set<String> = []
    func acquire(_ path: String) -> Bool { activePaths.insert(path).inserted }
    func release(_ path: String) { activePaths.remove(path) }
}

struct HyMTModelURLSessionClient: EmbeddingGemmaModelDownloadClient {
    func download(_ request: URLRequest, to destination: URL, expectedByteCount: Int64,
                  progress: @escaping @Sendable (Int64) -> Void) async throws {
        let operation = HyMTModelDownloadOperation(destination: destination, expectedByteCount: expectedByteCount, progress: progress)
        try await withTaskCancellationHandler {
            try Task.checkCancellation()
            try await operation.run(request)
        } onCancel: { operation.cancel() }
    }
}

private final class HyMTModelDownloadOperation: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private let destination: URL
    private let expectedByteCount: Int64
    private let progress: @Sendable (Int64) -> Void
    private var continuation: CheckedContinuation<Void, any Error>?
    private var session: URLSession?
    private var task: URLSessionDownloadTask?
    private var isCancelled = false
    private var terminalError: Error?
    private var lastProgressUptime: TimeInterval = 0

    init(destination: URL, expectedByteCount: Int64, progress: @escaping @Sendable (Int64) -> Void) {
        self.destination = destination
        self.expectedByteCount = expectedByteCount
        self.progress = progress
    }

    func run(_ request: URLRequest) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            let download: URLSessionDownloadTask? = lock.withLock {
                guard !isCancelled else { continuation.resume(throwing: CancellationError()); return nil }
                self.continuation = continuation
                let configuration = URLSessionConfiguration.ephemeral
                configuration.urlCache = nil
                configuration.urlCredentialStorage = nil
                configuration.httpCookieStorage = nil
                configuration.httpShouldSetCookies = false
                configuration.timeoutIntervalForRequest = 60
                configuration.timeoutIntervalForResource = 3_600
                let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
                self.session = session
                let download = session.downloadTask(with: request)
                self.task = download
                return download
            }
            download?.resume()
        }
    }

    func cancel() {
        let download = lock.withLock { isCancelled = true; return task }
        download?.cancel()
    }

    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        guard let url = request.url, let host = url.host?.lowercased(), url.scheme == "https",
              url.user == nil, url.password == nil,
              host == "huggingface.co" || host.hasSuffix(".huggingface.co") || host == "hf.co" || host.hasSuffix(".hf.co") else {
            completionHandler(nil)
            return
        }
        completionHandler(request)
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard !lock.withLock({ isCancelled }) else { return }
        guard totalBytesWritten <= expectedByteCount else {
            lock.withLock { terminalError = HyMTModelStoreError.verificationFailed }
            downloadTask.cancel()
            return
        }
        let now = ProcessInfo.processInfo.systemUptime
        if now - lastProgressUptime >= 0.1 || totalBytesWritten == expectedByteCount {
            lastProgressUptime = now
            progress(totalBytesWritten)
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        do {
            if lock.withLock({ isCancelled }) { throw CancellationError() }
            guard let response = downloadTask.response as? HTTPURLResponse else { throw HyMTModelStoreError.invalidResponse }
            guard response.statusCode == 200 else { throw HyMTModelStoreError.downloadFailed(response.statusCode) }
            let size = try location.resourceValues(forKeys: [.fileSizeKey]).fileSize
            guard Int64(size ?? -1) == expectedByteCount else { throw HyMTModelStoreError.verificationFailed }
            try FileManager.default.moveItem(at: location, to: destination)
        } catch { lock.withLock { terminalError = error } }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        let result: (CheckedContinuation<Void, any Error>?, Error?) = lock.withLock {
            let continuation = self.continuation
            self.continuation = nil
            self.task = nil
            self.session = nil
            return (continuation, isCancelled ? CancellationError() : (terminalError ?? error))
        }
        session.finishTasksAndInvalidate()
        if let error = result.1 { result.0?.resume(throwing: error) }
        else { result.0?.resume() }
    }
}
