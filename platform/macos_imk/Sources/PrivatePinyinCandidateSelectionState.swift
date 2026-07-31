import Foundation

struct PrivatePinyinCandidateSelectionToken: Equatable {
    let generation: UInt64
    let index: Int
}

enum PrivatePinyinCandidateSelectionResolutionSource: String, Equatable {
    case attribute
    case highlight
    case panel
    case text
}

struct PrivatePinyinResolvedCandidateSelection: Equatable {
    let token: PrivatePinyinCandidateSelectionToken
    let text: String
    let source: PrivatePinyinCandidateSelectionResolutionSource
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
        highlightedSelection = resolve(
            text: text,
            token: token,
            source: .highlight
        )
    }

    func resolveFinalSelection(
        text: String,
        attributeToken: PrivatePinyinCandidateSelectionToken?,
        panelSelection: PrivatePinyinResolvedCandidateSelection? = nil
    ) -> PrivatePinyinResolvedCandidateSelection? {
        if let attributeToken {
            // A stale or inconsistent strong identity must fail closed.
            return resolve(
                text: text,
                token: attributeToken,
                source: .attribute
            )
        }

        if let highlightedSelection,
           highlightedSelection.token.generation == generation,
           text.isEmpty || highlightedSelection.text == text {
            return PrivatePinyinResolvedCandidateSelection(
                token: highlightedSelection.token,
                text: highlightedSelection.text,
                source: .highlight
            )
        }

        if let panelSelection {
            guard text.isEmpty || panelSelection.text == text else {
                return nil
            }
            // The controller captures the generation that populated IMK.
            return resolve(
                text: panelSelection.text,
                token: panelSelection.token,
                source: .panel
            )
        }

        return resolve(text: text, token: nil, source: .text)
    }

    private func resolve(
        text: String,
        token: PrivatePinyinCandidateSelectionToken?,
        source: PrivatePinyinCandidateSelectionResolutionSource
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
            return PrivatePinyinResolvedCandidateSelection(
                token: token,
                text: displayedText,
                source: source
            )
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
            text: text,
            source: source
        )
    }
}
