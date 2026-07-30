import Foundation

private func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else {
        fatalError(message)
    }
}

private func newTracker() -> SelfTextChangeTracker<String> {
    SelfTextChangeTracker(callbackWindow: 0.25)
}

var synchronous = newTracker()
synchronous.beginOperation(documentIdentifier: nil, now: 1.0)
expect(
    synchronous.consumeCallback(
        documentIdentifier: nil,
        currentContext: nil,
        now: 1.0
    ),
    "A synchronous callback from the active text operation must be consumed."
)
synchronous.finishOperation(
    documentIdentifier: nil,
    postOperationContext: nil,
    now: 1.0
)
expect(synchronous.pendingCallbackCount == 0, "Synchronous tracking must settle.")

var asynchronous = newTracker()
asynchronous.beginOperation(documentIdentifier: "field-a", now: 2.0)
asynchronous.finishOperation(
    documentIdentifier: "field-a",
    postOperationContext: "你好",
    now: 2.01
)
expect(
    asynchronous.consumeCallback(
        documentIdentifier: "field-a",
        currentContext: "你好",
        now: 2.02
    ),
    "The latest post-operation context must consume a delayed self callback."
)

var externalClear = newTracker()
externalClear.beginOperation(documentIdentifier: "field-a", now: 3.0)
externalClear.finishOperation(
    documentIdentifier: "field-a",
    postOperationContext: "准备发布",
    now: 3.01
)
expect(
    !externalClear.consumeCallback(
        documentIdentifier: "field-a",
        currentContext: "",
        now: 3.02
    ),
    "A host send/clear transition must not be mistaken for a self callback."
)

var unavailableContext = newTracker()
unavailableContext.beginOperation(documentIdentifier: "field-a", now: 4.0)
unavailableContext.finishOperation(
    documentIdentifier: "field-a",
    postOperationContext: nil,
    now: 4.01
)
expect(
    !unavailableContext.consumeCallback(
        documentIdentifier: "field-a",
        currentContext: nil,
        now: 4.02
    ),
    "An asynchronous nil context must fail closed as an external change."
)

var oldContext = newTracker()
oldContext.beginOperation(documentIdentifier: "field-a", now: 5.0)
oldContext.finishOperation(
    documentIdentifier: "field-a",
    postOperationContext: "新文本",
    now: 5.01
)
expect(
    !oldContext.consumeCallback(
        documentIdentifier: "field-a",
        currentContext: "旧文本",
        now: 5.02
    ),
    "Pre-operation context evidence must never suppress an external change."
)

var replacedDocument = newTracker()
replacedDocument.beginOperation(documentIdentifier: "proxy-a", now: 5.5)
replacedDocument.finishOperation(
    documentIdentifier: "proxy-a",
    postOperationContext: "相同文本",
    now: 5.51
)
expect(
    !replacedDocument.consumeCallback(
        documentIdentifier: "proxy-b",
        currentContext: "相同文本",
        now: 5.52
    ),
    "A replaced document proxy must invalidate otherwise matching callback evidence."
)

var multiple = newTracker()
multiple.beginOperation(documentIdentifier: "field-a", now: 6.0)
multiple.finishOperation(
    documentIdentifier: "field-a",
    postOperationContext: "你",
    now: 6.01
)
multiple.beginOperation(documentIdentifier: "field-a", now: 6.02)
multiple.finishOperation(
    documentIdentifier: "field-a",
    postOperationContext: "你好",
    now: 6.03
)
expect(
    multiple.consumeCallback(
        documentIdentifier: "field-a",
        currentContext: "你好",
        now: 6.04
    ),
    "The first delayed callback must match the latest completed text state."
)
expect(
    multiple.consumeCallback(
        documentIdentifier: "field-a",
        currentContext: "你好",
        now: 6.05
    ),
    "Batched delayed callbacks must settle against one latest text state."
)

var expired = newTracker()
expired.beginOperation(documentIdentifier: "field-a", now: 7.0)
expired.finishOperation(
    documentIdentifier: "field-a",
    postOperationContext: "你好",
    now: 7.01
)
expect(
    !expired.consumeCallback(
        documentIdentifier: "field-a",
        currentContext: "你好",
        now: 7.30
    ),
    "Expired callback evidence must fail closed."
)

print("SelfTextChangeTracker regression passed.")
