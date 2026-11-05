// MARK: - 职责说明：R06 分类菜单装配回归守卫（docs/16 M12 §3.3）——
// 随实现落地（新代码无基线可红）；语义锁定 5 项顺序/勾选/计数/hidden 不泄露/.limited 管理入口。

import XCTest
@testable import PhotoDesk

final class LibraryCategoryMenuBuilderTests: XCTestCase {
    func testFiveScopesInOrderWithSelectionAndCounts() {
        let items = LibraryCategoryMenuBuilder.items(currentScope: .favorites,
                                                     isLimitedAccess: false,
                                                     counts: [.all: 100, .videos: 8, .screenshots: 3],
                                                     currentCount: 12)
        XCTAssertEqual(items.count, 5)
        XCTAssertEqual(items.map(\.title), ["全部", "收藏", "视频", "截图", "已隐藏"])
        XCTAssertEqual(items[0].displayTitle, "全部 · 100")
        XCTAssertEqual(items[1].displayTitle, "收藏 · 12", "当前项计数用 filteredItems.count")
        XCTAssertEqual(items[1].isSelected, true, "勾选由 query.scope 派生")
        XCTAssertEqual(items[2].displayTitle, "视频 · 8")
        XCTAssertNil(items[4].countText, "已隐藏解锁前不泄露数量")
        XCTAssertNil(items[4].scope, "已隐藏不走 setScope（弹 Vault）")
        XCTAssertFalse(items.contains { $0.isLimitedManagement }, "非 .limited 无管理入口")
    }

    func testLimitedAccessAddsManagementEntry() {
        let items = LibraryCategoryMenuBuilder.items(currentScope: .all,
                                                     isLimitedAccess: true,
                                                     counts: [:],
                                                     currentCount: 5)
        XCTAssertEqual(items.count, 6)
        let management = items.last
        XCTAssertEqual(management?.title, "管理可见照片")
        XCTAssertEqual(management?.isLimitedManagement, true)
        XCTAssertNil(management?.scope, "管理入口不走 setScope")
    }

    func testNilCountsOmitCountSuffix() {
        let items = LibraryCategoryMenuBuilder.items(currentScope: .all,
                                                     isLimitedAccess: false,
                                                     counts: [:],
                                                     currentCount: 5)
        XCTAssertEqual(items[1].displayTitle, "收藏", "异步计数未就绪 → 不带计数后缀")
    }
}
