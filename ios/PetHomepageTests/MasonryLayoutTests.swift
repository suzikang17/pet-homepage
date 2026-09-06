// ios/PetHomepageTests/MasonryLayoutTests.swift
import XCTest
@testable import PetHomepage

/// The column-balancing arithmetic behind the photo gallery. Pure input/output, so it is worth
/// testing directly rather than through a rendered grid.
final class MasonryLayoutTests: XCTestCase {
    /// Heights are relative — a cell's height for one unit of width.
    private func columns(_ heights: [Double], count: Int) -> [[Int]] {
        MasonryLayout.columns(heights, count: count) { $0 }
    }

    func testEqualHeightsFillLeftToRightLikeAPlainGrid() {
        // Every photo the same shape must lay out exactly as the uniform grid this replaced,
        // otherwise the change is visible on collections that never needed it.
        XCTAssertEqual(columns([1, 1, 1, 1], count: 2), [[0, 2], [1, 3]])
    }

    func testEachItemGoesToTheShortestColumn() {
        // A tall first photo means the second column is shorter, so the next two land there
        // before the first column is used again.
        XCTAssertEqual(columns([3, 1, 1, 1], count: 2), [[0], [1, 2, 3]])
    }

    func testThreeColumnsBalance() {
        XCTAssertEqual(columns([1, 1, 1, 1, 1, 1], count: 3), [[0, 3], [1, 4], [2, 5]])
    }

    /// Placement must not depend on items that arrive later: the grid is newest-first, so a new
    /// photo appended tomorrow must not reshuffle what is already on screen.
    func testPlacementIsStableAsItemsAreAppended() {
        let first = columns([2, 1, 1], count: 2)
        let extended = columns([2, 1, 1, 5, 0.5], count: 2)

        for (column, indices) in first.enumerated() {
            XCTAssertEqual(Array(extended[column].prefix(indices.count)), indices,
                           "column \(column) reshuffled when items were appended")
        }
    }

    func testEveryItemIsPlacedExactlyOnce() {
        let result = columns([1, 2.5, 0.4, 1.1, 3, 0.9, 1], count: 3)
        XCTAssertEqual(result.flatMap { $0 }.sorted(), Array(0..<7))
    }

    func testSingleColumnKeepsOriginalOrder() {
        XCTAssertEqual(columns([1, 2, 3], count: 1), [[0, 1, 2]])
    }

    func testZeroColumnsProducesNothingRatherThanCrashing() {
        XCTAssertEqual(columns([1, 2], count: 0), [])
    }

    func testEmptyInputProducesEmptyColumns() {
        XCTAssertEqual(columns([], count: 3), [[], [], []])
    }

    /// An unmeasurable photo must not poison the running total and pin everything after it into
    /// a single column.
    func testNonFiniteAndNonPositiveHeightsAreTreatedAsSquare() {
        XCTAssertEqual(columns([.nan, 1, 0, 1], count: 2), [[0, 2], [1, 3]])
        XCTAssertEqual(columns([.infinity, 1, 1, 1], count: 2), [[0, 2], [1, 3]])
        XCTAssertEqual(columns([-5, 1, 1, 1], count: 2), [[0, 2], [1, 3]])
    }
}
