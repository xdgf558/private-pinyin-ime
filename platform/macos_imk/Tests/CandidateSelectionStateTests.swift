import Foundation

@main
enum CandidateSelectionStateTests {
    static func main() {
        markedSelectionUsesItsExactDuplicateIndex()
        strippedAttributesPreferTheExactHighlightedDuplicate()
        emptyFinalCallbackUsesTheCurrentHighlight()
        staleSelectionCannotCommitAfterCandidateRefresh()
        staleAttributeCannotFallThroughToTheCurrentHighlight()
        currentPanelSnapshotCanResolveAnEmptyCallback()
        stalePanelSnapshotCannotBorrowTheCurrentGeneration()
        plainTextCallbackStillResolvesWithoutCustomAttributes()
        mismatchedMarkedTextFailsClosed()
        print("macOS candidate selection state tests passed.")
    }

    private static func markedSelectionUsesItsExactDuplicateIndex() {
        var state = PrivatePinyinCandidateSelectionState()
        state.replaceDisplayedCandidates(["重新", "打包一个", "打包一个"])
        let token = PrivatePinyinCandidateSelectionToken(
            generation: state.generation,
            index: 2
        )

        let resolved = state.resolveFinalSelection(
            text: "打包一个",
            attributeToken: token
        )
        require(resolved?.token.index == 2, "marked duplicates retain their displayed index")
        require(resolved?.source == .attribute, "the marked candidate uses attribute identity")
    }

    private static func strippedAttributesPreferTheExactHighlightedDuplicate() {
        var state = PrivatePinyinCandidateSelectionState()
        state.replaceDisplayedCandidates(["重新", "打包一个", "打包一个"])
        let token = PrivatePinyinCandidateSelectionToken(
            generation: state.generation,
            index: 2
        )
        state.recordHighlight(text: "打包一个", token: token)

        let resolved = state.resolveFinalSelection(
            text: "打包一个",
            attributeToken: nil
        )
        require(
            resolved?.token.index == 2,
            "a stripped callback prefers the verified highlight over the first text match"
        )
        require(resolved?.source == .highlight, "the stripped callback reports highlight resolution")
    }

    private static func emptyFinalCallbackUsesTheCurrentHighlight() {
        var state = PrivatePinyinCandidateSelectionState()
        state.replaceDisplayedCandidates(["重新", "打包一个", "一个"])
        let token = PrivatePinyinCandidateSelectionToken(
            generation: state.generation,
            index: 1
        )
        state.recordHighlight(text: "打包一个", token: token)

        let resolved = state.resolveFinalSelection(text: "", attributeToken: nil)
        require(resolved?.text == "打包一个", "an empty final callback retains the highlighted text")
        require(resolved?.token.index == 1, "an empty final callback retains the highlighted index")
        require(resolved?.source == .highlight, "the empty callback reports highlight resolution")
    }

    private static func staleSelectionCannotCommitAfterCandidateRefresh() {
        var state = PrivatePinyinCandidateSelectionState()
        state.replaceDisplayedCandidates(["重新", "打包一个"])
        let staleToken = PrivatePinyinCandidateSelectionToken(
            generation: state.generation,
            index: 1
        )
        state.recordHighlight(text: "打包一个", token: staleToken)

        state.replaceDisplayedCandidates(["重新", "打包", "一个"])

        require(
            state.resolveFinalSelection(
                text: "打包一个",
                attributeToken: staleToken
            ) == nil,
            "a callback from an older displayed page fails closed"
        )
        require(
            state.resolveFinalSelection(text: "", attributeToken: nil) == nil,
            "candidate refresh clears the old highlighted fallback"
        )
    }

    private static func stalePanelSnapshotCannotBorrowTheCurrentGeneration() {
        var state = PrivatePinyinCandidateSelectionState()
        state.replaceDisplayedCandidates(["重新", "打包一个"])
        let stalePanelSelection = PrivatePinyinResolvedCandidateSelection(
            token: PrivatePinyinCandidateSelectionToken(
                generation: state.generation,
                index: 1
            ),
            text: "打包一个",
            source: .panel
        )

        state.replaceDisplayedCandidates(["重新", "打包", "一个"])

        require(
            state.resolveFinalSelection(
                text: "",
                attributeToken: nil,
                panelSelection: stalePanelSelection
            ) == nil,
            "a panel index keeps the generation that populated the native panel"
        )
    }

    private static func staleAttributeCannotFallThroughToTheCurrentHighlight() {
        var state = PrivatePinyinCandidateSelectionState()
        state.replaceDisplayedCandidates(["重新", "打包一个"])
        let staleToken = PrivatePinyinCandidateSelectionToken(
            generation: state.generation,
            index: 1
        )

        state.replaceDisplayedCandidates(["重新", "打包一个"])
        let currentToken = PrivatePinyinCandidateSelectionToken(
            generation: state.generation,
            index: 1
        )
        state.recordHighlight(text: "打包一个", token: currentToken)

        require(
            state.resolveFinalSelection(
                text: "打包一个",
                attributeToken: staleToken
            ) == nil,
            "a stale strong identity cannot borrow a current matching highlight"
        )
    }

    private static func currentPanelSnapshotCanResolveAnEmptyCallback() {
        var state = PrivatePinyinCandidateSelectionState()
        state.replaceDisplayedCandidates(["重新", "打包一个", "打包一个"])
        let panelSelection = PrivatePinyinResolvedCandidateSelection(
            token: PrivatePinyinCandidateSelectionToken(
                generation: state.generation,
                index: 2
            ),
            text: "打包一个",
            source: .panel
        )

        let resolved = state.resolveFinalSelection(
            text: "",
            attributeToken: nil,
            panelSelection: panelSelection
        )
        require(resolved?.token.index == 2, "the current panel preserves a duplicate index")
        require(resolved?.source == .panel, "the empty callback reports panel resolution")
    }

    private static func plainTextCallbackStillResolvesWithoutCustomAttributes() {
        var state = PrivatePinyinCandidateSelectionState()
        state.replaceDisplayedCandidates(["重新", "打包一个", "一个"])

        let resolved = state.resolveFinalSelection(
            text: "打包一个",
            attributeToken: nil
        )
        require(resolved?.token.index == 1, "plain InputMethodKit callbacks remain supported")
        require(resolved?.source == .text, "plain callbacks report text compatibility resolution")
    }

    private static func mismatchedMarkedTextFailsClosed() {
        var state = PrivatePinyinCandidateSelectionState()
        state.replaceDisplayedCandidates(["重新", "打包一个"])
        let token = PrivatePinyinCandidateSelectionToken(
            generation: state.generation,
            index: 1
        )

        require(
            state.resolveFinalSelection(
                text: "重新",
                attributeToken: token
            ) == nil,
            "a marked index cannot commit different visible text"
        )
    }

    private static func require(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else {
            fatalError(message)
        }
    }
}
