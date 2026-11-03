// MARK: - 职责说明：ViewerViewModel 删除事务单元测试（docs/13 S12 验收 ≥8 条）——
// plan 不改数组/currentIndex；commit 首/中/末/唯一/连续两次/失配防御；rollback 恢复原位。

import XCTest
import PhotoDeskCore
@testable import PhotoDesk

@MainActor
final class ViewerRemovalPlannerTests: XCTestCase {
    private var settings: SettingsStore!
    private var writer: MockPhotoWriter!
    private var session: ReviewSessionController!
    private var persistence: PersistenceController!
    private var vm: ViewerViewModel!

    override func setUp() async throws {
        settings = SettingsStore()
        writer = MockPhotoWriter()
        persistence = PersistenceController(inMemory: true)
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("ViewerRemovalTests-\(UUID().uuidString)", isDirectory: true)
        session = ReviewSessionController(store: PendingActionStore(directoryOverride: tmp),
                                          writer: writer, trashBin: nil, settings: settings)
        let items = (0..<10).map { Self.makeItem($0) }
        vm = makeViewModel(items: items, startItemID: "id-0")
    }

    private static func makeItem(_ index: Int) -> PhotoItem {
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

    // MARK: - 1. plan 只入队 + 算 plan，不改数组 / currentIndex

    func testPlanDoesNotMutateItemsOrIndex() {
        let staged = vm.planRemoval(action: .moveToRecentlyDeleted, forItemID: "id-5", exitEdge: .bottom)
        XCTAssertNotNil(staged)
        XCTAssertEqual(vm.items.count, 10, "plan 不得改 items")
        XCTAssertEqual(vm.currentIndex, 0, "plan 不得改 currentIndex")
        XCTAssertEqual(session.pendingDeleteCount, 1, "plan 只入队")
        XCTAssertEqual(writer.moveToRecentlyDeletedCallCount, 0, "plan 零 PhotoKit 写")
    }

    // MARK: - 2. 删首张：index 保持 0，显示原第二张

    func testCommitFirstShowsNext() {
        let staged = vm.planRemoval(action: .moveToRecentlyDeleted, forItemID: "id-0", exitEdge: .bottom)!
        let result = vm.commitRemoval(staged)
        XCTAssertEqual(result.nextIndex, 0, "删首张后原第二张顶到 0")
        XCTAssertEqual(result.shouldClose, false)
        XCTAssertEqual(vm.current?.id, "id-1")
        XCTAssertEqual(vm.items.count, 9)
    }

    // MARK: - 3. 删中间：保持 index

    func testCommitMiddleStaysAtSameIndex() {
        vm.updateIndex(5)
        let staged = vm.planRemoval(action: .hide, forItemID: "id-5", exitEdge: .top)!
        let result = vm.commitRemoval(staged)
        XCTAssertEqual(result.nextIndex, 5)
        XCTAssertEqual(result.shouldClose, false)
        XCTAssertEqual(vm.current?.id, "id-6")
    }

    // MARK: - 4. 删末张：回退上一张

    func testCommitLastRollsBackToPrevious() {
        vm.updateIndex(9)
        let staged = vm.planRemoval(action: .moveToRecentlyDeleted, forItemID: "id-9", exitEdge: .top)!
        let result = vm.commitRemoval(staged)
        XCTAssertEqual(result.nextIndex, 8, "末张删除回退上一张")
        XCTAssertEqual(vm.current?.id, "id-8")
    }

    // MARK: - 5. 唯一一张：shouldClose + items 空 + index 归 0

    func testCommitOnlyItemCloses() {
        let single = [Self.makeItem(0)]
        let singleVM = makeViewModel(items: single, startItemID: "id-0")
        let staged = singleVM.planRemoval(action: .moveToRecentlyDeleted, forItemID: "id-0", exitEdge: .bottom)!
        let result = singleVM.commitRemoval(staged)
        XCTAssertEqual(result.shouldClose, true, "唯一一张删除 → 关闭查看器")
        XCTAssertTrue(singleVM.items.isEmpty)
        XCTAssertEqual(singleVM.currentIndex, 0)
    }

    // MARK: - 6. 连续两次 plan→commit：数组与 index 一致（不变量 I1/I2）

    func testTwoConsecutiveTransactionsConsistent() {
        let first = vm.planRemoval(action: .moveToRecentlyDeleted, forItemID: "id-0", exitEdge: .bottom)!
        let firstResult = vm.commitRemoval(first)
        XCTAssertEqual(vm.items.count, 9)
        XCTAssertEqual(vm.current?.id, "id-1")

        let second = vm.planRemoval(action: .moveToRecentlyDeleted, forItemID: "id-1", exitEdge: .bottom)!
        let secondResult = vm.commitRemoval(second)
        XCTAssertEqual(vm.items.count, 8)
        XCTAssertEqual(firstResult.nextIndex, 0)
        XCTAssertEqual(secondResult.nextIndex, 0)
        XCTAssertEqual(vm.current?.id, "id-2")
        XCTAssertEqual(vm.currentIndex, 0)
        XCTAssertEqual(session.pendingDeleteCount, 2)
    }

    // MARK: - 7. plan 失配数组时 commit 防御（不越界、不崩）

    func testCommitWithMismatchedArrayIsClamped() {
        let staged = vm.planRemoval(action: .moveToRecentlyDeleted, forItemID: "id-0", exitEdge: .bottom)!
        // plan 之后、commit 之前数组被外部改动（模拟回滚后重复提交）
        vm.updateIndex(3)
        let result = vm.commitRemoval(staged)
        XCTAssertEqual(vm.items.count, 9)
        XCTAssertTrue(vm.currentIndex < max(1, vm.items.count), "commit 后 index 必须在 0..<count")
        XCTAssertNotNil(result)
    }

    // MARK: - 8. rollback 恢复原位 + 队列清空

    func testRollbackRestoresItemAtOriginalIndex() {
        vm.updateIndex(4)
        let staged = vm.planRemoval(action: .moveToRecentlyDeleted, forItemID: "id-4", exitEdge: .top)!
        _ = vm.commitRemoval(staged)
        XCTAssertEqual(vm.items.count, 9)

        vm.rollbackRemoval(staged)
        XCTAssertEqual(vm.items.count, 10, "rollback 恢复 item")
        XCTAssertEqual(vm.items[4].id, "id-4", "恢复到原 index")
        XCTAssertEqual(vm.currentIndex, 4)
        XCTAssertEqual(session.pendingDeleteCount, 0, "rollback 同步清队列")
        XCTAssertEqual(writer.moveToRecentlyDeletedCallCount, 0)
    }

    // MARK: - 9. rollback 后重复 rollback 不重复插入

    func testDoubleRollbackDoesNotDuplicate() {
        let staged = vm.planRemoval(action: .hide, forItemID: "id-3", exitEdge: .bottom)!
        _ = vm.commitRemoval(staged)
        vm.rollbackRemoval(staged)
        vm.rollbackRemoval(staged)
        XCTAssertEqual(vm.items.count, 10, "重复 rollback 不得重复插入")
        XCTAssertEqual(session.pendingHideCount, 0)
    }

    // MARK: - 10. commit 后 isFavoriteCurrent 刷新为新当前项

    func testCommitRefreshesFavoriteState() {
        var items = (0..<3).map { Self.makeItem($0) }
        items[1] = PhotoItem(id: items[1].id,
                             mediaType: items[1].mediaType,
                             mediaSubtypes: items[1].mediaSubtypes,
                             creationDate: items[1].creationDate,
                             modificationDate: nil,
                             pixelWidth: 10, pixelHeight: 10, duration: 0,
                             isFavorite: true, isHidden: false,
                             location: nil, burstIdentifier: nil, isCloudOnly: false)
        let favVM = makeViewModel(items: items, startItemID: "id-0")
        let staged = favVM.planRemoval(action: .moveToRecentlyDeleted, forItemID: "id-0", exitEdge: .bottom)!
        _ = favVM.commitRemoval(staged)
        XCTAssertEqual(favVM.current?.id, "id-1")
        XCTAssertTrue(favVM.isFavoriteCurrent, "commit 后收藏状态应跟随新当前项")
    }
}
