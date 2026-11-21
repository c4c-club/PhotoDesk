// MARK: - 职责说明：LibrarySelectionController 轨迹接线单测（M20 T05，docs/49 T05 §4.2）——
// 经 DEBUG 单测接缝（debugFeed/debugProcessTrail）驱动状态机与轨迹事务，不触 UIKit 手势/窗口：
// beginTrail 只选锚点一格（M19 整行起手分支已删）、已多选横向起手建立取消模式事务、
// 行向下 rebase + 过滤重入、行向上 rewind 截断到目的行、空锚点防御性忽略。
// SlideSelectTrail/SelectionGestureMachine 纯逻辑归 PhotoDeskCore 单测，此处只测编排层。

import XCTest
import PhotoDeskCore
@testable import PhotoDesk

@MainActor
final class LibrarySelectionControllerTests: XCTestCase {

    // MARK: - fixtures

    private var controller: LibrarySelectionController!
    private var selectedIDs: Set<String> = []
    private var applied: [(add: Set<String>, remove: Set<String>)] = []
    private var trailActiveEvents: [Bool] = []
    private var nextHit: SelectionTrailHit!
    private var hitCallCount = 0

    override func setUpWithError() throws {
        let collectionView = UICollectionView(frame: CGRect(x: 0, y: 0, width: 390, height: 844),
                                              collectionViewLayout: UICollectionViewFlowLayout())
        var config = SelectionGestureConfig()
        config.longPressDuration = 0   // 单测实时钟喂 holdElapsed：免 0.28s 等待，语义不变
        controller = LibrarySelectionController(collectionView: collectionView, config: config)
        selectedIDs = []
        applied = []
        trailActiveEvents = []
        hitCallCount = 0
        nextHit = SelectionTrailHit(mode: .cells, orderedIDs: [], rewindID: nil)
        controller.isSelectionMode = { [weak self] in self?.isSelecting ?? false }
        controller.selectedIDsProvider = { [weak self] in self?.selectedIDs ?? [] }
        controller.applySelectionDelta = { [weak self] add, remove in
            guard let self else { return }
            self.applied.append((add: add, remove: remove))
            self.selectedIDs.formUnion(add)
            self.selectedIDs.subtract(remove)
        }
        controller.scopeProvider = { nil }
        controller.isApplyingSnapshotProvider = { false }
        controller.onSelectionEntered = { _ in }
        controller.onTrailActiveChanged = { [weak self] active in self?.trailActiveEvents.append(active) }
        controller.trailHitProvider = { [weak self] _, _ in
            self?.hitCallCount += 1
            return self?.nextHit ?? SelectionTrailHit(mode: .cells, orderedIDs: [], rewindID: nil)
        }
    }

    private var isSelecting = false

    /// 长按进入轨迹事务（armed + beginTrail），推进到 dragging 以便 processTrail。
    private func armAndDrag(hitID: String) {
        controller.debugFeed(.touchDown(point: GridPoint(x: 100, y: 200), hitID: hitID))
        controller.debugFeed(.holdElapsed)
        controller.debugFeed(.moved(dx: 6, dy: 0))   // armed → dragging（≥ activationDistance=6）
    }

    // MARK: - beginTrail：起手只选锚点一格

    func testBeginTrailConsumesOnlyAnchor() throws {
        armAndDrag(hitID: "a")
        XCTAssertEqual(applied.count, 1, "enterSelection + beginTrail 只落地一次净增量")
        XCTAssertEqual(applied.first?.add, ["a"], "起手绝不整行（M19 (press,press) 行带分支已删）")
        XCTAssertTrue(applied.first?.remove.isEmpty ?? false)
        XCTAssertEqual(controller.debugTrailPathCount, 1, "路径事务深度 = 锚点一格")
        XCTAssertEqual(trailActiveEvents.last, true)
    }

    // MARK: - 已多选 + 横向 beginTrail：取消模式事务

    func testHorizontalBeginTrailWhileSelectingBuildsDeselectTrail() throws {
        isSelecting = true
        selectedIDs = ["a", "b"]
        controller.debugFeed(.touchDown(point: GridPoint(x: 100, y: 200), hitID: "a"))
        controller.debugFeed(.moved(dx: 9, dy: 0))   // pressing 横向锁定（不再重复 enterSelection）
        XCTAssertEqual(applied.count, 1)
        XCTAssertEqual(applied.first?.remove, ["a"], "起手已选 → 锚点进取消模式事务，滑过即取消")
        XCTAssertTrue(applied.first?.add.isEmpty ?? false)
        XCTAssertEqual(controller.debugTrailPathCount, 1)
    }

    // MARK: - 行向下：rebase + 过滤重入

    func testRowsDownRebasesAndFiltersPathIDs() throws {
        armAndDrag(hitID: "a")
        applied.removeAll()
        nextHit = SelectionTrailHit(mode: .rows, orderedIDs: ["a", "b", "c", "d"], rewindID: nil)
        controller.debugProcessTrail(from: CGPoint(x: 100, y: 200), to: CGPoint(x: 100, y: 400))
        XCTAssertEqual(applied.count, 1)
        XCTAssertEqual(applied.first?.add, ["b", "c", "d"], "rebase 后整行种子一次入选，a 已在 base 零净差")
        XCTAssertEqual(controller.debugTrailPathCount, 4)
        applied.removeAll()
        controller.debugProcessTrail(from: CGPoint(x: 100, y: 400), to: CGPoint(x: 100, y: 420))
        XCTAssertTrue(applied.isEmpty, "同带重入帧过滤后为空 = 成功帧，无净差")
        XCTAssertEqual(hitCallCount, 2)
    }

    // MARK: - 行向上：rewind 只回退到目的行

    func testRowsUpRewindTruncatesToDestinationRow() throws {
        armAndDrag(hitID: "a")
        nextHit = SelectionTrailHit(mode: .rows, orderedIDs: ["a", "b", "c", "d"], rewindID: nil)
        controller.debugProcessTrail(from: CGPoint(x: 100, y: 200), to: CGPoint(x: 100, y: 400))
        applied.removeAll()
        nextHit = SelectionTrailHit(mode: .rows, orderedIDs: ["b", "a"], rewindID: "b")
        controller.debugProcessTrail(from: CGPoint(x: 100, y: 400), to: CGPoint(x: 100, y: 220))
        XCTAssertEqual(applied.count, 1)
        XCTAssertEqual(applied.first?.remove, ["c", "d"], "rewind ∈ path → 截断到目的行末项 b")
        XCTAssertTrue(applied.first?.add.isEmpty ?? false)
        XCTAssertEqual(controller.debugTrailPathCount, 2)
    }

    // MARK: - 空锚点：beginTrail 防御性忽略

    func testEmptyAnchorBeginTrailIsIgnored() throws {
        controller.debugFeed(.touchDown(point: GridPoint(x: 100, y: 200), hitID: ""))
        controller.debugFeed(.holdElapsed)   // enterSelection("") + beginTrail(anchorID: "")
        XCTAssertTrue(applied.isEmpty, "空锚点不建立事务、不落地增量")
        XCTAssertEqual(controller.debugTrailPathCount, -1, "路径事务未创建")
        XCTAssertTrue(trailActiveEvents.isEmpty, "onTrailActiveChanged 不得触发")
    }
}
