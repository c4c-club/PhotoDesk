// MARK: - StorageMathTests：按类型/年份聚合、未知大小计数、占比（docs/09 D07）

import XCTest
@testable import PhotoDeskCore

final class StorageMathTests: XCTestCase {
    private func entry(_ type: Int, _ year: Int?, _ bytes: Int64?) -> StorageEntry {
        StorageEntry(mediaType: type, year: year, bytes: bytes)
    }

    func testSummarizeByType() {
        let summary = StorageMath.summarize([
            entry(0, 2024, 100),   // photo
            entry(1, 2024, 300),   // video
            entry(2, 2023, 50),    // other
        ])
        XCTAssertEqual(summary.totalBytes, 450)
        XCTAssertEqual(summary.photoBytes, 100)
        XCTAssertEqual(summary.videoBytes, 300)
        XCTAssertEqual(summary.otherBytes, 50)
        XCTAssertEqual(summary.unknownCount, 0)
    }

    func testSummarizeUnknownSizes() {
        let summary = StorageMath.summarize([
            entry(0, 2024, nil),   // iCloud-only 未知
            entry(1, 2024, nil),
            entry(0, 2024, 10),
        ])
        XCTAssertEqual(summary.unknownCount, 2)
        XCTAssertEqual(summary.totalBytes, 10)
    }

    func testSummarizeByYear() {
        let summary = StorageMath.summarize([
            entry(0, 2024, 100),
            entry(1, 2024, 100),
            entry(0, 2023, 40),
            entry(0, nil, 7),      // 无日期不计年份，但计总量
        ])
        XCTAssertEqual(summary.byYear[2024], 200)
        XCTAssertEqual(summary.byYear[2023], 40)
        XCTAssertEqual(summary.byYear.count, 2)
        XCTAssertEqual(summary.totalBytes, 247)
    }

    func testSummarizeEmpty() {
        let summary = StorageMath.summarize([])
        XCTAssertEqual(summary.totalBytes, 0)
        XCTAssertEqual(summary.unknownCount, 0)
        XCTAssertTrue(summary.byYear.isEmpty)
    }

    func testPercent() {
        XCTAssertEqual(StorageMath.percent(50, of: 200), 25)
        XCTAssertEqual(StorageMath.percent(1, of: 3), 33)
        XCTAssertEqual(StorageMath.percent(0, of: 0), 0)
        XCTAssertEqual(StorageMath.percent(10, of: 0), 0)
        XCTAssertEqual(StorageMath.percent(200, of: 200), 100)
    }

    /// 10,000 条聚合 < 500ms（docs/09 D10 性能预算的孪生指标）
    func testSummarizePerformance10k() {
        let entries = (0..<10_000).map { StorageEntry(mediaType: $0 % 3, year: 2000 + $0 % 30, bytes: Int64($0)) }
        let start = Date()
        _ = StorageMath.summarize(entries)
        let elapsed = Date().timeIntervalSince(start)
        XCTAssertLessThan(elapsed, 0.5, "10k 聚合耗时 \(elapsed)s")
    }
}
