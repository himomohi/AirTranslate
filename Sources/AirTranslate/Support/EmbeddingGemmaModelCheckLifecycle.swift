/// 화면에 표시되는 동안 필요한 설치 확인만 예약한다. 사용자 취소는 재시도를 예약하지 않는다.
struct EmbeddingGemmaModelCheckLifecycle {
    private(set) var isVisible = false
    private(set) var isCaptureActive = false
    private var isPending = false
    private var isChecking = false

    mutating func appear(isCaptureActive: Bool) {
        isVisible = true
        self.isCaptureActive = isCaptureActive
        isPending = true
    }

    mutating func disappear() {
        isVisible = false
        isPending = false
    }

    mutating func captureChanged(isActive: Bool) {
        isCaptureActive = isActive
        if isActive, isVisible, isChecking { isPending = true }
    }

    mutating func beginIfPossible(isWorking: Bool) -> Bool {
        guard isVisible, isPending, !isChecking, !isWorking, !isCaptureActive else { return false }
        isPending = false
        isChecking = true
        return true
    }

    mutating func finish() {
        isChecking = false
    }
}
