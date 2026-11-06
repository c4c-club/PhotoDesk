// MARK: - 职责说明：单指滑选的全部常量集中在 Core，禁止 ViewController 散落魔法数字。

import Foundation

public enum SlideSelectConfig {
    public static let edgeBuffer: Double = 60
    public static let minStep: Double = 1
    public static let maxStep: Double = 18
    public static let directionLockEpsilon: Double = 0
}
