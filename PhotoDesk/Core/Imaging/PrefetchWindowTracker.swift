// MARK: - 职责说明：预取窗口差量追踪器（docs/13 §3.2 S02）——
// 维护当前预取 id 集合与像素尺寸；每次调用产出「需要 stop 的旧 id + 需要start 的新 id」，
// 窗口上限 7；尺寸变化时旧尺寸全停、新尺寸全开。纯逻辑、可注入尺寸，单测覆盖；
// ImagePipeline 拿到 Delta 后只做 PhotoKit 调用。

import CoreGraphics
import Foundation

/// 一次预取更新的差量（stopSize 为 nil 时表示无需 stop）
struct PrefetchDelta: Equatable {
    let stopIDs: [String]
    let stopSize: CGSize?
    let startIDs: [String]
    let startSize: CGSize?

    static let none = PrefetchDelta(stopIDs: [], stopSize: nil, startIDs: [], startSize: nil)
}

final class PrefetchWindowTracker {
    let windowLimit: Int
    private(set) var currentIDs: Set<String> = []
    private(set) var pixelSize: CGSize?

    init(windowLimit: Int = 7) {
        self.windowLimit = max(1, windowLimit)
    }

    /// - Parameters:
    ///   - ids: 期望预取的 id（超过窗口上限时截断，保持调用方顺序）
    ///   - size: 像素尺寸
    /// - Returns: 需要执行的 PhotoKit stop/start（无变化返回 .none）
    func update(ids: [String], size: CGSize) -> PrefetchDelta {
        guard !ids.isEmpty else {
            let stopIDs = currentIDs
            let stopSize = pixelSize
            currentIDs = []
            pixelSize = nil
            if stopIDs.isEmpty {
                return .none
            }
            return PrefetchDelta(stopIDs: Array(stopIDs), stopSize: stopSize, startIDs: [], startSize: nil)
        }
        let window = Set(ids.prefix(windowLimit))
        let oldIDs = currentIDs
        let oldSize = pixelSize
        let sizeChanged = oldSize != size

        if sizeChanged {
            // 尺寸变化：旧 id 全部按旧尺寸停（尺寸不匹配的 stopCachingImages 不会真正停掉）
            let startIDs = window.subtracting(oldIDs)
            currentIDs = window
            pixelSize = size
            if oldIDs.isEmpty {
                return PrefetchDelta(stopIDs: [], stopSize: nil,
                                     startIDs: window.sorted(), startSize: size)
            }
            return PrefetchDelta(stopIDs: oldIDs.sorted(), stopSize: oldSize,
                                 startIDs: window.sorted(), startSize: size)
        }

        let stopIDs = oldIDs.subtracting(window)
        let startIDs = window.subtracting(oldIDs)
        currentIDs = window
        pixelSize = size
        if stopIDs.isEmpty && startIDs.isEmpty {
            return .none
        }
        return PrefetchDelta(stopIDs: stopIDs.sorted(), stopSize: oldSize,
                             startIDs: startIDs.sorted(), startSize: size)
    }

    /// 移除单个 id（cancel(id:) 用）：若在窗口内，返回该 id 的 stop delta
    func remove(_ id: String) -> PrefetchDelta {
        guard currentIDs.contains(id) else { return .none }
        currentIDs.remove(id)
        return PrefetchDelta(stopIDs: [id], stopSize: pixelSize, startIDs: [], startSize: nil)
    }

    /// 全部停止（cancelAll / 内存警告）
    func reset() -> PrefetchDelta {
        guard !currentIDs.isEmpty else { return .none }
        let delta = PrefetchDelta(stopIDs: currentIDs.sorted(), stopSize: pixelSize,
                                  startIDs: [], startSize: nil)
        currentIDs = []
        pixelSize = nil
        return delta
    }
}
