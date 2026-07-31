import Foundation

struct PrivatePinyinCandidateSelectionToken: Equatable {
    let generation: UInt64
    let index: Int
}

struct PrivatePinyinResolvedCandidateSelection: Equatable {
    let token: PrivatePinyinCandidateSelectionToken
    let text: String
}

struct PrivatePinyinCandidateSelectionState {
    private(set) var generation: UInt64 = 0
    private(set) var displayedCandidates: [String] = []
    private var highlightedSelection: PrivatePinyinResolvedCandidateSelection?

    mutating func replaceDisplayedCandidates(_ candidates: [String]) {
        generation &+= 1
        displayedCandidates = candidates
        highlightedSelection = nil
    }

    mutating func clear() {
        replaceDisplayedCandidates([])
    }

    mutating func recordHighlight(
        text: String,
        token: PrivatePinyinCandidateSelectionToken?
    ) {
        highlightedSelection = resolve(text: text, token: token)
    }

    func resolveFinalSelection(
        text: String,
        token: PrivatePinyinCandidateSelectionToken?
    ) -> PrivatePinyinResolvedCandidateSelection? {
        if let resolved = resolve(text: text, token: token) {
            return resolved
        }

        guard let highlightedSelection,
              highlightedSelection.token.generation == generation,
              text.isEmpty || highlightedSelection.text == text else {
            return nil
        }
        return highlightedSelection
    }

    private func resolve(
        text: String,
        token: PrivatePinyinCandidateSelectionToken?
    ) -> PrivatePinyinResolvedCandidateSelection? {
        if let token {
            guard token.generation == generation,
                  displayedCandidates.indices.contains(token.index) else {
                return nil
            }
            let displayedText = displayedCandidates[token.index]
            guard text.isEmpty || displayedText == text else {
                return nil
            }
            return PrivatePinyinResolvedCandidateSelection(token: token, text: displayedText)
        }

        guard !text.isEmpty,
              let index = displayedCandidates.firstIndex(of: text) else {
            return nil
        }
        return PrivatePinyinResolvedCandidateSelection(
            token: PrivatePinyinCandidateSelectionToken(
                generation: generation,
                index: index
            ),
            text: text
        )
    }
}
