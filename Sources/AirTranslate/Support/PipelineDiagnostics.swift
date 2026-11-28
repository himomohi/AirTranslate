import Foundation

/// 명시적으로 켠 로컬 성능 측정에 숫자·불투명 UUID만 기록한다. 전사·번역·키는 기록하지 않는다.
enum PipelineDiagnostics {
    static let isEnabled = ProcessInfo.processInfo.environment["AIRTRANSLATE_LATENCY_TRACE"] == "1"
    private static let writeQueue = DispatchQueue(
        label: "AirTranslate.PipelineDiagnostics.writeQueue",
        qos: .utility
    )

    static func record(
        _ stage: String,
        id: String = "",
        sessionID: UUID? = nil,
        lineID: UUID? = nil,
        values: [String: Double] = [:]
    ) {
        guard isEnabled else { return }
        let uptime = ProcessInfo.processInfo.systemUptime
        let filteredValues = values.filter { $0.value.isFinite }
        let sessionUUID = sessionID?.uuidString
        let lineUUID = lineID?.uuidString
        writeQueue.async {
            var record: [String: Any] = filteredValues
            record["stage"] = stage
            record["uptime"] = uptime
            if !id.isEmpty { record["id"] = id }
            if let sessionUUID { record["session_id"] = sessionUUID }
            if let lineUUID { record["line_id"] = lineUUID }
            guard let data = try? JSONSerialization.data(withJSONObject: record, options: [.sortedKeys]) else { return }
            var lineData = Data("AIRTRANSLATE_LATENCY ".utf8)
            lineData.append(data)
            lineData.append(0x0A)
            FileHandle.standardOutput.write(lineData)
        }
    }
}
