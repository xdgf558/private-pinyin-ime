import Foundation

@main
enum CandidateSelectionStateTests {
    static func main() {
        markedSelectionUsesItsExactDuplicateIndex()
        emptyFinalCallbackUsesTheCurrentHighlight()
        staleSelectionCannotCommitAfterCandidateRefresh()
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

        let resolved = state.resolveFinalSelection(text: "打包一个", token: token)
        require(resolved?.token.index == 2, "marked duplicates retain their displayed index")
    }

    private static func emptyFinalCallbackUsesTheCurrentHighlight() {
        var state = PrivatePinyinCandidateSelectionState()
        state.replaceDisplayedCandidates(["重新", "打包一个", "一个"])
        let token = PrivatePinyinCandidateSelectionToken(
            generation: state.generation,
            index: 1
        )
        state.recordHighlight(text: "打包一个", token: token)

        let resolved = state.resolveFinalSelection(text: "", token: nil)
        require(resolved?.text == "打包一个", "an empty final callback retains the highlighted text")
        require(resolved?.token.index == 1, "an empty final callback retains the highlighted index")
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
            state.resolveFinalSelection(text: "打包一个", token: staleToken) == nil,
            "a callback from an older displayed page fails closed"
        )
        require(
            state.resolveFinalSelection(text: "", token: nil) == nil,
            "candidate refresh clears the old highlighted fallback"
        )
    }

    private static func plainTextCallbackStillResolvesWithoutCustomAttributes() {
        var state = PrivatePinyinCandidateSelectionState()
        state.replaceDisplayedCandidates(["重新", "打包一个", "一个"])

        let resolved = state.resolveFinalSelection(text: "打包一个", token: nil)
        require(resolved?.token.index == 1, "plain InputMethodKit callbacks remain supported")
    }

    private static func mismatchedMarkedTextFailsClosed() {
        var state = PrivatePinyinCandidateSelectionState()
        state.replaceDisplayedCandidates(["重新", "打包一个"])
        let token = PrivatePinyinCandidateSelectionToken(
            generation: state.generation,
            index: 1
        )

        require(
            state.resolveFinalSelection(text: "重新", token: token) == nil,
            "a marked index cannot commit different visible text"
        )
    }

    private static func require(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else {
            fatalError(message)
        }
    }
}
