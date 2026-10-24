// MARK: - 职责说明：App 侧冒烟测试——验证 iOS target 与 PhotoDeskCore 本地包的编译与链接（CI build job 的 test 步骤执行）。

import XCTest
import PhotoDeskCore

final class CoreLinkSmokeTests: XCTestCase {
    func testCorePackageIsLinked() {
        XCTAssertFalse(PhotoDeskCoreInfo.placeholderVersion.isEmpty)
    }
}
