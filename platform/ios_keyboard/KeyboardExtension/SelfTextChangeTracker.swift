import Foundation

struct SelfTextChangeTracker<DocumentIdentifier: Equatable> {
    private(set) var pendingCallbackCount = 0
    private var activeOperationCount = 0
    private var documentIdentifier: DocumentIdentifier?
    private var latestPostOperationContext: String?
    private var deadline: TimeInterval = 0
    private let callbackWindow: TimeInterval

    init(callbackWindow: TimeInterval) {
        self.callbackWindow = callbackWindow
    }

    mutating func beginOperation(
        documentIdentifier: DocumentIdentifier?,
        now: TimeInterval
    ) {
        if activeOperationCount == 0,
           (self.documentIdentifier != documentIdentifier || now > deadline) {
            reset()
        }

        self.documentIdentifier = documentIdentifier
        pendingCallbackCount += 1
        activeOperationCount += 1
        deadline = now + callbackWindow
    }

    mutating func finishOperation(
        documentIdentifier: DocumentIdentifier?,
        postOperationContext: String?,
        now: TimeInterval
    ) {
        activeOperationCount = max(0, activeOperationCount - 1)
        guard pendingCallbackCount > 0,
              self.documentIdentifier == documentIdentifier else {
            reset()
            return
        }

        // An asynchronous callback is trusted only when the host exposes the
        // latest post-operation context. Pre-operation and nil contexts can
        // also describe an external clear/send transition and must fail closed.
        latestPostOperationContext = postOperationContext
        deadline = now + callbackWindow
    }

    mutating func consumeCallback(
        documentIdentifier: DocumentIdentifier?,
        currentContext: String?,
        now: TimeInterval
    ) -> Bool {
        guard pendingCallbackCount > 0,
              now <= deadline,
              self.documentIdentifier == documentIdentifier else {
            reset()
            return false
        }

        let isSynchronousCallback = activeOperationCount > 0
        let matchesLatestPostOperationContext =
            activeOperationCount == 0
            && currentContext != nil
            && currentContext == latestPostOperationContext
        guard isSynchronousCallback || matchesLatestPostOperationContext else {
            reset()
            return false
        }

        pendingCallbackCount -= 1
        if pendingCallbackCount == 0, activeOperationCount == 0 {
            reset()
        }
        return true
    }

    mutating func reset() {
        pendingCallbackCount = 0
        activeOperationCount = 0
        documentIdentifier = nil
        latestPostOperationContext = nil
        deadline = 0
    }
}
