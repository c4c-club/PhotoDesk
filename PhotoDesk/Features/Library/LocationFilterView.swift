// MARK: - 职责说明：位置筛选（docs/09 D10）——离线 0.25° 网格聚类列表（GeoClusterer），
// 每行显示坐标 + 张数；选中后按 25 km 半径筛选。不请求定位权限、不联网、不做反向地理编码（红线）。

import SwiftUI
import PhotoDeskCore

struct LocationFilterView: View {
    /// 参与聚类的条目（当前 scope 全量）
    let items: [PhotoItem]
    /// 当前位置筛选（.any = 未选）
    let selected: LocationFilter
    /// 选择回调（nil 不会出现——用 .any 表示不限）
    var onSelect: (LocationFilter) -> Void
    @Environment(\.dismiss) private var dismiss

    /// 聚类结果（count 降序）
    private var clusters: [GeoCluster] {
        let points = items.compactMap { item -> GeoPoint? in
            guard let coordinate = item.location?.coordinate else { return nil }
            return GeoPoint(latitude: coordinate.latitude, longitude: coordinate.longitude)
        }
        return GeoClusterer.clusters(points: points)
    }

    var body: some View {
        NavigationView {
            List {
                Section {
                    Button {
                        onSelect(.any)
                        dismiss()
                    } label: {
                        HStack {
                            Text("不限位置")
                                .foregroundColor(Color(ds: DSColor.textPrimary))
                            Spacer()
                            if isSelected(.any) {
                                Image(systemName: "checkmark")
                                    .foregroundColor(Color(ds: DSColor.tint))
                            }
                        }
                    }

                    Button {
                        onSelect(.withLocation)
                        dismiss()
                    } label: {
                        HStack {
                            Text("有位置信息的照片")
                                .foregroundColor(Color(ds: DSColor.textPrimary))
                            Spacer()
                            if isSelected(.withLocation) {
                                Image(systemName: "checkmark")
                                    .foregroundColor(Color(ds: DSColor.tint))
                            }
                        }
                    }

                    Button {
                        onSelect(.withoutLocation)
                        dismiss()
                    } label: {
                        HStack {
                            Text("无位置信息的照片")
                                .foregroundColor(Color(ds: DSColor.textPrimary))
                            Spacer()
                            if isSelected(.withoutLocation) {
                                Image(systemName: "checkmark")
                                    .foregroundColor(Color(ds: DSColor.tint))
                            }
                        }
                    }
                }

                Section("拍摄地点聚类（约 25 km 范围）") {
                    if clusters.isEmpty {
                        Text("还没有带位置信息的照片")
                            .foregroundColor(Color(ds: DSColor.textSecondary))
                    } else {
                        ForEach(Array(clusters.prefix(50).enumerated()), id: \.offset) { _, cluster in
                            Button {
                                onSelect(.near(GeoRegion(center: cluster.center, radiusKm: 25)))
                                dismiss()
                            } label: {
                                HStack {
                                    Image(systemName: "mappin.circle.fill")
                                        .foregroundColor(Color(ds: DSColor.tint))
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(coordinateText(cluster.center))
                                            .font(.subheadline)
                                            .foregroundColor(Color(ds: DSColor.textPrimary))
                                        Text("\(cluster.count) 张")
                                            .font(.caption)
                                            .foregroundColor(Color(ds: DSColor.textSecondary))
                                    }
                                    Spacer()
                                    if case .near(let region) = selected,
                                       GeoMath.distanceKm(cluster.center, region.center) < 0.01 {
                                        Image(systemName: "checkmark")
                                            .foregroundColor(Color(ds: DSColor.tint))
                                    }
                                }
                            }
                        }
                    }
                }

                Section {
                    Text("位置筛选完全离线：不请求定位权限，不上传任何数据。")
                        .font(.caption)
                        .foregroundColor(Color(ds: DSColor.textSecondary))
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("位置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                Button("完成") { dismiss() }
            }
        }
        .navigationViewStyle(.stack)
    }

    private func isSelected(_ filter: LocationFilter) -> Bool {
        switch (selected, filter) {
        case (.any, .any), (.withLocation, .withLocation), (.withoutLocation, .withoutLocation):
            return true
        case (.near(let a), .near(let b)):
            return GeoMath.distanceKm(a.center, b.center) < 0.01 && a.radiusKm == b.radiusKm
        default:
            return false
        }
    }

    private func coordinateText(_ point: GeoPoint) -> String {
        let lat = point.latitude >= 0 ? String(format: "%.1f°N", point.latitude)
                                      : String(format: "%.1f°S", -point.latitude)
        let lon = point.longitude >= 0 ? String(format: "%.1f°E", point.longitude)
                                       : String(format: "%.1f°W", -point.longitude)
        return "\(lat), \(lon) 附近"
    }
}
