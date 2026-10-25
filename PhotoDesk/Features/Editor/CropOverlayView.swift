// MARK: - 职责说明：裁剪遮罩（docs/05 M6 任务 6.1 裁剪交互）——
// 自身 frame = 裁剪矩形（父视图坐标）；四角手柄拖拽改边、框内拖动整体移动；
// 父视图（EditorViewController）负责把 frame 换算回归一化裁剪并同步 transform。

import UIKit

final class CropOverlayView: UIView {
    /// 拖动/缩放结束后的裁剪矩形（父视图坐标）
    var onCropChanged: ((CGRect) -> Void)?
    /// 手势结束（commit）通知
    var onCropCommitted: (() -> Void)?

    private enum Handle: CaseIterable {
        case topLeft, topRight, bottomLeft, bottomRight
    }

    private let cornerHandleSize: CGFloat = 30
    private let minimumCropSize: CGFloat = 48
    private var activeHandle: Handle?
    private var dragStartLocation: CGPoint = .zero
    private var dragStartFrame: CGRect = .zero
    private let borderWidth: CGFloat = 1.5

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        for _ in Handle.allCases {
            let handle = UIView()
            handle.backgroundColor = .white
            handle.layer.cornerRadius = 4
            handle.layer.borderWidth = 1
            handle.layer.borderColor = DSColor.tint.cgColor
            handle.translatesAutoresizingMaskIntoConstraints = true
            addSubview(handle)
        }
        let pan = UIPanGestureRecognizer(target: self, action: #selector(onPan(_:)))
        addGestureRecognizer(pan)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) 未使用")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let size = cornerHandleSize
        handles()[0].frame = CGRect(x: -4, y: -4, width: size, height: size)                       // top-left
        handles()[1].frame = CGRect(x: bounds.maxX - size + 4, y: -4, width: size, height: size)   // top-right
        handles()[2].frame = CGRect(x: -4, y: bounds.maxY - size + 4, width: size, height: size)   // bottom-left
        handles()[3].frame = CGRect(x: bounds.maxX - size + 4, y: bounds.maxY - size + 4,
                                    width: size, height: size)                                     // bottom-right
    }

    private func handles() -> [UIView] {
        subviews
    }

    // MARK: - 手势

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        // 命中手柄或框内均可拖动
        bounds.insetBy(dx: -8, dy: -8).contains(point)
    }

    @objc private func onPan(_ gesture: UIPanGestureRecognizer) {
        let location = gesture.location(in: superview)
        switch gesture.state {
        case .began:
            dragStartLocation = location
            dragStartFrame = frame
            activeHandle = handle(at: gesture.location(in: self))
        case .changed:
            if let handle = activeHandle {
                resize(with: handle, to: location)
            } else {
                move(to: location)
            }
            onCropChanged?(frame)
        case .ended, .cancelled:
            activeHandle = nil
            onCropCommitted?()
        default:
            break
        }
    }

    private func handle(at point: CGPoint) -> Handle? {
        for (index, handle) in handles().enumerated() {
            if handle.frame.insetBy(dx: -12, dy: -12).contains(point) {
                return Handle.allCases[index]
            }
        }
        return nil
    }

    private func move(to location: CGPoint) {
        let delta = CGPoint(x: location.x - dragStartLocation.x,
                            y: location.y - dragStartLocation.y)
        guard let parent = superview else { return }
        var newFrame = dragStartFrame
        newFrame.origin.x = max(0, min(parent.bounds.width - newFrame.width,
                                       dragStartFrame.origin.x + delta.x))
        newFrame.origin.y = max(0, min(parent.bounds.height - newFrame.height,
                                       dragStartFrame.origin.y + delta.y))
        frame = newFrame
    }

    private func resize(with handle: Handle, to location: CGPoint) {
        guard let parent = superview else { return }
        var newFrame = frame
        let start = dragStartFrame
        switch handle {
        case .topLeft:
            newFrame.origin.x = max(0, min(location.x, start.maxX - minimumCropSize))
            newFrame.origin.y = max(0, min(location.y, start.maxY - minimumCropSize))
            newFrame.size.width = start.maxX - newFrame.origin.x
            newFrame.size.height = start.maxY - newFrame.origin.y
        case .topRight:
            newFrame.origin.y = max(0, min(location.y, start.maxY - minimumCropSize))
            newFrame.size.width = max(minimumCropSize, min(location.x, parent.bounds.width) - start.minX)
            newFrame.size.height = start.maxY - newFrame.origin.y
        case .bottomLeft:
            newFrame.origin.x = max(0, min(location.x, start.maxX - minimumCropSize))
            newFrame.size.width = start.maxX - newFrame.origin.x
            newFrame.size.height = max(minimumCropSize, min(location.y, parent.bounds.height) - start.minY)
        case .bottomRight:
            newFrame.size.width = max(minimumCropSize, min(location.x, parent.bounds.width) - start.minX)
            newFrame.size.height = max(minimumCropSize, min(location.y, parent.bounds.height) - start.minY)
        }
        frame = newFrame
    }

    // MARK: - 绘制（边框 + 暗角遮罩由父级叠加；本视图画边框与三分线）

    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        // 边框
        context.setStrokeColor(UIColor.white.cgColor)
        context.setLineWidth(borderWidth)
        context.stroke(bounds)

        // 三分线
        context.setStrokeColor(UIColor.white.withAlphaComponent(0.4).cgColor)
        context.setLineWidth(0.5)
        for position in [1.0 / 3.0, 2.0 / 3.0] {
            let x = bounds.width * position
            context.move(to: CGPoint(x: x, y: 0))
            context.addLine(to: CGPoint(x: x, y: bounds.maxY))
            let y = bounds.height * position
            context.move(to: CGPoint(x: 0, y: y))
            context.addLine(to: CGPoint(x: bounds.maxX, y: y))
        }
        context.strokePath()
    }
}
