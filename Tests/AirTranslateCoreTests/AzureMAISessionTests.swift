import Foundation
import Testing
@testable import AirTranslate

@Suite(.serialized)
@MainActor
struct AzureMAISessionTests {
    @Test(arguments: [false, true])
    func systemStopPreservesFinalTranscriptAndDrainsTranslations(repeatedStop: Bool) async throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        let session = fixture.session
        let generation = session.activateLiveCallbackPipelineForTesting().generation
        session.deliverAzureTranscriptForTesting("First.", isFinal: true, generation: generation)
        session.deliverAzureTranscriptForTesting("Last draft", isFinal: false, generation: generation)

        session.stopAzureFromSystemMenuForTesting(generation: generation)
        if repeatedStop {
            session.stopAzureFromSystemMenuForTesting(generation: generation)
            session.stop()
        }
        #expect(session.isRunning && session.isFinishingAzureMAI)

        // 캡처가 끝난 뒤 제공자가 확정하는 마지막 문장도 같은 세대에서 받는다.
        session.deliverAzureTranscriptForTesting("Last.", isFinal: true, generation: generation)
        #expect(await waitUntil { !session.isRunning })
        #expect(!session.isFinishingAzureMAI)
        #expect(session.lines.map(\.sourceText) == ["First.", "Last."])
        #expect(session.lines.map(\.isFinal) == [true, true])
        #expect(session.lines.map(\.translatedText) == ["첫 문장.", "마지막 문장."])

        let files = try FileManager.default.contentsOfDirectory(at: fixture.directory, includingPropertiesForKeys: nil)
        let original = try #require(files.first { $0.lastPathComponent.contains("original") })
        let translated = try #require(files.first { $0.lastPathComponent.contains("translation") })
        #expect(try String(contentsOf: original, encoding: .utf8) == "First.\nLast.")
        #expect(try String(contentsOf: translated, encoding: .utf8) == "첫 문장.\n마지막 문장.")

        session.deliverAzureTranscriptForTesting("stale", isFinal: true, generation: generation)
        session.stopAzureFromSystemMenuForTesting(generation: generation)
        #expect(session.lines.map(\.sourceText) == ["First.", "Last."])
        #expect(!session.isRunning && !session.isFinishingAzureMAI)
    }

    @Test
    func staleSystemStopDoesNotFinishCurrentAzureSession() async throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        let session = fixture.session
        let oldGeneration = session.activateLiveCallbackPipelineForTesting().generation
        let generation = session.activateLiveCallbackPipelineForTesting().generation

        session.stopAzureFromSystemMenuForTesting(generation: oldGeneration)
        #expect(session.isRunning && !session.isFinishingAzureMAI)
        session.deliverAzureTranscriptForTesting("Last.", isFinal: true, generation: generation)
        #expect(session.lines.last?.sourceText == "Last.")

        session.stopAzureFromSystemMenuForTesting(generation: generation)
        #expect(await waitUntil { !session.isRunning })
        #expect(session.lines.last?.translatedText == "마지막 문장.")
    }

    @Test
    func normalStopSavesEveryFinalTranslationAndExcludesUnfinishedDraft() async throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        let session = fixture.session
        let generation = session.activateLiveCallbackPipelineForTesting().generation
        session.deliverAzureTranscriptForTesting("First.", isFinal: true, generation: generation)
        session.deliverAzureTranscriptForTesting("Last.", isFinal: true, generation: generation)
        session.deliverAzureTranscriptForTesting("Unfinished draft", isFinal: false, generation: generation)
        session.stop()
        #expect(await waitUntil { !session.isRunning })

        let files = try FileManager.default.contentsOfDirectory(at: fixture.directory, includingPropertiesForKeys: nil)
        let original = try #require(files.first { $0.lastPathComponent.contains("original") })
        let translated = try #require(files.first { $0.lastPathComponent.contains("translation") })
        #expect(try String(contentsOf: original, encoding: .utf8) == "First.\nLast.")
        #expect(try String(contentsOf: translated, encoding: .utf8) == "첫 문장.\n마지막 문장.")
    }

    private struct Fixture {
        let session: TranslationSessionStore
        let defaults: UserDefaults
        let name: String
        let directory: URL

        @MainActor
        func cleanup() {
            session.finishAzurePipelineForTesting()
            defaults.removePersistentDomain(forName: name)
            try? FileManager.default.removeItem(at: directory)
        }
    }

    private func makeFixture() throws -> Fixture {
        let name = "AzureMAISessionTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let session = TranslationSessionStore(modelAvailabilityProvider: { _, _ in [:] },
            settingsDefaults: defaults, transcriptsDirectoryURL: directory)
        session.sourceLanguage = .english
        session.targetLanguage = .korean
        session.useAzureMAIMode()
        session.useTranslationMode()
        session.isDubbingEnabled = false
        session.isTranscriptPersistenceEnabled = true
        session.savedTranscriptContentMode = .originalAndTranslation
        session.azureTranslationForTesting = { text in
            try await Task.sleep(for: .milliseconds(30))
            return text == "First." ? "첫 문장." : "마지막 문장."
        }
        return Fixture(session: session, defaults: defaults, name: name, directory: directory)
    }

    private func waitUntil(_ condition: @MainActor () -> Bool) async -> Bool {
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while !condition(), ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(10))
        }
        return condition()
    }
}
