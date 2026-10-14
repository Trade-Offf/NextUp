import XCTest
@testable import NextUpShared

final class WidgetFitTests: XCTestCase {
    private let metrics = WidgetFit.Metrics(header: 28, row: 26, groupExtra: 12, footer: 22)

    func testEverythingFitsWithoutAFooter() {
        let choice = WidgetFit.choose(rowCount: 3, total: 3, groupStarts: [false, false, false], height: 200, metrics: metrics)
        XCTAssertEqual(choice, WidgetFit.Choice(shown: 3, more: 0))
    }

    func testOverflowKeepsWholeRowsAndCountsTheRest() {
        let choice = WidgetFit.choose(rowCount: 6, total: 20, groupStarts: Array(repeating: false, count: 6), height: CGFloat(28 + 26 * 3 + 22), metrics: metrics)
        XCTAssertEqual(choice, WidgetFit.Choice(shown: 3, more: 17))
    }

    func testAGroupDividerCanDropTheLastRow() {
        let flat = WidgetFit.choose(rowCount: 3, total: 3, groupStarts: [false, false, false], height: CGFloat(28 + 26 * 3), metrics: metrics)
        let groupedHeight = CGFloat(28 + 26 * 2 + 12 + 22)
        let grouped = WidgetFit.choose(rowCount: 3, total: 3, groupStarts: [false, true, true], height: groupedHeight, metrics: metrics)
        XCTAssertEqual(flat, WidgetFit.Choice(shown: 3, more: 0))
        XCTAssertEqual(grouped, WidgetFit.Choice(shown: 2, more: 1))
    }

    func testParentRowsDoNotReduceTheRemainingCount() {
        let choice = WidgetFit.choose(
            rowCount: 2,
            total: 2,
            groupStarts: [false, false],
            height: 400,
            metrics: metrics,
            countsTowardTotal: [false, true]
        )
        XCTAssertEqual(choice, WidgetFit.Choice(shown: 2, more: 1))
    }

    func testHiddenRowsStillCountWhenThePreparedListIsShorter() {
        let choice = WidgetFit.choose(rowCount: 4, total: 11, groupStarts: [false, false, false, false], height: 400, metrics: metrics)
        XCTAssertEqual(choice, WidgetFit.Choice(shown: 4, more: 7))
    }
}