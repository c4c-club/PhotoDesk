// MARK: - 职责说明：编辑器 UIKit 界面（docs/05 M6 任务 6.1/6.2）——
// 预览（aspectFit）+ 裁剪遮罩（CropOverlayView：四角手柄 + 整体拖动）+ 比例 chips + 旋转/翻转/重置
// + 五滑杆调整（实时预览）+ 保存三动作（另存默认/覆盖/还原）。
// 裁剪矩形语义：作用于「当前显示方向」的渲染图（旋转/翻转后），与 ExportRenderer 管线一致。

import UIKit
import Combine
import PhotoDeskCore

final class EditorViewController: UIViewController {
    private let viewModel: EditorViewModel
    private let item: PhotoItem
    var onClose: (() -> Void)?

    private let previewView = UIImageView()
    private let cropOverlay = CropOverlayView()
    private let aspectChipsStack = UIStackView()
    private var sliders: [UISlider] = []
    private let sliderNames = ["亮度", "对比度", "饱和度", "色温", "锐度"]
    private var observers: [AnyCancellable] = []

    private enum SliderID: Int, CaseIterable {
        case brightness = 0, contrast, saturation, temperature, sharpness
    }

    init(viewModel: EditorViewModel, item: PhotoItem) {
        self.viewModel = viewModel
        self.item = item
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) 未使用")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = DSColor.bgViewer
        setupPreview()
        setupControls()
        wireViewModel()

        navigationItem.leftBarButtonItem = UIBarButtonItem(title: "取消", style: .plain,
                                                           target: self, action: #selector(closeTapped))
        navigationItem.rightBarButtonItems = [
            UIBarButtonItem(title: "还原", style: .plain, target: self, action: #selector(revertTapped)),
            UIBarButtonItem(title: "覆盖", style: .plain, target: self, action: #selector(overwriteTapped)),
            UIBarButtonItem(title: "另存", style: .done, target: self, action: #selector(saveCopyTapped)),
        ]
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        Task { await viewModel.load() }
    }

    // MARK: - 构建

    private func setupPreview() {
        previewView.contentMode = .scaleAspectFit
        previewView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(previewView)

        cropOverlay.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(cropOverlay)
        cropOverlay.onCropChanged = { [weak self] rect in
            self?.applyCrop(viewRect: rect)
        }

        NSLayoutConstraint.activate([
            previewView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            previewView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            previewView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            previewView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -190),
        ])
    }

    private func setupControls() {
        // 比例 chips
        aspectChipsStack.axis = .horizontal
        aspectChipsStack.spacing = 8
        aspectChipsStack.translatesAutoresizingMaskIntoConstraints = false
        for preset in PhotoDeskCore.CropAspectRatio.presets {
            let button = UIButton(type: .system)
            button.setTitle(preset.name, for: .normal)
            button.titleLabel?.font = DSTypography.font(.badge)
            button.setTitleColor(DSColor.textPrimary, for: .normal)
            button.backgroundColor = DSColor.bgSecondary
            button.layer.cornerRadius = 12
            button.contentEdgeInsets = UIEdgeInsets(top: 4, left: 10, bottom: 4, right: 10)
            button.addAction(UIAction { [weak self] _ in
                self?.applyAspect(preset)
            }, for: .touchUpInside)
            aspectChipsStack.addArrangedSubview(button)
        }
        view.addSubview(aspectChipsStack)

        // 旋转 / 翻转 / 重置
        let rotateButton = UIButton(type: .system)
        rotateButton.setImage(UIImage(systemName: "rotate.right"), for: .normal)
        rotateButton.tintColor = DSColor.textPrimary
        rotateButton.addAction(UIAction { [weak self] _ in self?.viewModel.rotate() }, for: .touchUpInside)
        rotateButton.accessibilityLabel = "顺时针旋转 90 度"

        let flipButton = UIButton(type: .system)
        flipButton.setImage(UIImage(systemName: "arrow.left.and.right.righttriangle.left.righttriangle.right.fill"),
                            for: .normal)
        flipButton.tintColor = DSColor.textPrimary
        flipButton.addAction(UIAction { [weak self] _ in self?.viewModel.flipHorizontally() },
                             for: .touchUpInside)
        flipButton.accessibilityLabel = "水平翻转"

        let resetButton = UIButton(type: .system)
        resetButton.setTitle("重置", for: .normal)
        resetButton.setTitleColor(DSColor.textPrimary, for: .normal)
        resetButton.addAction(UIAction { [weak self] _ in self?.viewModel.resetAll() }, for: .touchUpInside)

        let geometryBar = UIStackView(arrangedSubviews: [rotateButton, flipButton, resetButton])
        geometryBar.axis = .horizontal
        geometryBar.spacing = 24
        geometryBar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(geometryBar)

        // 五滑杆
        let slidersStack = UIStackView()
        slidersStack.axis = .vertical
        slidersStack.spacing = 6
        slidersStack.translatesAutoresizingMaskIntoConstraints = false
        for (index, name) in sliderNames.enumerated() {
            let label = UILabel()
            label.text = name
            label.font = DSTypography.font(.badge)
            label.textColor = DSColor.textSecondary
            label.translatesAutoresizingMaskIntoConstraints = false
            label.widthAnchor.constraint(equalToConstant: 44).isActive = true

            let slider = UISlider()
            slider.tag = index
            slider.minimumValue = -1
            slider.maximumValue = 1
            slider.value = 0
            slider.addAction(UIAction { [weak self] action in
                self?.sliderChanged()
            }, for: .valueChanged)
            sliders.append(slider)

            let row = UIStackView(arrangedSubviews: [label, slider])
            row.axis = .horizontal
            row.spacing = 10
            slidersStack.addArrangedSubview(row)
        }
        view.addSubview(slidersStack)

        NSLayoutConstraint.activate([
            aspectChipsStack.topAnchor.constraint(equalTo: previewView.bottomAnchor, constant: 8),
            aspectChipsStack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            aspectChipsStack.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -12),

            geometryBar.topAnchor.constraint(equalTo: aspectChipsStack.bottomAnchor, constant: 8),
            geometryBar.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            geometryBar.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),

            slidersStack.topAnchor.constraint(equalTo: geometryBar.bottomAnchor, constant: 8),
            slidersStack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            slidersStack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            slidersStack.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -4),
        ])
    }

    private func wireViewModel() {
        viewModel.$preview.receive(on: DispatchQueue.main).sink { [weak self] image in
            self?.previewView.image = image
            self?.syncCropOverlayFromTransform()
        }.store(in: &observers)
        viewModel.$isLoading.receive(on: DispatchQueue.main).sink { [weak self] loading in
            self?.previewView.alpha = loading ? 0.4 : 1
        }.store(in: &observers)
    }

    private func sliderChanged() {
        let values = sliders.map(\.value)
        viewModel.updateAdjustments(brightness: Double(values[SliderID.brightness.rawValue]),
                                    contrast: Double(values[SliderID.contrast.rawValue]),
                                    saturation: Double(values[SliderID.saturation.rawValue]),
                                    temperature: Double(values[SliderID.temperature.rawValue]),
                                    sharpness: Double(values[SliderID.sharpness.rawValue]))
    }

    // MARK: - 比例适配

    private func applyAspect(_ preset: PhotoDeskCore.CropAspectRatio) {
        let displayAspect = aspectOfRenderedPreview()
        viewModel.applyAspect(preset, displayAspect: displayAspect)
        syncCropOverlayFromTransform()
    }

    private func aspectOfRenderedPreview() -> Double {
        guard let image = viewModel.preview, image.size.width > 0 else { return 1 }
        return image.size.width / image.size.height
    }

    // MARK: - 裁剪遮罩同步（归一化 ↔ 视图坐标，基于 aspectFit 的实际图像区域）

    private func imageDisplayFrame() -> CGRect {
        guard let image = viewModel.preview, image.size.width > 0 else {
            return previewView.bounds
        }
        let bounds = previewView.bounds
        guard bounds.width > 0, bounds.height > 0 else { return bounds }
        let scale = min(bounds.width / image.size.width, bounds.height / image.size.height)
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        return CGRect(x: (bounds.width - size.width) / 2,
                      y: (bounds.height - size.height) / 2,
                      width: size.width, height: size.height)
    }

    private func syncCropOverlayFromTransform() {
        let frame = imageDisplayFrame()
        guard frame.width > 0, frame.height > 0 else { return }
        let t = viewModel.transformWithoutCrop
        let rect = CGRect(x: frame.minX + CGFloat(t.cropX) * frame.width,
                          y: frame.minY + CGFloat(t.cropY) * frame.height,
                          width: CGFloat(t.cropWidth) * frame.width,
                          height: CGFloat(t.cropHeight) * frame.height)
        cropOverlay.frame = rect
        cropOverlay.isHidden = false
        cropOverlay.setNeedsDisplay()
    }

    /// CropOverlayView 回调（视图坐标矩形）→ 归一化裁剪
    private func applyCrop(viewRect: CGRect) {
        let frame = imageDisplayFrame()
        guard frame.width > 0, frame.height > 0 else { return }
        let x = max(0, (viewRect.minX - frame.minX) / frame.width)
        let y = max(0, (viewRect.minY - frame.minY) / frame.height)
        let w = min(1 - x, viewRect.width / frame.width)
        let h = min(1 - y, viewRect.height / frame.height)
        viewModel.setCrop(cropX: Double(x), cropY: Double(y),
                          cropWidth: Double(max(0.01, w)), cropHeight: Double(max(0.01, h)))
    }

    // MARK: - 保存动作

    @objc private func closeTapped() {
        onClose?()
        dismiss(animated: true)
    }

    @objc private func saveCopyTapped() {
        Task {
            do {
                try await viewModel.saveCopy()
                let alert = UIAlertController(title: "已另存为新照片", message: nil, preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: "好", style: .default) { _ in self.closeTapped() })
                present(alert, animated: true)
            } catch {
                presentError(error)
            }
        }
    }

    @objc private func overwriteTapped() {
        let alert = UIAlertController(title: "覆盖原件？",
                                      message: "编辑结果将替换原照片，系统相册保留「还原」能力。",
                                      preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "覆盖", style: .destructive) { [weak self] _ in
            Task {
                do {
                    try await self?.viewModel.saveOverwrite()
                    self?.closeTapped()
                } catch {
                    self?.presentError(error)
                }
            }
        })
        present(alert, animated: true)
    }

    @objc private func revertTapped() {
        let alert = UIAlertController(title: "还原到原始状态？",
                                      message: "将清除本应用对这张照片的全部编辑。",
                                      preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "还原", style: .destructive) { [weak self] _ in
            Task {
                try? await self?.viewModel.revert()
            }
        })
        present(alert, animated: true)
    }

    private func presentError(_ error: Error) {
        let alert = UIAlertController(title: "操作失败",
                                      message: error.localizedDescription,
                                      preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "好", style: .default))
        present(alert, animated: true)
    }
}
