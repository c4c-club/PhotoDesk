// MARK: - 职责说明：ViewerViewModel 单元测试（docs/09 Phase 4；docs/13 S12 删除事务适配）——
// assetID 定位；删除事务 plan（不改数组）→ commit（在 batch block 内调用）→ rollback；
// 上滑→底补/下滑→顶补/末尾回卷/空列表关闭；滑动 0 次 PhotoKit 写、staged 撤销恢复、收藏即时写。

import XCTest
import PhotoDeskCore
@testable import PhotoDesk

@MainActor
final class ViewerViewModelTests: XCTestCase {
    private var settings: SettingsStore!
    private var writer: MockPhotoWriter!
    private var session: ReviewSessionController!
    private var persistence: PersistenceController!

    override func setUp() async throws {
        settings = SettingsStore()
        writer = MockPhotoWriter()
        persistence = PersistenceController(inMemory: true)
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("ViewerVMTests-\(UUID().uuidString)", isDirectory: true)
        session = ReviewSessionController(store: PendingActionStore(directoryOverride: tmp),
                                          writer: writer, trashBin: nil, settings: settings)
    }

    private func makeItem(_ index: Int) -> PhotoItem {
        PhotoItem(id: "id-\(index)",
                  mediaType: .image,
                  mediaSubtypes: [],
                  creationDate: Date(timeIntervalSince1970: 1_700_000_000 + TimeInterval(index * 3_600)),
                  modificationDate: nil,
                  pixelWidth: 10, pixelHeight: 10, duration: 0,
                  isFavorite: false, isHidden: false,
                  location: nil, burstIdentifier: nil, isCloudOnly: false)
    }

    private func makeViewModel(items: [PhotoItem], startItemID: String) -> ViewerViewModel {
        ViewerViewModel(context: ViewerContext(items: items, startItemID: startItemID, queryKey: "test"),
                        settings: settings,
                        writer: writer,
                        trashBin: TrashBin(persistence: persistence, settings: settings),
                        undoCenter: UndoCenter(writer: writer, trashBin: nil, persistence: persistence),
                        reviewSession: session)
    }

    /// plan + commit 的便捷封装（模拟 VC 事务路径）
    @discardableResult
    private func planAndCommit(_ vm: ViewerViewModel, _ action: SwipeAction, id: String,
                               exitEdge: VerticalEdge?) -> ViewerViewModel.StagedPlan? {
        guard let staged = vm.planRemoval(action: action, forItemID: id, exitEdge: exitEdge) else { return nil }
        _ = vm.commitRemoval(staged)
        return staged
    }

    // MARK: - D01 定位

    func testInitialPositionByAssetID() {
        let items = (0..<10).map { makeItem($0) }
        let vm = makeViewModel(items: items, startItemID: "id-7")
        XCTAssertEqual(vm.currentIndex, 7, "按 assetID 定位，不再永远停在第 1 张")
        XCTAssertEqual(vm.current?.id, "id-7")
    }

    func testMissingStartItemFallsBackToZero() {
        let items = (0..<5).map { makeItem($0) }
        let vm = makeViewModel(items: items, startItemID: "missing")
        XCTAssertEqual(vm.currentIndex, 0)
    }

    // MARK: - S12 删除事务：上滑→底补 / 下滑→顶补

    func testPlanCommitSwipeUpEntryFromBottom() {
        let items = (0..<10).map { makeItem($0) }
        let vm = makeViewModel(items: items, startItemID: "id-3")
        let staged = vm.planRemoval(action: .moveToRecentlyDeleted, forItemID: "id-3", exitEdge: .top)
        XCTAssertNotNil(staged)
        XCTAssertEqual(staged?.plan.nextIndex, 3, "保持 index（原 i+1 顶上来），不跳张")
        XCTAssertEqual(staged?.plan.entryEdge, .bottom, "上滑 → 底部补位")
        XCTAssertEqual(staged?.removedItem.id, "id-3")
        XCTAssertEqual(vm.items.count, 10, "plan 不改 items（S12 不变量：数组只在 commit 中变）")
        XCTAssertEqual(vm.currentIndex, 3, "plan 不改 currentIndex")
        _ = vm.commitRemoval(staged!)
        XCTAssertEqual(vm.items.count, 9)
        XCTAssertEqual(vm.current?.id, "id-4")
        XCTAssertEqual(writer.moveToRecentlyDeletedCallCount, 0, "滑动路径 0 次 PhotoKit 写")
        XCTAssertEqual(session.pendingDeleteCount, 1)
    }

    func testPlanCommitSwipeDownEntryFromTop() {
        let items = (0..<10).map { makeItem($0) }
        let vm = makeViewModel(items: items, startItemID: "id-3")
        let staged = vm.planRemoval(action: .hide, forItemID: "id-3", exitEdge: .bottom)
        XCTAssertEqual(staged?.plan.entryEdge, .top, "下滑 → 顶部补位")
        _ = vm.commitRemoval(staged!)
        XCTAssertEqual(session.pendingHideCount, 1)
    }

    func testPlanCommitAtEndRollsBack() {
        let items = (0..<5).map { makeItem($0) }
        let vm = makeViewModel(items: items, startItemID: "id-4")
        let staged = planAndCommit(vm, .moveToRecentlyDeleted, id: "id-4", exitEdge: .top)
        XCTAssertEqual(staged?.plan.nextIndex, 3, "末尾回退上一张")
        XCTAssertEqual(staged?.plan.entryEdge, .top, "回卷：与飞出边相同")
        XCTAssertFalse(staged!.plan.shouldClose)
        XCTAssertEqual(vm.current?.id, "id-3")
    }

    func testPlanCommitEmptyListShouldClose() {
        let items = [makeItem(0)]
        let vm = makeViewModel(items: items, startItemID: "id-0")
        let staged = planAndCommit(vm, .moveToRecentlyDeleted, id: "id-0", exitEdge: .bottom)
        XCTAssertEqual(staged?.plan.shouldClose, true, "列表删空 → 关闭查看器")
        XCTAssertTrue(vm.items.isEmpty)
        XCTAssertEqual(vm.currentIndex, 0, "空列表 index 归 0（不变量 I2）")
    }

    func testPlanToolbarDeleteDefaultsToBottom() {
        let items = (0..<5).map { makeItem($0) }
        let vm = makeViewModel(items: items, startItemID: "id-2")
        let staged = vm.planRemoval(action: .moveToRecentlyDeleted, forItemID: "id-2", exitEdge: nil)
        XCTAssertEqual(staged?.plan.entryEdge, .bottom, "工具栏无手势 → 默认底部前进")
        XCTAssertEqual(vm.items.count, 5, "plan 不改 items")
    }

    // MARK: - D16：连续滑动 0 次 writer、提交 1 次

    func testTwentyStagesZeroWriterCallsCommitOnce() async {
        let items = (0..<25).map { makeItem($0) }
        let vm = makeViewModel(items: items, startItemID: "id-0")
        for item in items.prefix(20) {
            XCTAssertNotNil(planAndCommit(vm, .moveToRecentlyDeleted, id: item.id, exitEdge: .top))
        }
        XCTAssertEqual(writer.moveToRecentlyDeletedCallCount, 0)
        XCTAssertEqual(session.pendingDeleteCount, 20)
        XCTAssertEqual(vm.items.count, 5, "本地移除 20 张")

        let result = await session.commitDeletes()
        XCTAssertEqual(result.committed, 20)
        XCTAssertEqual(writer.moveToRecentlyDeletedCallCount, 1, "一次批量提交 = 1 次系统确认")
        XCTAssertEqual(writer.moveToRecentlyDeletedCalls.first?.count, 20)
    }

    // MARK: - 撤销恢复

    func testUndoStagedRestoresItem() {
        let items = (0..<5).map { makeItem($0) }
        let vm = makeViewModel(items: items, startItemID: "id-2")
        _ = planAndCommit(vm, .moveToRecentlyDeleted, id: "id-2", exitEdge: .top)
        XCTAssertEqual(vm.items.count, 4)

        vm.undoStaged()
        XCTAssertEqual(vm.items.count, 5, "staged 撤销：本地还原")
        XCTAssertEqual(vm.items[2].id, "id-2", "还原到原 index")
        XCTAssertEqual(vm.current?.id, "id-2")
        XCTAssertEqual(session.pendingDeleteCount, 0, "队列同步移除")
        XCTAssertEqual(writer.moveToRecentlyDeletedCallCount, 0, "撤销零 PhotoKit 写")
        XCTAssertFalse(vm.hasUndoableStaged)
    }

    // MARK: - 收藏仍即时写（不前进）

    func testFavoriteStillWritesImmediately() async {
        let items = (0..<3).map { makeItem($0) }
        let vm = makeViewModel(items: items, startItemID: "id-1")
        let indexBefore = vm.currentIndex
        let outcome = await vm.execute(.favorite, for: items[1])
        guard case .success(_, let toastText, let undoKind) = outcome else {
            return XCTFail("收藏应成功")
        }
        XCTAssertEqual(toastText, "已收藏")
        XCTAssertEqual(undoKind, .favorite)
        XCTAssertEqual(writer.setFavoriteCallCount, 1)
        XCTAssertEqual(vm.currentIndex, indexBefore, "收藏不自动前进")
    }
}
