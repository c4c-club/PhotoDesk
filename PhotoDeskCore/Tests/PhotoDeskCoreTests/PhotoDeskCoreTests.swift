// MARK: - 职责说明：P-1 冒烟测试——验证 PhotoDeskCore 在 Linux（Docker swift:6.0-noble）与 CI core-linux 上可编译、可测试。

import XCTest
import PhotoDeskCore

final class PhotoDeskCoreSmokeTests: XCTestCase {
    func testPackageCompilesAndLinks() {
        XCTAssertEqual(PhotoDeskCoreInfo.placeholderVersion, "0.1.0")
    }
}
