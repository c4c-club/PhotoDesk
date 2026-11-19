// MARK: - 职责说明：行带展开后的最小选择单元（M19 T03，docs/42 §3.1/§10.1）——
// Core 只产数值 (section,item)，不做 id 映射（App 经 Diffable dataSource.itemIdentifier 换算，
// 见 docs/42 §10.1 裁决：不新增 RowBandExpander.swift / resolve 闭包，避免 Core 持有 id 通道耦合）。
// scope 过滤不在此层：展开产纯数值，id 级 scope 过滤由 SlideSelectTrail.consume 承担。

import Foundation

/// 行带展开单元：段内第 item 个 item（列升序由展开方保证）。
public struct RowBandItem: Hashable, Sendable {
    public let section: Int
    public let item: Int

    public init(section: Int, item: Int) {
        self.section = section
        self.item = item
    }
}
