// MARK: - 职责说明：撤销倒计时唯一时钟（docs/16 M12 R04）——
// settings.undoWindow 为唯一时长来源；单一 30fps 泵（.common mode）驱动全部会话：
// DSToast 环动画、UndoCenter 到期、Viewer staged 撤销到期共用同源时间（Clock 注入），
// 「环归零 / 「撤销」按钮失效 / 实际撤销截止」三者同刻（误差 ≤ 0.1s 不变量）。
// DSToast 只做渲染（updateRing(remaining:duration:)），不再自算到期/自行 dismiss。

import Foundation
import PhotoDeskCore

@MainActor
final class UndoCountdownDriver {
    /// 一条倒计时会话（duration > 0；到点 onExpire 恰好调用一次）
    private struct Session {
        let id: UUID
        let duration: TimeInterval
        let startedAt: Date
        let onTick: ((Double) -> Void)?
        let onExpire: () -> Void
    }

    private var sessions: [UUID: Session] = [:]
    /// 单一泵：全部会话共享（旧版 DSToast 30fps + UndoCenter 0.25s 两套时钟的根因修复）
    private var pump: Timer?
    private let clock: Clock

    init(clock: Clock = SystemClock()) {
        self.clock = clock
    }

    /// 启动会话；返回 id（cancel(id:) 用）。onExpire 只在到点触发一次。
    @discardableResult
    func start(duration: TimeInterval,
               onTick: ((Double) -> Void)?,
               onExpire: @escaping () -> Void) -> UUID {
        let id = UUID()
        sessions[id] = Session(id: id,
                               duration: max(0.05, duration),
                               startedAt: clock.now,
                               onTick: onTick,
                               onExpire: onExpire)
        startPumpIfNeeded()
        tick()   // 立即刷一帧（环从满开始；已过期立即收口）
        return id
    }

    func cancel(id: UUID) {
        sessions.removeValue(forKey: id)
        if sessions.isEmpty {
            pump?.invalidate()
            pump = nil
        }
    }

    func cancelAll() {
        sessions.removeAll()
        pump?.invalidate()
        pump = nil
    }

    #if DEBUG
    /// 单测驱动：手动触发一帧（注入 MockClock 推进时间后调用，绕开真实 Timer 等待）
    func fireIfExpiredForTesting() {
        tick()
    }
    #endif

    // MARK: - 私有

    private func startPumpIfNeeded() {
        guard pump == nil else { return }
        let timer = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tick()
            }
        }
        RunLoop.main.add(timer, forMode: .common)   // 框选/滚动期间也不停摆
        pump = timer
    }

    private func tick() {
        guard !sessions.isEmpty else {
            pump?.invalidate()
            pump = nil
            return
        }
        let now = clock.now
        var expired: [(UUID, Session)] = []
        for (id, session) in sessions {
            let elapsed = now.timeIntervalSince(session.startedAt)
            let fraction = session.duration > 0 ? max(0, min(1, 1 - elapsed / session.duration)) : 0
            session.onTick?(fraction)
            if fraction <= 0 {
                expired.append((id, session))
            }
        }
        guard !expired.isEmpty else { return }
        for (id, _) in expired {
            sessions.removeValue(forKey: id)
        }
        if sessions.isEmpty {
            pump?.invalidate()
            pump = nil
        }
        for (_, session) in expired {
            session.onExpire()
        }
    }
}
