import Foundation
import PrompterCore

final class CoreTests {
    func testFolderTreePreservesNestedAndRootFiles() {
        let tree = ScriptTreeNode.build(paths: ["video/script.md", "video/notes/outline.md", "video/metadata.md", "README.md", "other/script.md", "video/script.md"])
        checkEqual(tree.map(\.name), ["other", "video", "README.md"])
        checkEqual(tree[1].children?.map(\.name), ["notes", "metadata.md", "script.md"])
        checkEqual(tree[1].children?.first?.children?.first?.path, "video/notes/outline.md")
        checkEqual(tree[0].children?.first?.path, "other/script.md")
        checkEqual(tree.last?.children, nil)
    }
    func testFolderSearchKeepsAncestorsAndExpandsFolderMatches() {
        let tree = ScriptTreeNode.build(paths: ["video/notes/outline.md", "video/script.md", "other/script.md", "README.md"])
        let match = ScriptTreeNode.filter(tree, query: " OUTLINE ")
        checkEqual(match.map(\.name), ["video"])
        checkEqual(match.first?.children?.map(\.name), ["notes"])
        checkEqual(match.first?.children?.first?.children?.first?.name, "outline.md")
        let folderMatch = ScriptTreeNode.filter(tree, query: "video")
        checkEqual(folderMatch.first?.children?.map(\.name), ["notes", "script.md"])
        checkEqual(ScriptTreeNode.filter(tree, query: "script.md").map(\.name), ["other", "video"])
        checkEqual(ScriptTreeNode.filter(tree, query: "missing"), [])
        checkEqual(ScriptTreeNode.filter(tree, query: "  "), tree)
    }
    func testFolderTreeUsesNaturalOrderingAndStablePaths() {
        let paths = ["take10/script.md", "take2/script.md", "take2/script10.md", "take2/script2.md"]
        let tree = ScriptTreeNode.build(paths: paths)
        checkEqual(tree.map(\.name), ["take2", "take10"])
        checkEqual(tree.first?.children?.map(\.name), ["script.md", "script2.md", "script10.md"])
        checkEqual(ScriptTreeNode.build(paths: paths.reversed()), tree)
    }
    func testFolderSortReversesNamesAtEveryLevelAndKeepsFoldersFirst() {
        let tree = ScriptTreeNode.build(paths: ["take2/a.md", "take2/z.md", "take2/sub/script.md", "take10/script.md", "z.md", "a.md"])
        let descending = ScriptTreeNode.sorted(tree, by: .nameDescending)
        checkEqual(descending.map(\.name), ["take10", "take2", "z.md", "a.md"])
        checkEqual(descending[1].children?.map(\.name), ["sub", "z.md", "a.md"])
        checkEqual(ScriptTreeNode.sorted(descending, by: .nameAscending), tree)
    }
    func testFolderDateSortUsesCorrectDatesAndHandlesMissingAndTiedDates() {
        func dates(_ modified: Double, _ created: Double) -> ScriptFileDates {
            .init(modified: Date(timeIntervalSince1970: modified), created: Date(timeIntervalSince1970: created))
        }
        let tree = ScriptTreeNode.build(paths: ["a/take2.md", "a/take10.md", "a/take3.md", "a/unknown.md", "b/script.md", "root.md"], dates: [
            "a": dates(100, 200), "b": dates(200, 100), "root.md": dates(300, 300),
            "a/take2.md": dates(10, 30), "a/take10.md": dates(20, 10), "a/take3.md": dates(20, 20)
        ])
        let newest = ScriptTreeNode.sorted(tree, by: .modifiedNewest)
        checkEqual(newest.map(\.name), ["b", "a", "root.md"])
        checkEqual(newest[1].children?.map(\.name), ["take3.md", "take10.md", "take2.md", "unknown.md"])
        let oldest = ScriptTreeNode.sorted(tree, by: .modifiedOldest)
        checkEqual(oldest.map(\.name), ["a", "b", "root.md"])
        checkEqual(oldest[0].children?.map(\.name), ["take2.md", "take3.md", "take10.md", "unknown.md"])
        let createdNewest = ScriptTreeNode.sorted(tree, by: .createdNewest)
        checkEqual(createdNewest.map(\.name), ["a", "b", "root.md"])
        checkEqual(createdNewest[0].children?.map(\.name), ["take2.md", "take3.md", "take10.md", "unknown.md"])
        let createdOldest = ScriptTreeNode.sorted(tree, by: .createdOldest)
        checkEqual(createdOldest.map(\.name), ["b", "a", "root.md"])
        checkEqual(createdOldest[1].children?.map(\.name), ["take10.md", "take3.md", "take2.md", "unknown.md"])
        let searched = ScriptTreeNode.sorted(ScriptTreeNode.filter(tree, query: "take"), by: .modifiedNewest)
        checkEqual(searched.first?.dates, dates(100, 200))
        checkEqual(searched.first?.children?.map(\.name), ["take3.md", "take10.md", "take2.md"])
    }
    func testExternalMarkdownBecomesReadableScript() {
        let source = """
        ---
        title: Metadata should not be spoken
        ---
        # Opening
        Hello **world**.
        This wraps onto one paragraph.

        <!-- production note -->
        - [ ] First point
        > Say this slowly.
        ```swift
        print("not spoken")
        ```
        ![camera](shot.png)
        [link]: https://example.com
        """
        checkEqual(MarkdownScript.parse(source), [
            .init(kind: .heading(1), text: "Opening"),
            .init(kind: .paragraph, text: "Hello **world**. This wraps onto one paragraph."),
            .init(kind: .bullet, text: "First point"),
            .init(kind: .quote, text: "Say this slowly.")
        ])
        checkTrue(MarkdownScript.parse(source, includeCode: true).contains(.init(kind: .code, text: "print(\"not spoken\")")))
    }
    func testUnclosedFenceAndWindowsNewlines() {
        checkEqual(MarkdownScript.parse("Hello\r\nworld\r\n\r\n~~~js\r\ncode", includeCode: true), [.init(kind: .paragraph, text: "Hello world"), .init(kind: .code, text: "code")])
    }
    func testUnterminatedFrontmatterDoesNotEatScript() {
        checkEqual(MarkdownScript.parse("---\nStill readable"), [.init(kind: .paragraph, text: "Still readable")])
    }
    func testPedalReportValidatesPacketAndAllThreeButtons() {
        checkEqual(PedalReport.decode([1, 0, 3, 0, 1, 0, 1]), [true, false, true])
        checkEqual(PedalReport.decode([1, 0, 3, 0, 0, 1, 0]), [false, true, false])
        checkNil(PedalReport.decode([1, 0, 3]))
        checkNil(PedalReport.decode([1, 0, 3, 0, 8, 0, 0]))
        checkNil(PedalReport.decode([2, 0, 3, 0, 1, 0, 0]))
    }
    func testScrollIsTimeBasedClampedAndLoops() {
        checkEqual(ScrollMath.advance(position: 10, velocity: 100, elapsed: 0.05, maximum: 100, loop: false), 15)
        checkEqual(ScrollMath.advance(position: 10, velocity: -400, elapsed: 0.1, maximum: 100, loop: false), 0)
        checkEqual(ScrollMath.advance(position: 99, velocity: 100, elapsed: 0.1, maximum: 100, loop: false), 100)
        checkEqual(ScrollMath.advance(position: 99, velocity: 100, elapsed: 0.1, maximum: 100, loop: true), 0)
        checkEqual(ScrollMath.advance(position: 0, velocity: 100, elapsed: 8, maximum: 1000, loop: false), 10)
    }
    func testReadingMarkerIsAtBandCentreForAllTextSizes() {
        for fontSize in [20.0, 48, 110] {
            for spacing in [1.0, 1.35, 2] {
                let band = ReadingBand(displayHeight: 600, position: 0.38, fontSize: fontSize, lineSpacing: spacing)
                checkTrue(abs((band.top + band.bottom) / 2 - 228) < 0.0001)
                checkTrue(band.top < 228 && band.bottom > 228)
                // Text starts inside the band, rather than shifting below the centre.
                checkTrue(abs(band.textTop - band.top - 6) < 0.0001)
            }
        }
    }
    func testReadingAlignmentMatchesPhysicalMarkerWhenRotated() {
        for displayHeight in [600.0, 1440] {
            for markerY in [0.0, 0.2, 0.38, 0.9, 1] {
                for rotated in [false, true] {
                    let position = ReadingBand.position(alignedTo: markerY, rotated: rotated)
                    let band = ReadingBand(displayHeight: displayHeight, position: position, fontSize: 48, lineSpacing: 1.35)
                    let midpoint = (band.top + band.bottom) / 2
                    let physicalCenter = rotated ? displayHeight - midpoint : midpoint
                    checkTrue(abs(physicalCenter - markerY * displayHeight) < 0.0001)
                }
            }
        }
    }
    func testReadingAreaResizesAroundTheSameCentre() {
        let standard = ReadingBand(displayHeight: 600, position: 0.55, fontSize: 48, lineSpacing: 1.35)
        for lines in [1.0, 2, 3.5, 5] {
            let resized = ReadingBand(displayHeight: 600, position: 0.55, fontSize: 48, lineSpacing: 1.35, lines: lines)
            checkTrue(abs((resized.top + resized.bottom) / 2 - standard.centerY) < 0.0001)
            checkTrue(abs(resized.height / standard.height - lines / 2) < 0.0001)
        }
    }
}

private var failures = 0
private func checkEqual<T: Equatable>(_ actual: T, _ expected: T, file: StaticString = #filePath, line: UInt = #line) {
    if actual != expected { failures += 1; print("FAIL \(file):\(line): \(actual) != \(expected)") }
}
private func checkTrue(_ value: Bool, file: StaticString = #filePath, line: UInt = #line) { checkEqual(value, true, file: file, line: line) }
private func checkNil<T>(_ value: T?, file: StaticString = #filePath, line: UInt = #line) { checkTrue(value == nil, file: file, line: line) }

@main struct Checks {
    static func main() {
        let tests = CoreTests()
        tests.testFolderTreePreservesNestedAndRootFiles()
        tests.testFolderSearchKeepsAncestorsAndExpandsFolderMatches()
        tests.testFolderTreeUsesNaturalOrderingAndStablePaths()
        tests.testFolderSortReversesNamesAtEveryLevelAndKeepsFoldersFirst()
        tests.testFolderDateSortUsesCorrectDatesAndHandlesMissingAndTiedDates()
        tests.testExternalMarkdownBecomesReadableScript()
        tests.testUnclosedFenceAndWindowsNewlines()
        tests.testUnterminatedFrontmatterDoesNotEatScript()
        tests.testPedalReportValidatesPacketAndAllThreeButtons()
        tests.testScrollIsTimeBasedClampedAndLoops()
        tests.testReadingMarkerIsAtBandCentreForAllTextSizes()
        tests.testReadingAlignmentMatchesPhysicalMarkerWhenRotated()
        tests.testReadingAreaResizesAroundTheSameCentre()
        print(failures == 0 ? "PASS: 13 core scenarios (folder tree, search and sorting, Markdown, USB reports, scrolling, reading alignment and resizing)" : "FAIL: \(failures) assertions")
        exit(failures == 0 ? 0 : 1)
    }
}
