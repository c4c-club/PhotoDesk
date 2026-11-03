# 一次性脚本：轮 15 三处修复（运行后删除）
import io

# 1) StabilityUITests：筛选钩子参数改赋值（防累积）；位置测试改自适应月份
p = 'PhotoDeskUITests/StabilityUITests.swift'
s = io.open(p, encoding='utf-8').read()

old = '''    /// 清空筛选启动（-uiTestingFilterYear 0 = 就绪后 clearFilter，跨用例持久化隔离）
    @discardableResult
    private func launchWithFilterCleared(_ app: XCUIApplication) -> XCUIElement {
        app.launchArguments += ["-uiTestingFilterYear", "0"]
        return launchToGrid(app)
    }

    /// 年份筛选启动（就绪后应用年份筛选）
    private func launchWithYearFilter(_ app: XCUIApplication, year: Int) {
        app.launchArguments += ["-uiTestingFilterYear", "\\(year)"]
        _ = launchToGrid(app)
    }'''
new = '''    /// 清空筛选启动（-uiTestingFilterYear 0 = 就绪后 clearFilter，跨用例持久化隔离）。
    /// 注意必须整体赋值：+= 会累积多个同名参数，intValue 取第一个导致钩子失效（CI 轮 14 实测）
    @discardableResult
    private func launchWithFilterCleared(_ app: XCUIApplication) -> XCUIElement {
        app.launchArguments = ["-uiTestingFilterYear", "0"]
        return launchToGrid(app)
    }

    /// 年份筛选启动（就绪后应用年份筛选）
    private func launchWithYearFilter(_ app: XCUIApplication, year: Int) {
        app.launchArguments = ["-uiTestingFilterYear", "\\(year)"]
        _ = launchToGrid(app)
    }'''
assert old in s, "filter helpers not found"
s = s.replace(old, new)

old = '''        var reached = waitTopHeaderContains(app, "2024年5月", timeout: 2)
        var swipes = 0
        while !reached, swipes < 60 {
            app.swipeUp()
            swipes += 1
            reached = waitTopHeaderContains(app, "2024年5月", timeout: 1)
        }
        XCTAssertTrue(reached, "\\(swipes) 次滑动内未到达 2024年5月（顶部：\\(topHeaderText(app))）\\n\\(hierarchy(app))")
        Thread.sleep(forTimeInterval: 1.5)   // 等位置保存兜底 Timer
        app.terminate()
        _ = launchToGrid(app)
        XCTAssertTrue(waitTopHeaderContains(app, "2024年5月", timeout: 10),
                      "重启后未回到 2024年5月（顶部：\\(topHeaderText(app))）\\n\\(hierarchy(app))")
        assertAlive(app, "位置恢复重启后")
        snap(app, "s04-restore")'''
new = '''        // 先按年滚动（单次快滑约跳 6-9 个月，逐月目标会被采样跳过——CI 轮 14 实测滑到 2018）
        var reached = waitTopHeaderContains(app, "2024年", timeout: 2)
        var swipes = 0
        while !reached, swipes < 60 {
            app.swipeUp()
            swipes += 1
            reached = waitTopHeaderContains(app, "2024年", timeout: 1)
        }
        XCTAssertTrue(reached, "\\(swipes) 次滑动内未到达 2024 年（顶部：\\(topHeaderText(app))）\\n\\(hierarchy(app))")
        Thread.sleep(forTimeInterval: 0.5)   // 等减速完成
        // 以实际停住的月份为恢复断言目标（保存/恢复都按首个可见 asset，二者自洽）
        let savedMonth = topHeaderText(app).components(separatedBy: " ").first ?? ""
        XCTAssertTrue(savedMonth.contains("2024年"), "停在非 2024 年月份：\\(savedMonth)")
        Thread.sleep(forTimeInterval: 1.5)   // 等位置保存兜底 Timer
        app.terminate()
        _ = launchToGrid(app)
        XCTAssertTrue(waitTopHeaderContains(app, savedMonth, timeout: 10),
                      "重启后未回到 \\(savedMonth)（顶部：\\(topHeaderText(app))）\\n\\(hierarchy(app))")
        assertAlive(app, "位置恢复重启后")
        snap(app, "s04-restore")'''
assert old in s, "position test not found"
s = s.replace(old, new)
io.open(p, 'w', encoding='utf-8', newline='\n').write(s)
print('stability ok')

# 2) LibraryRootView：月份跳转钩子加重试
p2 = 'PhotoDesk/Features/Library/LibraryContainer.swift'
s2 = io.open(p2, encoding='utf-8').read()

old2 = '''    /// docs/13 M11：快照包含目标月后跳转（等价月份面板点卡片，同一条 scrollToSection 路径；
    /// scrollToSection 失败（collectionView 未提交）时不置位，等下一次快照重试）
    func openHookMonthJumpIfNeeded() {
        guard !hookMonthJumped, viewModel.viewState == .ready,
              let sectionID = UITestHooks.stringValue("-uiTestingMonthJump") else { return }
        guard let index = viewModel.sections.firstIndex(where: { $0.id == sectionID }) else { return }
        if selectionBridge.controller?.scrollToSection(index) == true {
            hookMonthJumped = true
        }
    }'''
new2 = '''    /// docs/13 M11：快照包含目标月后跳转（等价月份面板点卡片，同一条 scrollToSection 路径）。
    /// 首次触发时快照 apply 可能尚未提交（numberOfSections == 0）→ 短重试；
    /// sections 内容不变时 onChange 不再触发，不能只依赖 onChange 重试（CI 轮 14 实测跳转丢失）
    func openHookMonthJumpIfNeeded() {
        guard !hookMonthJumped, viewModel.viewState == .ready,
              let sectionID = UITestHooks.stringValue("-uiTestingMonthJump") else { return }
        guard let index = viewModel.sections.firstIndex(where: { $0.id == sectionID }) else { return }
        if selectionBridge.controller?.scrollToSection(index) == true {
            hookMonthJumped = true
            return
        }
        guard !hookMonthJumpRetrying else { return }
        hookMonthJumpRetrying = true
        var attempts = 0
        func retry() {
            guard !hookMonthJumped, attempts < 20 else { return }
            attempts += 1
            if let index2 = viewModel.sections.firstIndex(where: { $0.id == sectionID }),
               selectionBridge.controller?.scrollToSection(index2) == true {
                hookMonthJumped = true
                return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { retry() }
        }
        retry()
    }'''
assert old2 in s2, "month jump hook not found"
s2 = s2.replace(old2, new2)

old3 = '''    @State private var hookFilterApplied = false
    @State private var hookMonthJumped = false
    #endif'''
new3 = '''    @State private var hookFilterApplied = false
    @State private var hookMonthJumped = false
    @State private var hookMonthJumpRetrying = false
    #endif'''
assert old3 in s2, "state vars not found"
s2 = s2.replace(old3, new3)
io.open(p2, 'w', encoding='utf-8', newline='\n').write(s2)
print('container ok')
