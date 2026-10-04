import CoreMedia
import Foundation
import Testing
@testable import AirTranslate

@MainActor
private final class ControlledScheduledTranslator {
    struct Call {
        let invocation: TranslationInvocationForTesting
        var continuation: CheckedContinuation<String, Error>?
        var cancellationObserved = false
    }

    let cooperatesWithCancellation: Bool
    private(set) var calls: [Call] = []
    private(set) var activeCount = 0
    private(set) var maximumActiveCount = 0

    init(cooperatesWithCancellation: Bool) {
        self.cooperatesWithCancellation = cooperatesWithCancellation
    }

    func translate(_ invocation: TranslationInvocationForTesting) async throws -> String {
        let index = calls.count
        calls.append(Call(invocation: invocation))
        activeCount += 1
        maximumActiveCount = max(maximumActiveCount, activeCount)
        defer { activeCount -= 1 }
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                calls[index].continuation = continuation
            }
        } onCancel: {
            Task { @MainActor in
                self.calls[index].cancellationObserved = true
                if self.cooperatesWithCancellation {
                    self.complete(index, with: .failure(CancellationError()))
                }
            }
        }
    }

    func complete(_ index: Int, with result: Result<String, Error>) {
        guard calls.indices.contains(index), let continuation = calls[index].continuation else { return }
        calls[index].continuation = nil
        continuation.resume(with: result)
    }

    func publish(_ text: String, from index: Int) {
        calls[index].invocation.progress(text)
    }

    func releaseAll() {
        for index in calls.indices {
            complete(index, with: .failure(CancellationError()))
        }
    }
}

private struct SchedulingEvent {
    let stage: String
    let id: UUID
    let values: [String: Double]
}

@MainActor
private final class SchedulingEventRecorder {
    var events: [SchedulingEvent] = []
}

private enum DelayedSchedulingError: LocalizedError {
    case previousSession

    var errorDescription: String? { "Previous translation failed." }
}

@Suite
@MainActor
struct TranslationSchedulingTests {
    @Test
    func identicalPartialAndFinalReuseOneTranslationAndIdenticalResultDoesNotReapply() async throws {
        let fixture = makeFixture(cooperatesWithCancellation: true)
        defer { fixture.cleanup() }
        let session = fixture.session
        let source = "An unchanged complete phrase."
        deliver(source, segment: 1, revision: 1, final: false, to: session)
        #expect(await waitUntil { fixture.translator.calls.count == 1 })
        deliver(source, segment: 1, revision: 2, final: true, to: session)
        #expect(session.lines.last?.isFinal == true)
        #expect(!fixture.translator.calls[0].cancellationObserved)

        fixture.translator.publish("변하지 않은 문장입니다.", from: 0)
        let revisionAfterProgress = session.lines.last?.revision
        fixture.translator.complete(0, with: .success("변하지 않은 문장입니다."))
        #expect(await waitUntil { fixture.recorder.events.contains { $0.stage == "translation.result" } })
        #expect(fixture.translator.calls.count == 1)
        #expect(session.lines.last?.revision == revisionAfterProgress)
        #expect(session.lines.last?.isFinal == true)
        #expect(session.pendingTranslationSourceTextForTesting.isEmpty)
        #expect(fixture.recorder.events.filter { $0.stage == "translation.queued" }.count == 1)
        #expect(fixture.recorder.events.filter { $0.stage == "translation.coalesced_final" }.count == 1)
        #expect(fixture.recorder.events.filter { $0.stage == "translation.apply" }.count == 1)
        assertCompleteEventAccounting(fixture.recorder)
    }

    @Test
    func coalescedFinalSupersedesPendingShorterPartialAndPreservesFinalTranslation() async throws {
        let fixture = makeFixture(cooperatesWithCancellation: true)
        defer { fixture.cleanup() }
        let session = fixture.session
        let source = "Book a flight to Seoul."
        let shorterSource = "Book a flight"
        let finalTranslation = "서울행 항공편을 예약하세요."

        deliver(source, segment: 1, revision: 1, final: false, to: session)
        try #require(await waitUntil { fixture.translator.calls.count == 1 })
        let lineID = try #require(session.lines.last?.id)
        let activeID = try #require(fixture.recorder.events.first { $0.stage == "translation.queued" }?.id)
        deliver(shorterSource, segment: 1, revision: 2, final: false, to: session)
        try #require(await waitUntil {
            fixture.recorder.events.filter { $0.stage == "translation.queued" }.count == 2
        })
        let pendingID = try #require(fixture.recorder.events.last { $0.stage == "translation.queued" }?.id)
        #expect(session.lines.last?.id == lineID)
        #expect(session.pendingTranslationSourceTextForTesting == shorterSource)
        #expect(fixture.translator.calls.count == 1)

        deliver(source, segment: 1, revision: 3, final: true, to: session)
        try #require(fixture.recorder.events.contains {
            $0.id == activeID && $0.stage == "translation.coalesced_final"
        })
        #expect(session.lines.last?.isFinal == true)
        #expect(session.pendingTranslationSourceTextForTesting.isEmpty)
        #expect(!fixture.translator.calls[0].cancellationObserved)
        fixture.translator.complete(0, with: .success(finalTranslation))
        try #require(await waitUntil {
            fixture.recorder.events.contains { $0.id == activeID && $0.stage == "translation.result" }
                && (!terminalEvents(for: pendingID, in: fixture.recorder).isEmpty
                    || fixture.translator.calls.count > 1)
        })

        // 회귀가 있으면 남은 B도 완료시켜 final A의 번역을 덮는지까지 확인한다.
        if let obsoleteCall = fixture.translator.calls.firstIndex(where: { $0.invocation.text == shorterSource }) {
            fixture.translator.complete(obsoleteCall, with: .success("항공편을 예약하세요."))
            try #require(await waitUntil { !terminalEvents(for: pendingID, in: fixture.recorder).isEmpty })
        }

        #expect(fixture.translator.calls.count == 1)
        #expect(fixture.translator.maximumActiveCount == 1)
        #expect(session.lines.last?.id == lineID)
        #expect(session.lines.last?.isFinal == true)
        #expect(session.lines.last?.sourceText == source)
        #expect(session.lines.last?.translatedSourceText == source)
        #expect(session.lines.last?.translatedText == finalTranslation)
        #expect(session.pendingTranslationSourceTextForTesting.isEmpty)
        #expect(terminalEvents(for: pendingID, in: fixture.recorder).map(\.stage) == ["translation.superseded"])
        #expect(!fixture.recorder.events.contains { $0.id == pendingID && $0.stage == "translation.start" })
        assertCompleteEventAccounting(fixture.recorder)
    }

    @Test
    func finalCancelsCooperativePartialAndStartsWithoutWaitingForItsNormalCompletion() async throws {
        let fixture = makeFixture(cooperatesWithCancellation: true)
        defer { fixture.cleanup() }
        let session = fixture.session

        deliver("Book a flight", segment: 1, revision: 1, final: false, to: session)
        #expect(await waitUntil { fixture.translator.calls.count == 1 })
        deliver("Book a flight to Seoul.", segment: 1, revision: 2, final: true, to: session)

        #expect(await waitUntil { fixture.translator.calls.count == 2 })
        #expect(fixture.translator.calls[0].cancellationObserved)
        #expect(fixture.translator.calls[1].invocation.text == "Book a flight to Seoul.")
        #expect(fixture.translator.maximumActiveCount == 1)
        fixture.translator.complete(1, with: .success("서울행 항공편을 예약하세요."))
        #expect(await waitUntil { session.lines.last?.translatedText == "서울행 항공편을 예약하세요." })
        #expect(session.lines.last?.isFinal == true)

        let queued = fixture.recorder.events.filter { $0.stage == "translation.queued" }
        #expect(queued.count == 2)
        let partialID = try #require(queued.first?.id)
        #expect(terminalEvents(for: partialID, in: fixture.recorder).map(\.stage) == ["translation.superseded"])
        #expect(!fixture.recorder.events.contains { $0.id == partialID && $0.stage == "translation.apply" })
        assertCompleteEventAccounting(fixture.recorder)
    }

    @Test
    func uncooperativePartialCannotPublishAfterFinalAndKeepsSingleExecutionSlot() async throws {
        let fixture = makeFixture(cooperatesWithCancellation: false)
        defer { fixture.cleanup() }
        let session = fixture.session

        deliver("A partial phrase", segment: 1, revision: 1, final: false, to: session)
        #expect(await waitUntil { fixture.translator.calls.count == 1 })
        deliver("A partial phrase is now final.", segment: 1, revision: 2, final: true, to: session)
        #expect(await waitUntil { fixture.translator.calls[0].cancellationObserved })
        let translatedBeforeLateProgress = session.lines.last?.translatedText
        fixture.translator.publish("적용되면 안 되는 중간 번역", from: 0)
        #expect(session.lines.last?.translatedText == translatedBeforeLateProgress)
        #expect(fixture.translator.calls.count == 1)

        fixture.translator.complete(0, with: .success("적용되면 안 되는 이전 번역"))
        #expect(await waitUntil { fixture.translator.calls.count == 2 })
        #expect(session.lines.last?.translatedText == translatedBeforeLateProgress)
        #expect(fixture.translator.maximumActiveCount == 1)
        fixture.translator.complete(1, with: .success("최종 번역입니다."))
        #expect(await waitUntil { session.lines.last?.translatedText == "최종 번역입니다." })
        assertCompleteEventAccounting(fixture.recorder)
    }

    @Test(arguments: [false, true])
    func stoppedRequestCannotPublishProgressSuccessOrOrdinaryErrorIntoRestartedSession(fails: Bool) async throws {
        let fixture = makeFixture(cooperatesWithCancellation: false)
        defer { fixture.cleanup() }
        let session = fixture.session
        let repeatedSource = "The same partial phrase"

        deliver(repeatedSource, segment: 1, revision: 1, final: false, to: session)
        #expect(await waitUntil { fixture.translator.calls.count == 1 })
        session.stop()
        _ = session.activateLiveCallbackPipelineForTesting()
        session.statusMessage = "Restarted session is listening."
        deliver(repeatedSource, segment: 2, revision: 1, final: false, to: session)
        let currentLineID = try #require(session.lines.last?.id)
        let expectedStatus = session.statusMessage
        let expectedText = session.lines.last?.translatedText
        #expect(session.pendingTranslationSourceTextForTesting == repeatedSource)
        #expect(fixture.translator.calls.count == 1)

        fixture.translator.publish("이전 세션의 진행 결과", from: 0)
        #expect(session.lines.last?.translatedText == expectedText)
        #expect(session.statusMessage == expectedStatus)
        fixture.translator.complete(0, with: fails ? .failure(DelayedSchedulingError.previousSession) : .success("이전 세션의 결과"))

        #expect(await waitUntil { fixture.translator.calls.count == 2 })
        #expect(session.lines.last?.id == currentLineID)
        #expect(session.lines.last?.translatedText == expectedText)
        #expect(session.statusMessage == expectedStatus)
        #expect(session.pendingTranslationSourceTextForTesting == repeatedSource)
        #expect(fixture.translator.maximumActiveCount == 1)
        fixture.translator.complete(1, with: .success("현재 세션의 번역입니다."))
        #expect(await waitUntil { session.lines.last?.translatedText == "현재 세션의 번역입니다." })
        #expect(session.pendingTranslationSourceTextForTesting.isEmpty)

        let firstID = try #require(fixture.recorder.events.first { $0.stage == "translation.queued" }?.id)
        #expect(terminalEvents(for: firstID, in: fixture.recorder).map(\.stage) == ["translation.cancelled"])
        assertCompleteEventAccounting(fixture.recorder)
    }

    @Test
    func repeatedFinalTextKeepsDistinctRequestIDsAndFinalOrderWhileReplayIsIgnored() async throws {
        let fixture = makeFixture(cooperatesWithCancellation: false)
        defer { fixture.cleanup() }
        let session = fixture.session

        deliver("Yes.", segment: 1, revision: 1, final: true, to: session)
        #expect(await waitUntil { fixture.translator.calls.count == 1 })
        deliver("Yes.", segment: 1, revision: 1, final: true, to: session)
        deliver("Yes.", segment: 2, revision: 1, final: true, to: session)
        deliver("A later partial phrase", segment: 3, revision: 1, final: false, to: session)
        #expect(fixture.translator.calls.count == 1)
        #expect(session.lines.count == 3)
        fixture.translator.complete(0, with: .success("첫 번째 확인."))
        #expect(await waitUntil { fixture.translator.calls.count == 2 })
        #expect(fixture.translator.calls[1].invocation.text == "Yes.")
        fixture.translator.complete(1, with: .success("두 번째 확인."))
        #expect(await waitUntil { fixture.translator.calls.count == 3 })
        #expect(fixture.translator.calls[2].invocation.text == "A later partial phrase")
        fixture.translator.complete(2, with: .success("뒤의 중간 문장."))
        #expect(await waitUntil { session.lines.last?.translatedText == "뒤의 중간 문장." })
        #expect(session.lines[0].translatedText == "첫 번째 확인.")
        #expect(session.lines[1].translatedText == "두 번째 확인.")
        #expect(fixture.translator.maximumActiveCount == 1)

        let queued = fixture.recorder.events.filter { $0.stage == "translation.queued" }
        #expect(queued.count == 3)
        #expect(Set(queued.map(\.id)).count == 3)
        for event in fixture.recorder.events where event.stage == "translation.start" {
            #expect(try #require(event.values["queue_ms"]) >= 0)
        }
        for event in fixture.recorder.events where event.stage == "translation.result" {
            #expect(try #require(event.values["elapsed_ms"]) >= 0)
        }
        assertCompleteEventAccounting(fixture.recorder)
    }

    @Test
    func onlyAppliedProgressRecordsFirstApplyAndEachRequestTerminatesOnce() async throws {
        let fixture = makeFixture(cooperatesWithCancellation: false)
        defer { fixture.cleanup() }
        deliver("A completed phrase.", segment: 1, revision: 1, final: true, to: fixture.session)
        #expect(await waitUntil { fixture.translator.calls.count == 1 })
        fixture.translator.publish("부분 번역", from: 0)
        fixture.translator.publish("두 번째 부분 번역", from: 0)
        fixture.translator.complete(0, with: .success("최종 번역입니다."))
        #expect(await waitUntil { fixture.session.lines.last?.translatedText == "최종 번역입니다." })

        let firstApply = fixture.recorder.events.filter { $0.stage == "translation.first_apply" }
        #expect(firstApply.count == 1)
        #expect(try #require(firstApply.first?.values["since_queued_ms"]) >= 0)
        assertCompleteEventAccounting(fixture.recorder)
    }

    @Test
    func resetCancelsQueuedFinalsWithoutStartingThem() async throws {
        let fixture = makeFixture(cooperatesWithCancellation: false)
        defer { fixture.cleanup() }
        deliver("The first final.", segment: 1, revision: 1, final: true, to: fixture.session)
        #expect(await waitUntil { fixture.translator.calls.count == 1 })
        deliver("The second final.", segment: 2, revision: 1, final: true, to: fixture.session)
        fixture.session.stop()
        fixture.translator.complete(0, with: .failure(DelayedSchedulingError.previousSession))
        #expect(await waitUntil { fixture.translator.activeCount == 0 })
        #expect(fixture.translator.calls.count == 1)
        #expect(fixture.recorder.events.filter { $0.stage == "translation.cancelled" }.count == 2)
        assertCompleteEventAccounting(fixture.recorder)
    }

    @Test
    func jevFinalSelectionChangesOnlyTranslationInputAndDoesNotCoalesceWithPartial() async throws {
        let fixture = makeFixture(cooperatesWithCancellation: true, jevEnabled: true)
        defer { fixture.cleanup() }
        let original = "Please check the cash size."
        let selected = "Please check the cache size."
        var inputs: [JevTranscriptSelectionInput] = []
        fixture.session.jevSelectionForTesting = { input in
            inputs.append(input)
            return JevTranscriptSelection(text: selected, outcome: .selected, confidence: 0.95)
        }
        deliver(original, segment: 1, revision: 1, final: false, to: fixture.session)
        try #require(await waitUntil { fixture.translator.calls.count == 1 })
        #expect(inputs.isEmpty)
        deliver(original, segment: 1, revision: 2, final: true, alternatives: [selected], to: fixture.session)
        try #require(await waitUntil { fixture.translator.calls.count == 2 })
        #expect(fixture.translator.calls[0].cancellationObserved)
        #expect(inputs.count == 1)
        #expect(inputs.first?.original == original)
        #expect(inputs.first?.alternatives == [selected])
        #expect(fixture.translator.calls[1].invocation.text == selected)
        fixture.translator.complete(1, with: .success("캐시 크기를 확인하세요."))
        try #require(await waitUntil { fixture.session.lines.last?.translatedText == "캐시 크기를 확인하세요." })
        #expect(fixture.session.lines.last?.sourceText == original)
        #expect(fixture.session.lines.last?.translatedSourceText == original)
        #expect(!fixture.recorder.events.contains { $0.stage == "translation.coalesced_final" })
        #expect(fixture.recorder.events.filter { $0.stage == "jev.selection" }.count == 1)
        assertCompleteEventAccounting(fixture.recorder)
    }

    @Test
    func disabledJevNeverInvokesSelectorEvenWithCandidates() async throws {
        let fixture = makeFixture(cooperatesWithCancellation: true)
        defer { fixture.cleanup() }
        var count = 0
        fixture.session.jevSelectionForTesting = { input in
            count += 1
            return JevTranscriptSelection(text: input.original, outcome: .original, confidence: 1)
        }
        let source = "Keep the original text."
        deliver(source, segment: 1, revision: 1, final: true, alternatives: ["Another sentence."], to: fixture.session)
        try #require(await waitUntil { fixture.translator.calls.count == 1 })
        #expect(count == 0)
        #expect(fixture.translator.calls[0].invocation.text == source)
    }

    @Test
    func jevWithoutDistinctCandidatesReusesIdenticalPartialTranslation() async throws {
        let fixture = makeFixture(cooperatesWithCancellation: true, jevEnabled: true)
        defer { fixture.cleanup() }
        var selectionCount = 0
        fixture.session.jevSelectionForTesting = { input in
            selectionCount += 1
            return JevTranscriptSelection(text: input.original, outcome: .original, confidence: 1)
        }
        let source = "Keep the current recognized sentence."
        deliver(source, segment: 1, revision: 1, final: false, to: fixture.session)
        try #require(await waitUntil { fixture.translator.calls.count == 1 })
        deliver(source, segment: 1, revision: 2, final: true, alternatives: ["  " + source + "  "], to: fixture.session)
        #expect(selectionCount == 0)
        #expect(!fixture.translator.calls[0].cancellationObserved)
        #expect(fixture.recorder.events.filter { $0.stage == "translation.coalesced_final" }.count == 1)
        fixture.translator.complete(0, with: .success("기존 인식 문장을 유지하세요."))
        try #require(await waitUntil { fixture.session.lines.last?.translatedText == "기존 인식 문장을 유지하세요." })
        #expect(fixture.translator.calls.count == 1)
    }

    @Test
    func jevLateResultAfterStopCannotReachTranslatorOrRestartedSession() async throws {
        let fixture = makeFixture(cooperatesWithCancellation: true, jevEnabled: true)
        let selector = ControlledScheduledTranslator(cooperatesWithCancellation: false)
        defer { selector.releaseAll(); fixture.cleanup() }
        fixture.session.jevSelectionForTesting = { input in
            let text = try await selector.translate(TranslationInvocationForTesting(text: input.original, progress: { _ in }))
            return JevTranscriptSelection(text: text, outcome: .selected, confidence: 1)
        }
        deliver("The previous session text.", segment: 1, revision: 1, final: true, alternatives: ["A corrected sentence."], to: fixture.session)
        try #require(await waitUntil { selector.calls.count == 1 })
        fixture.session.stop()
        _ = fixture.session.activateLiveCallbackPipelineForTesting()
        selector.complete(0, with: .success("A stale correction."))
        try #require(await waitUntil { selector.activeCount == 0 })
        #expect(fixture.translator.calls.isEmpty)
        #expect(!fixture.recorder.events.contains { $0.stage == "jev.selection" })
        #expect(!fixture.session.lines.contains { $0.translatedText == "A stale correction." })
    }

    @Test
    func jevUsesAtMostSixPriorFinalSegmentsAsContext() async throws {
        let fixture = makeFixture(cooperatesWithCancellation: true, jevEnabled: true)
        defer { fixture.cleanup() }
        var contexts: [String] = []
        fixture.session.jevSelectionForTesting = { input in
            contexts.append(input.previousContext)
            return JevTranscriptSelection(text: input.original, outcome: .original, confidence: 1)
        }
        fixture.session.translationForTesting = { _ in "번역" }
        for segment in 1...8 {
            deliver("Context \(segment).", segment: segment, revision: 1, final: true,
                    alternatives: ["Alternative \(segment)."], to: fixture.session)
            try #require(await waitUntil { contexts.count == segment })
        }
        #expect(contexts.first == "")
        #expect(contexts.last == "Context 2. Context 3. Context 4. Context 5. Context 6. Context 7.")
    }

    @Test
    func jevOptionPersistsButIsUnavailableForTranscriptionOnlyAndCloudSpeech() {
        let fixture = makeFixture(cooperatesWithCancellation: true, jevEnabled: true)
        defer { fixture.cleanup() }
        fixture.session.stop()
        #expect(fixture.defaults.bool(forKey: "isJevSelectionEnabled"))
        #expect(fixture.session.isJevSelectionAvailable)
        fixture.session.selectedModel = .appleSpeechOnly
        #expect(!fixture.session.isUsingJevSelection)
        fixture.session.useTranslationMode()
        fixture.session.nariTranscriptionModel = .qwen3ASR
        #expect(!fixture.session.isUsingJevSelection)
    }

    @Test
    func jevBatchesAlreadyQueuedFinalsInGroupsOfFourAndPreservesTranslationOrder() async throws {
        let fixture = makeFixture(cooperatesWithCancellation: true, jevEnabled: true)
        defer { fixture.cleanup() }
        var batches: [[String]] = []
        fixture.session.jevBatchSelectionForTesting = { inputs in
            batches.append(inputs.map(\.original))
            return inputs.map { .init(text: $0.alternatives[0], outcome: .selected, confidence: 0.95) }
        }
        deliver("The first sentence is already translating.", segment: 1, revision: 1, final: true, to: fixture.session)
        try #require(await waitUntil { fixture.translator.calls.count == 1 })
        for segment in 2...7 {
            deliver("Original \(segment).", segment: segment, revision: 1, final: true,
                    alternatives: ["Selected \(segment)."], to: fixture.session)
        }
        #expect(batches.isEmpty)
        fixture.translator.complete(0, with: .success("첫 번역"))
        for segment in 2...7 {
            try #require(await waitUntil { fixture.translator.calls.count == segment })
            #expect(fixture.translator.calls[segment - 1].invocation.text == "Selected \(segment).")
            #expect(fixture.session.bufferedJevSelectionCountForTesting <= 3)
            fixture.translator.complete(segment - 1, with: .success("번역 \(segment)"))
        }
        try #require(await waitUntil { fixture.recorder.events.filter { $0.stage == "translation.result" }.count == 7 })
        #expect(batches == [["Original 2.", "Original 3.", "Original 4.", "Original 5."], ["Original 6.", "Original 7."]])
        #expect(fixture.translator.maximumActiveCount == 1)
        #expect(fixture.session.bufferedJevSelectionCountForTesting == 0)
        #expect(fixture.session.lines.suffix(6).map(\.sourceText) == (2...7).map { "Original \($0)." })
        #expect(fixture.session.lines.suffix(6).map(\.translatedSourceText) == (2...7).map { "Original \($0)." })
        #expect(fixture.recorder.events.filter { $0.stage == "jev.selection" && $0.values["buffered"] == 1 }.count == 4)
        assertCompleteEventAccounting(fixture.recorder)
    }

    @Test
    func singleJevFinalDoesNotWaitForMoreCandidatesAndNeverBatchesPartial() async throws {
        let fixture = makeFixture(cooperatesWithCancellation: true, jevEnabled: true)
        defer { fixture.cleanup() }
        var batches: [[String]] = []
        fixture.session.jevBatchSelectionForTesting = { inputs in
            batches.append(inputs.map(\.original))
            return inputs.map { .init(text: $0.original, outcome: .original, confidence: 1) }
        }
        deliver("A final sentence.", segment: 1, revision: 1, final: true,
                alternatives: ["An alternate sentence."], to: fixture.session)
        try #require(await waitUntil { fixture.translator.calls.count == 1 })
        #expect(batches == [["A final sentence."]])
        deliver("A pending partial phrase", segment: 2, revision: 1, final: false,
                alternatives: ["An alternative partial phrase"], to: fixture.session)
        fixture.translator.complete(0, with: .success("확정 번역"))
        try #require(await waitUntil { fixture.translator.calls.count == 2 })
        #expect(batches.count == 1)
        #expect(fixture.translator.calls[1].invocation.text == "A pending partial phrase")
    }

    @Test
    func completedJevBatchBufferIsClearedOnStopAndNotReusedAfterRestart() async throws {
        let fixture = makeFixture(cooperatesWithCancellation: true, jevEnabled: true)
        defer { fixture.cleanup() }
        var callCount = 0
        fixture.session.jevBatchSelectionForTesting = { inputs in
            callCount += 1
            return inputs.map { .init(text: $0.alternatives[0], outcome: .selected, confidence: 1) }
        }
        deliver("Blocker.", segment: 1, revision: 1, final: true, to: fixture.session)
        try #require(await waitUntil { fixture.translator.calls.count == 1 })
        for segment in 2...3 {
            deliver("Original \(segment).", segment: segment, revision: 1, final: true,
                    alternatives: ["Old selection \(segment)."], to: fixture.session)
        }
        fixture.translator.complete(0, with: .success("먼저 번역"))
        try #require(await waitUntil { fixture.translator.calls.count == 2 })
        #expect(fixture.session.bufferedJevSelectionCountForTesting == 1)
        fixture.session.stop()
        #expect(fixture.session.bufferedJevSelectionCountForTesting == 0)
        _ = fixture.session.activateLiveCallbackPipelineForTesting()
        deliver("Original 3.", segment: 30, revision: 1, final: true,
                alternatives: ["New selection."], to: fixture.session)
        try #require(await waitUntil { fixture.translator.calls.count == 3 })
        #expect(callCount == 2)
        #expect(fixture.translator.calls[2].invocation.text == "New selection.")
        #expect(fixture.session.bufferedJevSelectionCountForTesting == 0)
    }

    @Test
    func lateJevBatchCannotPopulateBufferOrTranslateAfterStop() async throws {
        let fixture = makeFixture(cooperatesWithCancellation: true, jevEnabled: true)
        let selector = ControlledScheduledTranslator(cooperatesWithCancellation: false)
        defer { selector.releaseAll(); fixture.cleanup() }
        fixture.session.jevBatchSelectionForTesting = { inputs in
            _ = try await selector.translate(.init(text: "batch", progress: { _ in }))
            return inputs.map { .init(text: $0.alternatives[0], outcome: .selected, confidence: 1) }
        }
        deliver("Blocker.", segment: 1, revision: 1, final: true, to: fixture.session)
        try #require(await waitUntil { fixture.translator.calls.count == 1 })
        for segment in 2...3 {
            deliver("Original \(segment).", segment: segment, revision: 1, final: true,
                    alternatives: ["Stale selection \(segment)."], to: fixture.session)
        }
        fixture.translator.complete(0, with: .success("먼저 번역"))
        try #require(await waitUntil { selector.calls.count == 1 })
        fixture.session.stop()
        _ = fixture.session.activateLiveCallbackPipelineForTesting()
        selector.complete(0, with: .success("ignored"))
        try #require(await waitUntil { selector.activeCount == 0 })
        #expect(fixture.translator.calls.count == 1)
        #expect(fixture.session.bufferedJevSelectionCountForTesting == 0)
        #expect(!fixture.recorder.events.contains { $0.stage == "jev.selection" })
    }

    @Test
    func mismatchedJevBatchResultCountFallsBackToEachOriginal() async throws {
        let fixture = makeFixture(cooperatesWithCancellation: true, jevEnabled: true)
        defer { fixture.cleanup() }
        fixture.session.jevBatchSelectionForTesting = { _ in [] }
        deliver("Original words.", segment: 1, revision: 1, final: true,
                alternatives: ["Alternate words."], to: fixture.session)
        try #require(await waitUntil { fixture.translator.calls.count == 1 })
        #expect(fixture.translator.calls[0].invocation.text == "Original words.")
    }

    private struct Fixture {
        let session: TranslationSessionStore
        let translator: ControlledScheduledTranslator
        let recorder: SchedulingEventRecorder
        let defaults: UserDefaults
        let suiteName: String

        @MainActor
        func cleanup() {
            session.stop()
            translator.releaseAll()
            defaults.removePersistentDomain(forName: suiteName)
        }
    }

    private func makeFixture(cooperatesWithCancellation: Bool, jevEnabled: Bool = false) -> Fixture {
        let suiteName = "TranslationSchedulingTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let session = TranslationSessionStore(modelAvailabilityProvider: { _, _ in [:] }, settingsDefaults: defaults)
        let translator = ControlledScheduledTranslator(cooperatesWithCancellation: cooperatesWithCancellation)
        let recorder = SchedulingEventRecorder()
        session.sourceLanguage = .english
        session.targetLanguage = .korean
        session.isAppleSourceAutoDetectionEnabled = false
        session.isTranscriptPersistenceEnabled = false
        session.isDubbingEnabled = false
        session.openAITranslationModel = .off
        session.geminiTranslationModel = .off
        session.useTranslationMode()
        session.isJevSelectionEnabled = jevEnabled
        session.translationForTesting = { try await translator.translate($0) }
        session.translationEventForTesting = { stage, id, values in
            recorder.events.append(SchedulingEvent(stage: stage, id: id, values: values))
        }
        _ = session.activateLiveCallbackPipelineForTesting()
        return Fixture(session: session, translator: translator, recorder: recorder, defaults: defaults, suiteName: suiteName)
    }

    private func deliver(_ text: String, segment: Int, revision: Int, final: Bool, alternatives: [String] = [], to session: TranslationSessionStore) {
        session.receiveCaptionForTesting(text, metadata: AppleSpeechRecognitionMetadata(
            segmentID: "apple:en:\(segment)", revision: revision, isFinal: final,
            audioRange: CMTimeRange(start: CMTime(seconds: Double(segment) * 2, preferredTimescale: 1_000),
                                    duration: CMTime(seconds: 1, preferredTimescale: 1_000)),
            sourceText: text, alternatives: alternatives, emittedAt: Date()
        ))
    }

    private func terminalEvents(for id: UUID, in recorder: SchedulingEventRecorder) -> [SchedulingEvent] {
        let terminalStages: Set<String> = ["translation.result", "translation.failed", "translation.cancelled", "translation.superseded"]
        return recorder.events.filter { $0.id == id && terminalStages.contains($0.stage) }
    }

    private func assertCompleteEventAccounting(_ recorder: SchedulingEventRecorder) {
        for queued in recorder.events where queued.stage == "translation.queued" {
            #expect(terminalEvents(for: queued.id, in: recorder).count == 1)
        }
    }

    private func waitUntil(_ condition: @MainActor () -> Bool) async -> Bool {
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while !condition(), ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(1))
        }
        return condition()
    }
}
