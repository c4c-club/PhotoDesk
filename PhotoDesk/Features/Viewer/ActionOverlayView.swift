// MARK: - 职责说明：动作浮层（docs/04 §3.2 规格）——
// 圆形 96pt 背景 + 36pt SF Symbol + 15pt 文案；随手指 progress 变化：
// 透明度 0.35+0.65p、缩放 0.85+0.30p、位移 dy×0.6；锁定态：实心背景 + scale 1.15 + 2pt 描边。
// 上滑浮层居屏幕上方 1/4、下滑浮层居下方 1/4（由父视图放置两个实例，本类只管自身状态）。
// 颜色 token 见 DSColor（收藏 #FFB300 / 隐藏 #5C6BC0 / 移到最近删除 #E53935 / 相簿 / 分享 / 信息）。

import UIKit
import PhotoDeskCore

final class ActionOverlayView: UIView {
    private let circleView: UIView = {
        let view = UIView()
        view.layer.cornerRadius = DSSpacing.actionOverlaySize / 2
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    private let iconView: UIImageView = {
        let view = UIImageView()
        view.contentMode = .scaleAspectFit
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    private let promptLabel: UILabel = {
        let label = UILabel()
        // 浮层文案 15pt 起步、动态字体、上限 20pt（docs/04 §3.2 + §6）
        label.font = DSTypography.fontCapped(.toast, maxPoint: 20)
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private var baseCenterY: CGFloat = 0

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false          // 纯展示，不拦手势
        alpha = 0
        addSubview(circleView)
        addSubview(iconView)
        addSubview(promptLabel)
        NSLayoutConstraint.activate([
            circleView.centerXAnchor.constraint(equalTo: centerXAnchor),
            circleView.centerYAnchor.constraint(equalTo: centerYAnchor),
            circleView.widthAnchor.constraint(equalToConstant: DSSpacing.actionOverlaySize),
            circleView.heightAnchor.constraint(equalToConstant: DSSpacing.actionOverlaySize),

            iconView.centerXAnchor.constraint(equalTo: circleView.centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: circleView.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: DSSpacing.actionOverlayIconSize),
            iconView.heightAnchor.constraint(equalToConstant: DSSpacing.actionOverlayIconSize),

            promptLabel.topAnchor.constraint(equalTo: circleView.bottomAnchor, constant: 10),
            promptLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) 未使用")
    }

    /// 记录浮层锚点 Y（父视图布局后调用：上滑 = 高度 1/4，下滑 = 高度 3/4）
    func setBaseCenter(y: CGFloat) {
        baseCenterY = y
        center = CGPoint(x: center.x, y: baseCenterY)
    }

    /// 手指拖拽驱动；动作由调用方按当前设置解析后传入（依赖方向：Features → Domain，不反向依赖组合根）
    func update(direction: SwipeDirection, action: SwipeAction, progress: Double, locked: Bool, translationY: CGFloat) {
        isHidden = false
        let color = Self.color(for: action)
        let clamped = max(0, min(1, progress))

        iconView.image = UIImage(systemName: Self.symbol(for: action))
        promptLabel.text = action.overlayPrompt
        iconView.tintColor = locked ? .white : color
        promptLabel.textColor = locked ? .white : color

        // 非锁定：描边圆环 + 半透明底；锁定：实心 + 2pt 描边 + scale 1.15
        circleView.backgroundColor = locked ? color : color.withAlphaComponent(0.18)
        circleView.layer.borderWidth = locked ? 2 : 1.5
        circleView.layer.borderColor = (locked ? UIColor.white : color).withAlphaComponent(locked ? 1 : 0.8).cgColor

        let scale = locked ? 1.15 : (0.85 + 0.30 * clamped)
        alpha = locked ? 1 : (0.35 + 0.65 * clamped)
        transform = CGAffineTransform(translationX: 0, y: translationY * 0.6)
            .scaledBy(x: scale, y: scale)
        center = CGPoint(x: center.x, y: baseCenterY)   // transform 以锚点为基准
    }

    func hide() {
        guard !isHidden else { return }
        isHidden = true
        alpha = 0
        transform = .identity
    }

    // MARK: - 动作映射（docs/04 §3.2 颜色表 + §5.3 SF Symbols）

    static func symbol(for action: SwipeAction) -> String {
        switch action {
        case .favorite:              return "heart.fill"
        case .unfavorite:            return "heart"
        case .toggleFavorite:        return "heart"
        case .hide:                  return "eye.slash.fill"
        case .unhide:                return "eye.fill"
        case .moveToRecentlyDeleted: return "trash.fill"
        case .addToAlbum:            return "folder.badge.plus"
        case .share:                 return "square.and.arrow.up"
        case .showInfo:              return "info.circle"
        case .rotate:                return "rotate.right"
        case .dismiss:               return "xmark"
        case .none:                  return "minus"
        }
    }

    static func color(for action: SwipeAction) -> UIColor {
        switch action {
        case .favorite, .unfavorite, .toggleFavorite: return DSColor.accentFavorite
        case .hide, .unhide:                          return DSColor.accentHide
        case .moveToRecentlyDeleted:                  return DSColor.accentDelete
        case .addToAlbum:                             return DSColor.accentAlbum
        case .share:                                  return DSColor.accentShare
        case .showInfo:                               return DSColor.accentInfo
        case .rotate, .dismiss, .none:                return DSColor.textSecondary
        }
    }
}
