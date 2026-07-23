import Foundation
import Security

enum PrivatePinyinAIHelperClientError: Error {
    case helperUnavailable
    case authenticationFailed
    case protocolMismatch
    case invalidResponse
    case requestCancelled
    case requestTimedOut
}

enum PrivatePinyinWriterFeature: UInt8, CaseIterable {
    case rewriteFormal = 2
    case rewritePolite = 3
    case rewriteShort = 4
    case rewriteCasual = 5
    case translateZhEn = 6
    case translateEnZh = 7

    var title: String {
        switch self {
        case .rewriteFormal: return "正式改写"
        case .rewritePolite: return "礼貌改写"
        case .rewriteShort: return "精简表达"
        case .rewriteCasual: return "口语改写"
        case .translateZhEn: return "中译英"
        case .translateEnZh: return "英译中"
        }
    }
}

struct PrivatePinyinAIHelperRestartBudget {
    let maximumLaunches: Int
    let windowSeconds: TimeInterval
    private var launchTimes: [TimeInterval] = []

    init(maximumLaunches: Int = 3, windowSeconds: TimeInterval = 30) {
        precondition(maximumLaunches > 0 && windowSeconds > 0)
        self.maximumLaunches = maximumLaunches
        self.windowSeconds = windowSeconds
    }

    mutating func consumeLaunch(at uptime: TimeInterval) -> Bool {
        launchTimes.removeAll { uptime - $0 >= windowSeconds }
        guard launchTimes.count < maximumLaunches else { return false }
        launchTimes.append(uptime)
        return true
    }
}

private enum PrivatePinyinAIHelperOpcode: UInt16 {
    case authenticate = 1
    case health = 2
    case mockInference = 3
    case cancel = 4
    case shutdown = 5
    case writerInference = 6
    case prepareWriter = 7
    case authenticated = 0x8001
    case healthy = 0x8002
    case mockCompleted = 0x8003
    case cancelled = 0x8004
    case acknowledged = 0x8005
    case writerCompleted = 0x8006
    case writerReady = 0x8007
    case error = 0x80ff
}

private struct PrivatePinyinAIHelperFrame {
    static let magic: UInt32 = 0x5050_4139
    static let version: UInt16 = 1
    static let headerBytes = 20
    static let maximumPayloadBytes = 64 * 1024

    let opcode: PrivatePinyinAIHelperOpcode
    let requestID: UInt64
    let payload: Data

    func encoded() throws -> Data {
        guard payload.count <= Self.maximumPayloadBytes else {
            throw PrivatePinyinAIHelperClientError.protocolMismatch
        }
        var data = Data()
        data.appendLittleEndian(Self.magic)
        data.appendLittleEndian(Self.version)
        data.appendLittleEndian(opcode.rawValue)
        data.appendLittleEndian(requestID)
        data.appendLittleEndian(UInt32(payload.count))
        data.append(payload)
        return data
    }

    static func decodeAvailable(from buffer: inout Data) throws -> PrivatePinyinAIHelperFrame? {
        guard buffer.count >= headerBytes else {
            return nil
        }
        guard buffer.readUInt32LittleEndian(at: 0) == magic,
              buffer.readUInt16LittleEndian(at: 4) == version,
              let opcode = PrivatePinyinAIHelperOpcode(
                rawValue: buffer.readUInt16LittleEndian(at: 6)
              ) else {
            throw PrivatePinyinAIHelperClientError.protocolMismatch
        }
        let requestID = buffer.readUInt64LittleEndian(at: 8)
        let payloadLength = Int(buffer.readUInt32LittleEndian(at: 16))
        guard payloadLength <= maximumPayloadBytes else {
            throw PrivatePinyinAIHelperClientError.protocolMismatch
        }
        let totalLength = headerBytes + payloadLength
        guard buffer.count >= totalLength else {
            return nil
        }
        let payload = buffer.subdata(in: headerBytes..<totalLength)
        buffer.removeSubrange(0..<totalLength)
        return PrivatePinyinAIHelperFrame(
            opcode: opcode,
            requestID: requestID,
            payload: payload
        )
    }
}

/// Optional desktop Writer helper transport.
///
/// AI-09 does not route ordinary candidates through this client. Future Writer features
/// may submit bounded work here, while every launch, read, write, and callback stays off
/// the IMK key-event thread. Anonymous child pipes authenticate the controlled process;
/// the random per-launch token adds a protocol-level fail-closed handshake.
final class PrivatePinyinAIHelperClient {
    static let shared = PrivatePinyinAIHelperClient()

    typealias Completion = (Result<Void, PrivatePinyinAIHelperClientError>) -> Void
    typealias WriterCompletion = (Result<[String], PrivatePinyinAIHelperClientError>) -> Void

    private struct PendingRequest {
        let completion: Completion
        let deadline: DispatchWorkItem
    }

    private struct PendingWriterRequest {
        let feature: PrivatePinyinWriterFeature
        let sessionID: UInt64
        let completion: WriterCompletion
        let deadline: DispatchWorkItem
    }

    private let stateQueue = DispatchQueue(label: "com.privatepinyin.ai-helper-client")
    private let requestCounterLock = NSLock()
    private var process: Process?
    private var inputHandle: FileHandle?
    private var outputHandle: FileHandle?
    private var outputBuffer = Data()
    private var authenticated = false
    private var transportGeneration: UInt64 = 0
    private var requestCounter: UInt64 = 0
    private var restartBudget = PrivatePinyinAIHelperRestartBudget()
    private var afterAuthentication: [(
        operation: () -> Void,
        completion: Completion
    )] = []
    private var pending: [UInt64: PendingRequest] = [:]
    private var pendingWriter: [UInt64: PendingWriterRequest] = [:]

    private init() {}

    func healthCheck(completion: @escaping Completion) {
        enqueueAfterAuthentication(completion: completion) { [weak self] in
            self?.sendRequest(opcode: .health, payload: Data(), completion: completion)
        }
    }

    func prepareWriter(completion: @escaping Completion) {
        enqueueAfterAuthentication(completion: completion) { [weak self] in
            self?.sendRequest(
                opcode: .prepareWriter,
                payload: Data(),
                timeoutSeconds: 35,
                completion: completion
            )
        }
    }

    @discardableResult
    func submitWriter(
        feature: PrivatePinyinWriterFeature,
        source: String,
        locale: String = "zh-CN",
        completion: @escaping WriterCompletion
    ) -> UInt64 {
        let requestID = nextRequestID()
        let sessionID = requestID ^ UInt64(Date().timeIntervalSince1970.bitPattern)
        guard let payload = Self.writerPayload(
            feature: feature,
            sessionID: sessionID,
            locale: locale,
            source: source
        ) else {
            completion(.failure(.protocolMismatch))
            return requestID
        }
        enqueueAfterAuthentication(completion: { result in
            if case let .failure(error) = result {
                completion(.failure(error))
            }
        }) { [weak self] in
            self?.sendWriterRequest(
                requestID: requestID,
                sessionID: sessionID,
                feature: feature,
                payload: payload,
                completion: completion
            )
        }
        return requestID
    }

    @discardableResult
    func submitMock(delayMilliseconds: UInt32, completion: @escaping Completion) -> UInt64 {
        let requestID = nextRequestID()
        enqueueAfterAuthentication(completion: completion) { [weak self] in
            var payload = Data()
            payload.appendLittleEndian(delayMilliseconds)
            self?.sendRequest(
                opcode: .mockInference,
                requestID: requestID,
                payload: payload,
                timeoutSeconds: min(6, max(1, TimeInterval(delayMilliseconds) / 1_000 + 1)),
                completion: completion
            )
        }
        return requestID
    }

    func cancel(requestID: UInt64, completion: Completion? = nil) {
        let completion = completion ?? { _ in }
        enqueueAfterAuthentication(completion: completion) { [weak self] in
            var payload = Data()
            payload.appendLittleEndian(requestID)
            self?.sendRequest(opcode: .cancel, payload: payload, completion: completion)
        }
    }

    func shutdown() {
        stateQueue.async { [weak self] in
            guard let self, authenticated else {
                self?.stopTransport(error: .helperUnavailable)
                return
            }
            sendRequest(opcode: .shutdown, payload: Data()) { [weak self] _ in
                self?.stateQueue.async {
                    self?.stopTransport(error: .helperUnavailable)
                }
            }
        }
    }

    func terminateForTesting() {
        stateQueue.sync {
            process?.terminate()
        }
    }

    private func enqueueAfterAuthentication(
        completion: @escaping Completion,
        operation: @escaping () -> Void
    ) {
        stateQueue.async { [weak self] in
            guard let self else {
                completion(.failure(.helperUnavailable))
                return
            }
            do {
                try ensureStarted()
                if authenticated {
                    operation()
                } else {
                    afterAuthentication.append((operation, completion))
                }
            } catch {
                completion(.failure(.helperUnavailable))
                stopTransport(error: .helperUnavailable)
            }
        }
    }

    private func ensureStarted() throws {
        if process?.isRunning == true {
            return
        }
        stopTransport(error: .helperUnavailable)
        guard restartBudget.consumeLaunch(at: ProcessInfo.processInfo.systemUptime) else {
            throw PrivatePinyinAIHelperClientError.helperUnavailable
        }
        transportGeneration &+= 1
        if transportGeneration == 0 {
            transportGeneration = 1
        }
        let generation = transportGeneration

        guard let helperURL = Bundle.main.executableURL?
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Helpers", isDirectory: true)
            .appendingPathComponent("PrivatePinyinAIHelper"),
              FileManager.default.isExecutableFile(atPath: helperURL.path) else {
            throw PrivatePinyinAIHelperClientError.helperUnavailable
        }

        var token = Data(count: 32)
        let status = token.withUnsafeMutableBytes { buffer in
            SecRandomCopyBytes(kSecRandomDefault, buffer.count, buffer.baseAddress!)
        }
        guard status == errSecSuccess else {
            throw PrivatePinyinAIHelperClientError.helperUnavailable
        }

        let inputPipe = Pipe()
        let outputPipe = Pipe()
        let process = Process()
        process.executableURL = helperURL
        process.arguments = ["--stdio"]
        var environment = ProcessInfo.processInfo.environment
        environment["PRIVATE_PINYIN_AI_HELPER_TOKEN"] = token.hexadecimalString
        process.environment = environment
        process.standardInput = inputPipe
        process.standardOutput = outputPipe
        process.standardError = FileHandle.nullDevice
        process.terminationHandler = { [weak self] _ in
            self?.stateQueue.async {
                guard self?.transportGeneration == generation else { return }
                self?.stopTransport(error: .helperUnavailable)
            }
        }

        inputHandle = inputPipe.fileHandleForWriting
        outputHandle = outputPipe.fileHandleForReading
        outputHandle?.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            self?.stateQueue.async {
                guard let self, self.transportGeneration == generation else { return }
                if data.isEmpty {
                    self.stopTransport(error: .helperUnavailable)
                    return
                }
                self.receive(data)
            }
        }
        try process.run()
        self.process = process

        registerPending(requestID: 0, timeoutSeconds: 5) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success:
                authenticated = true
                let operations = afterAuthentication
                afterAuthentication.removeAll(keepingCapacity: true)
                operations.forEach { $0.operation() }
            case .failure:
                stopTransport(error: .authenticationFailed)
            }
        }
        try write(
            PrivatePinyinAIHelperFrame(
                opcode: .authenticate,
                requestID: 0,
                payload: token
            )
        )
    }

    private func nextRequestID() -> UInt64 {
        requestCounterLock.lock()
        defer { requestCounterLock.unlock() }
        requestCounter &+= 1
        if requestCounter == 0 {
            requestCounter = 1
        }
        return requestCounter
    }

    private func sendRequest(
        opcode: PrivatePinyinAIHelperOpcode,
        requestID: UInt64? = nil,
        payload: Data,
        timeoutSeconds: TimeInterval = 5,
        completion: Completion? = nil
    ) {
        let requestID = requestID ?? nextRequestID()
        if let completion {
            registerPending(
                requestID: requestID,
                timeoutSeconds: timeoutSeconds,
                completion: completion
            )
        }
        do {
            try write(
                PrivatePinyinAIHelperFrame(
                    opcode: opcode,
                    requestID: requestID,
                    payload: payload
                )
            )
        } catch {
            removePending(requestID: requestID)?(.failure(.helperUnavailable))
            stopTransport(error: .helperUnavailable)
        }
    }

    private func sendWriterRequest(
        requestID: UInt64,
        sessionID: UInt64,
        feature: PrivatePinyinWriterFeature,
        payload: Data,
        completion: @escaping WriterCompletion
    ) {
        let generation = transportGeneration
        let deadline = DispatchWorkItem { [weak self] in
            guard let self, transportGeneration == generation,
                  let request = removePendingWriter(requestID: requestID) else { return }
            request.completion(.failure(.requestTimedOut))
        }
        pendingWriter[requestID] = PendingWriterRequest(
            feature: feature,
            sessionID: sessionID,
            completion: completion,
            deadline: deadline
        )
        stateQueue.asyncAfter(deadline: .now() + 4, execute: deadline)
        do {
            try write(
                PrivatePinyinAIHelperFrame(
                    opcode: .writerInference,
                    requestID: requestID,
                    payload: payload
                )
            )
        } catch {
            removePendingWriter(requestID: requestID)?.completion(.failure(.helperUnavailable))
            stopTransport(error: .helperUnavailable)
        }
    }

    private func registerPending(
        requestID: UInt64,
        timeoutSeconds: TimeInterval,
        completion: @escaping Completion
    ) {
        let generation = transportGeneration
        let deadline = DispatchWorkItem { [weak self] in
            guard let self, transportGeneration == generation,
                  let completion = removePending(requestID: requestID) else { return }
            completion(.failure(.requestTimedOut))
            stopTransport(error: .requestTimedOut)
        }
        pending[requestID] = PendingRequest(completion: completion, deadline: deadline)
        stateQueue.asyncAfter(
            deadline: .now() + max(0.05, timeoutSeconds),
            execute: deadline
        )
    }

    private func removePending(requestID: UInt64) -> Completion? {
        guard let request = pending.removeValue(forKey: requestID) else { return nil }
        request.deadline.cancel()
        return request.completion
    }

    private func removePendingWriter(requestID: UInt64) -> PendingWriterRequest? {
        guard let request = pendingWriter.removeValue(forKey: requestID) else { return nil }
        request.deadline.cancel()
        return request
    }

    private func write(_ frame: PrivatePinyinAIHelperFrame) throws {
        guard let inputHandle else {
            throw PrivatePinyinAIHelperClientError.helperUnavailable
        }
        try inputHandle.write(contentsOf: frame.encoded())
    }

    private func receive(_ data: Data) {
        outputBuffer.append(data)
        do {
            while let frame = try PrivatePinyinAIHelperFrame.decodeAvailable(from: &outputBuffer) {
                handle(frame)
            }
        } catch {
            stopTransport(error: .protocolMismatch)
        }
    }

    private func handle(_ frame: PrivatePinyinAIHelperFrame) {
        if let writer = pendingWriter[frame.requestID] {
            let result: Result<[String], PrivatePinyinAIHelperClientError>
            if frame.opcode == .writerCompleted,
               let suggestions = Self.decodeWriterPreview(
                   frame.payload,
                   feature: writer.feature,
                   sessionID: writer.sessionID
               ) {
                result = .success(suggestions)
            } else if frame.opcode == .cancelled {
                result = .failure(.requestCancelled)
            } else {
                result = .failure(.invalidResponse)
            }
            removePendingWriter(requestID: frame.requestID)?.completion(result)
            return
        }
        let result: Result<Void, PrivatePinyinAIHelperClientError>
        switch frame.opcode {
        case .authenticated, .healthy, .mockCompleted, .acknowledged, .writerReady:
            result = .success(())
        case .cancelled:
            result = .failure(.requestCancelled)
        case .error:
            result = .failure(.invalidResponse)
        default:
            stopTransport(error: .protocolMismatch)
            return
        }
        removePending(requestID: frame.requestID)?(result)
    }

    private func stopTransport(error: PrivatePinyinAIHelperClientError) {
        transportGeneration &+= 1
        if transportGeneration == 0 {
            transportGeneration = 1
        }
        outputHandle?.readabilityHandler = nil
        try? inputHandle?.close()
        try? outputHandle?.close()
        process?.terminationHandler = nil
        if process?.isRunning == true {
            process?.terminate()
        }
        process = nil
        inputHandle = nil
        outputHandle = nil
        outputBuffer.removeAll(keepingCapacity: false)
        authenticated = false
        let completions = pending.values.map { request -> Completion in
            request.deadline.cancel()
            return request.completion
        }
        let writerCompletions = pendingWriter.values.map { request -> WriterCompletion in
            request.deadline.cancel()
            return request.completion
        }
        let deferredCompletions = afterAuthentication.map { $0.completion }
        pending.removeAll(keepingCapacity: false)
        pendingWriter.removeAll(keepingCapacity: false)
        afterAuthentication.removeAll(keepingCapacity: false)
        completions.forEach { $0(.failure(error)) }
        writerCompletions.forEach { $0(.failure(error)) }
        deferredCompletions.forEach { $0(.failure(error)) }
    }

    private static func writerPayload(
        feature: PrivatePinyinWriterFeature,
        sessionID: UInt64,
        locale: String,
        source: String
    ) -> Data? {
        guard let localeData = locale.data(using: .utf8),
              let sourceData = source.data(using: .utf8),
              !sourceData.isEmpty,
              sourceData.count <= 4 * 1024,
              source.count <= 600,
              localeData.count <= Int(UInt16.max) else {
            return nil
        }
        var payload = Data()
        payload.appendLittleEndian(UInt16(1))
        payload.append(feature.rawValue)
        payload.append(1)
        payload.appendLittleEndian(sessionID)
        payload.appendLittleEndian(UInt64(1))
        payload.appendLittleEndian(UInt64(0))
        payload.appendLittleEndian(UInt32(3_000))
        payload.appendLittleEndian(UInt16(localeData.count))
        payload.appendLittleEndian(UInt32(sourceData.count))
        payload.append(localeData)
        payload.append(sourceData)
        return payload
    }

    private static func decodeWriterPreview(
        _ payload: Data,
        feature: PrivatePinyinWriterFeature,
        sessionID: UInt64
    ) -> [String]? {
        guard payload.count >= 28,
              payload.readUInt16LittleEndian(at: 0) == 1,
              payload[2] == feature.rawValue,
              (1...3).contains(Int(payload[3])),
              payload.readUInt64LittleEndian(at: 4) == sessionID,
              payload.readUInt64LittleEndian(at: 12) == 1,
              payload.readUInt64LittleEndian(at: 20) == 0 else {
            return nil
        }
        var offset = 28
        var suggestions: [String] = []
        for _ in 0..<Int(payload[3]) {
            guard offset + 2 <= payload.count else { return nil }
            let length = Int(payload.readUInt16LittleEndian(at: offset))
            offset += 2
            guard length > 0, length <= 4 * 1024, offset + length <= payload.count,
                  let value = String(data: payload.subdata(in: offset..<(offset + length)), encoding: .utf8),
                  !value.isEmpty, value.count <= 600 else {
                return nil
            }
            suggestions.append(value)
            offset += length
        }
        return offset == payload.count ? suggestions : nil
    }
}

private extension Data {
    mutating func appendLittleEndian<T: FixedWidthInteger>(_ value: T) {
        var littleEndian = value.littleEndian
        Swift.withUnsafeBytes(of: &littleEndian) { bytes in
            append(contentsOf: bytes)
        }
    }

    func readUInt16LittleEndian(at offset: Int) -> UInt16 {
        UInt16(self[offset]) | (UInt16(self[offset + 1]) << 8)
    }

    func readUInt32LittleEndian(at offset: Int) -> UInt32 {
        (0..<4).reduce(UInt32(0)) { value, index in
            value | (UInt32(self[offset + index]) << UInt32(index * 8))
        }
    }

    func readUInt64LittleEndian(at offset: Int) -> UInt64 {
        (0..<8).reduce(UInt64(0)) { value, index in
            value | (UInt64(self[offset + index]) << UInt64(index * 8))
        }
    }

    var hexadecimalString: String {
        map { String(format: "%02x", $0) }.joined()
    }
}
