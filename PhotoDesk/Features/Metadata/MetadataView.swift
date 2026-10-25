// MARK: - 职责说明：信息面板（docs/05 M5 任务 5.6 / docs/04 §4.13）——
// 尺寸/字节数/格式（PHAssetResource originalFilename 后缀 + UTType）+ EXIF 行
// （requestContentEditingInput → CGImageSource → MetadataParser）+ GPS 小地图（SwiftUI Map 单针，iOS 14+）。
// 解析纯逻辑在 MetadataParser（可单测）；本视图只做取图与展示。

import SwiftUI
import Photos
import ImageIO
import UniformTypeIdentifiers
import MapKit

struct MetadataView: View {
    let item: PhotoItem

    @State private var fields = MetadataFields()
    @State private var byteSize: Int64 = 0
    @State private var formatText = "—"

    private static let byteFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter
    }()

    var body: some View {
        List {
            Section("基本信息") {
                row("尺寸", "\(item.pixelWidth) × \(item.pixelHeight)")
                row("大小", byteSize > 0 ? Self.byteFormatter.string(fromByteCount: byteSize) : "未知")
                row("格式", formatText)
                if let duration = durationText {
                    row("时长", duration)
                }
                if let created = item.creationDate {
                    row("拍摄时间", Self.dateFormatter.string(from: created))
                }
            }

            Section("相机") {
                if let model = fields.deviceModel { row("设备", model) }
                if let lens = fields.lensModel { row("镜头", lens) }
                if let aperture = MetadataParser.apertureText(fields.fNumber) { row("光圈", aperture) }
                if let shutter = MetadataParser.shutterText(fields.exposureTime) { row("快门", shutter) }
                if let iso = fields.iso { row("ISO", "\(iso)") }
                if let focal = fields.focalLength { row("焦距", String(format: "%.0f mm", focal)) }
                if let flash = fields.didFireFlash { row("闪光灯", flash ? "已开启" : "未开启") }
                if fields.deviceModel == nil && fields.lensModel == nil {
                    Text("无 EXIF 信息（截图或已剥离元数据的图片）")
                        .font(.caption)
                        .foregroundColor(Color(ds: DSColor.textSecondary))
                }
            }

            if let latitude = fields.gpsLatitude, let longitude = fields.gpsLongitude {
                Section("位置") {
                    row("坐标", String(format: "%.5f, %.5f", latitude, longitude))
                    miniMap(latitude: latitude, longitude: longitude)
                        .frame(height: 140)
                        .listRowInsets(EdgeInsets())
                        .accessibilityLabel("位置小地图，坐标 \(String(format: "%.2f", latitude)), \(String(format: "%.2f", longitude))")
                }
            } else {
                Section("位置") {
                    Text("无位置信息")
                        .font(.caption)
                        .foregroundColor(Color(ds: DSColor.textSecondary))
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("信息")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    // MARK: - 子视图

    private func row(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
                .foregroundColor(Color(ds: DSColor.textPrimary))
            Spacer()
            Text(value)
                .foregroundColor(Color(ds: DSColor.textSecondary))
                .textSelection(.enabled)   // 元数据可复制（docs/04 §6 便利性）
        }
        .font(.subheadline)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title) \(value)")
    }

    private func miniMap(latitude: Double, longitude: Double) -> some View {
        let coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        return Map(coordinateRegion: .constant(MKCoordinateRegion(
            center: coordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
        ))) {   // SwiftUI Map + 单针（iOS 14+，AGENTS.md 允许 MapKit）
            MapMarker(coordinate: coordinate, tint: UIColor(ds: DSColor.tint))
        }
        .allowsHitTesting(false)   // 面板内地图禁手势（不与列表滚动冲突）
    }

    private var durationText: String? {
        guard item.mediaType == .video, item.duration > 0 else { return nil }
        let seconds = Int(item.duration.rounded())
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy年M月d日 HH:mm"
        return formatter
    }()

    // MARK: - 取图与解析

    private func load() async {
        loadBasics()
        await loadEXIF()
    }

    /// 字节数 + 格式（PHAssetResource；fileSize KVC 失败回退 0——M1 KVC 崩溃教训）
    private func loadBasics() {
        let assets = PHAsset.fetchAssets(withLocalIdentifiers: [item.id], options: nil)
        guard let asset = assets.firstObject else { return }
        let resources = PHAssetResource.assetResources(for: asset)
        let resource = resources.first { $0.type == .photo }
            ?? resources.first { $0.type == .fullSizePhoto }
            ?? resources.first { $0.type == .video }
            ?? resources.first
        guard let resource else { return }
        byteSize = (try? resource.value(forKey: "fileSize") as? Int64) ?? 0
        let filename = resource.originalFilename
        let ext = (filename as NSString).pathExtension
        if let uti = resource.uniformTypeIdentifier, let type = UTType(uti) {
            formatText = type.preferredLocalizedString ?? ext.uppercased()
        } else if !ext.isEmpty {
            formatText = ext.uppercased()
        }
    }

    /// EXIF：requestContentEditingInput（禁网络）→ CGImageSource 属性 → MetadataParser
    private func loadEXIF() async {
        let assets = PHAsset.fetchAssets(withLocalIdentifiers: [item.id], options: nil)
        guard let asset = assets.firstObject else { return }
        let options = PHContentEditingInputRequestOptions()
        options.isNetworkAccessAllowed = false
        let input: PHContentEditingInput? = await withCheckedContinuation { continuation in
            asset.requestContentEditingInput(with: options) { input, _ in
                continuation.resume(returning: input)
            }
        }
        guard let url = input?.fullSizeImageURL,
              let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any] else {
            return
        }
        fields = MetadataParser.parse(properties: properties)
    }
}
