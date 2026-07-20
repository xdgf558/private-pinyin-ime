import Foundation

@main
private enum AIHelperClientTests {
    static func main() throws {
        let client = PrivatePinyinAIHelperClient.shared

        try waitFor("health") { completion in
            client.healthCheck(completion: completion)
        }

        let cancelled = DispatchSemaphore(value: 0)
        let requestID = client.submitMock(delayMilliseconds: 500) { result in
            guard case .failure(.requestCancelled) = result else {
                fatalError("cancelled mock returned an unexpected result")
            }
            cancelled.signal()
        }
        try waitFor("cancel acknowledgement") { completion in
            client.cancel(requestID: requestID, completion: completion)
        }
        guard cancelled.wait(timeout: .now() + 2) == .success else {
            throw TestError.timeout("cancelled mock")
        }

        let crashed = DispatchSemaphore(value: 0)
        _ = client.submitMock(delayMilliseconds: 500) { result in
            guard case .failure(.helperUnavailable) = result else {
                fatalError("helper crash must fail optional work")
            }
            crashed.signal()
        }
        client.terminateForTesting()
        guard crashed.wait(timeout: .now() + 2) == .success else {
            throw TestError.timeout("helper crash fallback")
        }

        // A crash must not poison the next controlled launch.
        try waitFor("health after restart") { completion in
            client.healthCheck(completion: completion)
        }
        client.shutdown()
    }

    private static func waitFor(
        _ name: String,
        operation: (@escaping PrivatePinyinAIHelperClient.Completion) -> Void
    ) throws {
        let semaphore = DispatchSemaphore(value: 0)
        var operationError: PrivatePinyinAIHelperClientError?
        operation { result in
            if case let .failure(error) = result {
                operationError = error
            }
            semaphore.signal()
        }
        guard semaphore.wait(timeout: .now() + 3) == .success else {
            throw TestError.timeout(name)
        }
        if let operationError {
            throw operationError
        }
    }

    private enum TestError: Error {
        case timeout(String)
    }
}
