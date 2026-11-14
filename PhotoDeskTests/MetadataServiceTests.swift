// MARK: - 职责说明：元数据服务测试（M17 T08 X06，docs/31 §3）——
// 字节数/格式/EXIF 解析全部下沉服务（Feature 层零 PHAsset）；解析在后台线程。
// CI 模拟器有种库（sim-photos-dated.sh 2）：真 PhotoKit 通道验证；空库跳过。

import XCTest
import Photos
@testable import PhotoDesk

@MainActor
final class MetadataServiceTests: XCTestCase {

    func testBasicsForFirstLibraryAsset() async throws {
        let fetch = PHAsset.fetchAssets(with: nil, options: nil)
        guard fetch.count > 0 else {
            throw XCTSkip("模拟器相册为空：真库通道用例跳过（本地不误伤）")
        }
        let asset = fetch.object(at: 0)
        let service = PhotoMetadataService()
        let basics = await service.basics(for: asset.localIdentifier)
        XCTAssertNotNil(basics, "有种库资源必须返回基础信息")
        XCTAssertFalse(basics?.filename.isEmpty ?? true, "originalFilename 不得为空")
    }

    func testExifFieldsForFirstLibraryAsset() async throws {
        let fetch = PHAsset.fetchAssets(with: nil, options: nil)
        guard fetch.count > 0 else {
            throw XCTSkip("模拟器相册为空：真库通道用例跳过（本地不误伤）")
        }
        let asset = fetch.object(at: 0)
        guard asset.mediaType == .image else {
            throw XCTSkip("首资源非照片：EXIF 通道用例跳过")
        }
        let service = PhotoMetadataService()
        let fields = await service.exifFields(for: asset.localIdentifier)
        XCTAssertNotNil(fields, "照片 EXIF 解析不得失败（服务内禁网络取件）")
    }
}