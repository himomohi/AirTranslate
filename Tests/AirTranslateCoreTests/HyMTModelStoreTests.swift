import CryptoKit
import Darwin
import Foundation
import Testing
@testable import AirTranslate

@Suite("Hy-MT2 local model installation")
struct HyMTModelStoreTests {
    @Test func manifestPinsOfficialWeightsAndCredentialFreeDownload() throws {
        #expect(HyMTModelStore.revision == "a0c709d9fac510f2c807aa3af52872340dc37a4a")
        #expect(HyMTModelStore.totalBytes == 1_133_080_448)
        #expect(HyMTModelStore.manifest.sha256 == "dc5f44fcf1fa496ee7ad725982c0c8c553a4de00259b53af84c4b89fb0c06699")
        let request = try HyMTModelStore.downloadRequest()
        #expect(request.url?.absoluteString == "https://huggingface.co/tencent/Hy-MT2-1.8B-GGUF/resolve/a0c709d9fac510f2c807aa3af52872340dc37a4a/Hy-MT2-1.8B-Q4_K_M.gguf")
        #expect(request.httpMethod == "GET")
        #expect(request.httpBody == nil)
        #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
        #expect(request.value(forHTTPHeaderField: "Accept-Encoding") == "identity")
    }

    @Test func verifiesStagingAndReusesInstalledWeights() async throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let bytes = Data("GGUF fixture weights".utf8)
        let client = HyMTFixtureDownloadClient(data: bytes)
        let store = fixtureStore(root, bytes: bytes, client: client)
        #expect(try await store.installedModel() == nil)
        let progress = HyMTProgressRecorder()
        let result = try await store.install { progress.append($0) }
        #expect(result == root.appendingPathComponent("model/weights.gguf"))
        #expect(try Data(contentsOf: result) == bytes)
        #expect(try await store.installedModel() == result)
        #expect(try await store.install() == result)
        #expect(await client.requestCount == 1)
        #expect(progress.values.first == 0)
        #expect(progress.values.last == 1)
        #expect(progress.values.allSatisfy { (0...1).contains($0) })
        #expect(try FileManager.default.contentsOfDirectory(atPath: root.path) == ["model"])
    }

    @Test func sameSizeTamperingInvalidatesVerificationCache() async throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let bytes = Data("correct".utf8)
        let store = fixtureStore(root, bytes: bytes)
        let result = try await store.install()
        #expect(try await store.installedModel() == result)
        try Data("changed".utf8).write(to: result)
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(5)], ofItemAtPath: result.path)
        #expect(try await store.installedModel() == nil)
    }

    @Test func replacedInodeCannotReusePriorHash() async throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let bytes = Data("correct".utf8)
        let store = fixtureStore(root, bytes: bytes)
        let result = try await store.install()
        let originalDate = try #require(FileManager.default.attributesOfItem(atPath: result.path)[.modificationDate] as? Date)
        let replacement = root.appendingPathComponent("replacement")
        try Data("changed".utf8).write(to: replacement)
        try FileManager.default.setAttributes([.modificationDate: originalDate], ofItemAtPath: replacement.path)
        try FileManager.default.removeItem(at: result)
        try FileManager.default.moveItem(at: replacement, to: result)
        #expect(try await store.installedModel() == nil)
    }

    @Test func hashFailurePreservesPreviousDirectoryAndCleansStaging() async throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let previous = try createPreviousInstallation(root)
        let expected = Data("new".utf8)
        let store = fixtureStore(root, bytes: expected, client: HyMTFixtureDownloadClient(data: Data("bad".utf8)))
        await #expect(throws: HyMTModelStoreError.verificationFailed) { try await store.install() }
        #expect(try Data(contentsOf: previous) == Data("previous model".utf8))
        #expect(try FileManager.default.contentsOfDirectory(atPath: root.path) == ["model"])
    }

    @Test func wrongSizeCannotBecomeInstalled() async throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = fixtureStore(root, bytes: Data("expected".utf8), client: HyMTFixtureDownloadClient(data: Data("short".utf8)))
        await #expect(throws: HyMTModelStoreError.verificationFailed) { try await store.install() }
        #expect(try await store.installedModel() == nil)
        #expect(try FileManager.default.contentsOfDirectory(atPath: root.path).isEmpty)
    }

    @Test func cancellationPreservesPreviousAndRemovesPartialDownload() async throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let previous = try createPreviousInstallation(root)
        let bytes = Data("new weights".utf8)
        let client = HyMTFixtureDownloadClient(data: bytes, waitsForCancellation: true)
        let store = fixtureStore(root, bytes: bytes, client: client)
        let task = Task { try await store.install() }
        defer { task.cancel() }
        try await client.waitUntilStarted()
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(try Data(contentsOf: previous) == Data("previous model".utf8))
        #expect(try FileManager.default.contentsOfDirectory(atPath: root.path) == ["model"])
    }

    @Test func installAndRemoveAreExclusiveAcrossInstances() async throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let bytes = Data("weights".utf8)
        let client = HyMTFixtureDownloadClient(data: bytes, waitsForCancellation: true)
        let first = fixtureStore(root, bytes: bytes, client: client)
        let second = fixtureStore(root, bytes: bytes)
        let task = Task { try await first.install() }
        defer { task.cancel() }
        try await client.waitUntilStarted()
        await #expect(throws: HyMTModelStoreError.operationInProgress) { try await second.install() }
        await #expect(throws: HyMTModelStoreError.operationInProgress) { try await second.remove() }
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
        let installed = try await second.install()
        #expect(try Data(contentsOf: installed) == bytes)
        try await second.remove()
        #expect(try await second.installedModel() == nil)
        try await second.remove()
    }

    @Test func missingSpaceFailsBeforeTransport() async throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let bytes = Data("weights".utf8)
        let client = HyMTFixtureDownloadClient(data: bytes)
        let store = HyMTModelStore(directory: root.appendingPathComponent("model"), manifest: entry(bytes), client: client,
                                  availableCapacity: { _ in HyMTModelStore.minimumFreeDiskBytes - 1 })
        await #expect(throws: HyMTModelStoreError.insufficientDiskSpace) { try await store.install() }
        #expect(await client.requestCount == 0)
    }

    @Test func traversalAndInvalidManifestFailBeforeTransport() async throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let bytes = Data("weights".utf8)
        let client = HyMTFixtureDownloadClient(data: bytes)
        for path in ["../weights", "/weights", "a//b", "a/./b", "a/%2e%2e/b", "a\\b"] {
            let file = EmbeddingGemmaModelFile(relativePath: path, byteCount: Int64(bytes.count), sha256: entry(bytes).sha256)
            let store = HyMTModelStore(directory: root.appendingPathComponent("model"), manifest: file, client: client)
            await #expect(throws: HyMTModelStoreError.invalidPath) { try await store.install() }
        }
        let invalid = EmbeddingGemmaModelFile(relativePath: "weights", byteCount: 0, sha256: "invalid")
        let store = HyMTModelStore(directory: root.appendingPathComponent("model"), manifest: invalid, client: client)
        await #expect(throws: HyMTModelStoreError.invalidManifest) { try await store.install() }
        #expect(await client.requestCount == 0)
        #expect(!FileManager.default.fileExists(atPath: root.path))
    }

    @Test func symbolicLinkFileIsNeverRecognizedAsInstalled() async throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let directory = root.appendingPathComponent("model")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let bytes = Data("weights".utf8)
        let outside = root.appendingPathComponent("outside")
        try bytes.write(to: outside)
        try FileManager.default.createSymbolicLink(at: directory.appendingPathComponent("weights.gguf"), withDestinationURL: outside)
        let store = fixtureStore(root, bytes: bytes)
        #expect(try await store.installedModel() == nil)
        try await store.remove()
        #expect(try Data(contentsOf: outside) == bytes)
    }

    @Test func symbolicLinkParentCannotRedirectInstallationOrRemoval() async throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let outside = root.appendingPathComponent("outside")
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        let alias = root.appendingPathComponent("alias")
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: outside)
        let bytes = Data("weights".utf8)
        let client = HyMTFixtureDownloadClient(data: bytes)
        let store = HyMTModelStore(directory: alias.appendingPathComponent("model"), manifest: entry(bytes), client: client)
        await #expect(throws: HyMTModelStoreError.invalidPath) { try await store.install() }
        await #expect(throws: HyMTModelStoreError.invalidPath) { try await store.remove() }
        #expect(await client.requestCount == 0)
        #expect(try FileManager.default.contentsOfDirectory(atPath: outside.path).isEmpty)
    }

    @Test func installedCheckPropagatesCancellation() async throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let bytes = Data("weights".utf8)
        let store = fixtureStore(root, bytes: bytes)
        _ = try await store.install()
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await store.installedModel()
        }
        await #expect(throws: CancellationError.self) { try await task.value }
    }

    private func fixtureStore(_ root: URL, bytes: Data, client: HyMTFixtureDownloadClient? = nil) -> HyMTModelStore {
        HyMTModelStore(directory: root.appendingPathComponent("model"), manifest: entry(bytes),
                       client: client ?? HyMTFixtureDownloadClient(data: bytes),
                       availableCapacity: { _ in HyMTModelStore.minimumFreeDiskBytes })
    }

    private func entry(_ bytes: Data) -> EmbeddingGemmaModelFile {
        .init(relativePath: "weights.gguf", byteCount: Int64(bytes.count),
              sha256: SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined())
    }

    private func temporaryRoot() -> URL {
        // Foundation의 resolvingSymlinksInPath는 /private 접두사를 다시 줄일 수 있다.
        let temporaryPath = FileManager.default.temporaryDirectory.path
        let resolved = temporaryPath.withCString { realpath($0, nil) }
        defer { free(resolved) }
        let canonical = resolved.map { String(cString: $0) } ?? temporaryPath
        return URL(fileURLWithPath: canonical, isDirectory: true)
            .appendingPathComponent("HyMTModelTests-\(UUID().uuidString)", isDirectory: true)
    }

    private func createPreviousInstallation(_ root: URL) throws -> URL {
        let directory = root.appendingPathComponent("model")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let marker = directory.appendingPathComponent("previous")
        try Data("previous model".utf8).write(to: marker)
        return marker
    }
}

private actor HyMTFixtureDownloadClient: EmbeddingGemmaModelDownloadClient {
    let data: Data
    let waitsForCancellation: Bool
    private(set) var requestCount = 0
    private var started = false

    init(data: Data, waitsForCancellation: Bool = false) {
        self.data = data
        self.waitsForCancellation = waitsForCancellation
    }

    func download(_ request: URLRequest, to destination: URL, expectedByteCount: Int64,
                  progress: @escaping @Sendable (Int64) -> Void) async throws {
        requestCount += 1
        try data.write(to: destination)
        progress(Int64(data.count))
        started = true
        if waitsForCancellation { try await Task.sleep(for: .seconds(60)) }
        try Task.checkCancellation()
    }

    func waitUntilStarted() async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while !started {
            guard ContinuousClock.now < deadline else { throw HyMTFixtureError.downloadNeverStarted }
            try await Task.sleep(for: .milliseconds(5))
        }
    }
}

private enum HyMTFixtureError: Error { case downloadNeverStarted }

private final class HyMTProgressRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [Double] = []
    var values: [Double] { lock.withLock { recorded } }
    func append(_ value: Double) { lock.withLock { recorded.append(value) } }
}
