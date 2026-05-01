import UIKit

class EditingBannerUIView: UIView {

    var onConfirm: (() -> Void)?
    var onCancel: (() -> Void)?

    private let icon = UIImageView()
    private let label = UILabel()
    private let confirmBtn = UIButton(type: .custom)
    private let cancelBtn = UIButton(type: .custom)

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = UIColor.systemBlue.withAlphaComponent(0.08)

        icon.image = UIImage(systemName: "pencil.circle.fill")
        icon.tintColor = .systemBlue
        addSubview(icon)

        label.text = "Editing translation — tap ✓ when done"
        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.textColor = .label
        addSubview(label)

        let confirmConfig = UIImage.SymbolConfiguration(pointSize: 22)
        confirmBtn.setImage(UIImage(systemName: "checkmark.circle.fill", withConfiguration: confirmConfig), for: .normal)
        confirmBtn.tintColor = .systemGreen
        confirmBtn.addTarget(self, action: #selector(confirmTapped), for: .touchUpInside)
        addSubview(confirmBtn)

        let cancelConfig = UIImage.SymbolConfiguration(pointSize: 22)
        cancelBtn.setImage(UIImage(systemName: "xmark.circle.fill", withConfiguration: cancelConfig), for: .normal)
        cancelBtn.tintColor = .secondaryLabel
        cancelBtn.addTarget(self, action: #selector(cancelTapped), for: .touchUpInside)
        addSubview(cancelBtn)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        let h = bounds.height
        let w = bounds.width
        icon.frame = CGRect(x: 12, y: (h - 18) / 2, width: 18, height: 18)
        cancelBtn.frame = CGRect(x: w - 40, y: (h - 30) / 2, width: 30, height: 30)
        confirmBtn.frame = CGRect(x: w - 76, y: (h - 30) / 2, width: 30, height: 30)
        label.frame = CGRect(x: 36, y: 0, width: w - 36 - 82, height: h)
    }

    @objc private func confirmTapped() { onConfirm?() }
    @objc private func cancelTapped() { onCancel?() }
}
