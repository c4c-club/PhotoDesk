// MARK: - 职责说明：PhotoLibraryService 授权刷新单测（docs/49 T02 §3.1）——
// 注入 statusProvider/requestProvider 验证 refreshAccess / requestAccess / requestAccessIfNeeded
// 状态机与映射规则，不触碰真实 PHPhotoLibrary（CI 模拟器已预授权，注入保证确定性）。

import XCTest
import Photos
@testable import PhotoDesk

@MainActor
final class PhotoLibraryServiceTests: XCTestCase {

    // MARK: - 注入（docs/49 T02 §3.1）

    func testInitialAccessInjectionCoversAllStates() {
        for state in [LibraryAccess.notDetermined, .denied, .restricted, .limited, .authorized] {
            XCTAssertEqual(PhotoLibraryService(initialAccess: state).access, state,
                           "initialAccess=\(state) 必须原样生效")
        }
    }

    // MARK: - refreshAccess（denied → authorized 更新并发布）

    func testRefreshAccessUpdatesAccessOnStatusChange() {
        var current: PHAuthorizationStatus = .denied
        let service = PhotoLibraryService(statusProvider: { current })
        XCTAssertEqual(service.access, .denied)
        XCTAssertEqual(service.refreshAccess(), .denied, "状态未变：返回原值且不改发布")
        current = .authorized
        let latest = service.refreshAccess()
        XCTAssertEqual(latest, .authorized, "denied → authorized 必须刷新成功")
        XCTAssertEqual(service.access, .authorized, "access 必须更新（@Published 发布变化）")
    }

    // MARK: - requestAccess 映射（requestProvider 注入）

    func testRequestAccessMapsLimited() async {
        let service = PhotoLibraryService(initialAccess: .notDetermined,
                                          requestProvider: { .limited })
        await service.requestAccess()
        XCTAssertEqual(service.access, .limited, "requestProvider 返回 limited 必须映射为 .limited")
    }

    // MARK: - requestAccessIfNeeded（仅 notDetermined 弹框）

    func testRequestAccessIfNeededOnlyRequestsWhenNotDetermined() async {
        var requestCount = 0
        var current: PHAuthorizationStatus = .denied
        let service = PhotoLibraryService(statusProvider: { current },
                                          requestProvider: { requestCount += 1; return .authorized })
        await service.requestAccessIfNeeded()
        XCTAssertEqual(requestCount, 0, "denied 状态不得请求授权（不假装成功），只刷新")
        XCTAssertEqual(service.access, .denied)
        current = .authorized
        await service.requestAccessIfNeeded()
        XCTAssertEqual(requestCount, 0, "非 notDetermined 一律只刷新")
        XCTAssertEqual(service.access, .authorized, "denied → authorized 经刷新生效")

        let intro = PhotoLibraryService(initialAccess: .notDetermined,
                                        requestProvider: { requestCount += 1; return .limited })
        await intro.requestAccessIfNeeded()
        XCTAssertEqual(requestCount, 1, "仅 notDetermined 才触发系统请求")
        XCTAssertEqual(intro.access, .limited)
    }

    // MARK: - 映射规则（现有 map，未知状态 @unknown default → .denied）

    func testMapCoversAllKnownStatuses() {
        XCTAssertEqual(PhotoLibraryService.map(.notDetermined), .notDetermined)
        XCTAssertEqual(PhotoLibraryService.map(.denied), .denied)
        XCTAssertEqual(PhotoLibraryService.map(.restricted), .restricted)
        XCTAssertEqual(PhotoLibraryService.map(.limited), .limited)
        XCTAssertEqual(PhotoLibraryService.map(.authorized), .authorized)
    }
}
