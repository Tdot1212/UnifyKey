import UIKit

class SmartReplyPopupUIView: UIView {
    var onReplySelected: ((String) -> Void)?
    var onClose: (() -> Void)?

    private let titleLabel = UILabel()
    private let closeButton = UIButton(type: .custom)
    private let stackView = UIStackView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }
    required init?(coder: NSCoder) { fatalError() }

    private func setupUI() {
        backgroundColor = .systemBackground
        layer.cornerRadius = 16
        clipsToBounds = true

        titleLabel.text = "Smart Replies"
        titleLabel.font = .systemFont(ofSize: 16, weight: .semibold)
        addSubview(titleLabel)

        closeButton.setImage(UIImage(systemName: "xmark.circle.fill"), for: .normal)
        closeButton.tintColor = .tertiaryLabel
        closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        addSubview(closeButton)

        stackView.axis = .vertical
        stackView.spacing = 10
        addSubview(stackView)
    }

    func setReplies(_ replies: [(targetText: String, userText: String)]) {
        stackView.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for reply in replies {
            let card = makeReplyCard(targetText: reply.targetText, userText: reply.userText)
            stackView.addArrangedSubview(card)
        }
        setNeedsLayout()
    }

    private func makeReplyCard(targetText: String, userText: String) -> UIView {
        let card = UIButton(type: .custom)
        card.backgroundColor = UIColor.secondarySystemFill
        card.layer.cornerRadius = 12
        card.accessibilityValue = targetText

        let targetLabel = UILabel()
        targetLabel.text = targetText
        targetLabel.font = .systemFont(ofSize: 16, weight: .medium)
        targetLabel.textColor = .label
        targetLabel.numberOfLines = 0
        targetLabel.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(targetLabel)

        let userLabel = UILabel()
        userLabel.text = userText
        userLabel.font = .systemFont(ofSize: 14)
        userLabel.textColor = .secondaryLabel
        userLabel.numberOfLines = 0
        userLabel.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(userLabel)

        targetLabel.isUserInteractionEnabled = false
        userLabel.isUserInteractionEnabled = false

        NSLayoutConstraint.activate([
            targetLabel.topAnchor.constraint(equalTo: card.topAnchor, constant: 12),
            targetLabel.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
            targetLabel.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16),
            userLabel.topAnchor.constraint(equalTo: targetLabel.bottomAnchor, constant: 4),
            userLabel.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
            userLabel.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16),
            userLabel.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -12),
        ])

        card.heightAnchor.constraint(greaterThanOrEqualToConstant: 64).isActive = true
        card.addTarget(self, action: #selector(replyTapped(_:)), for: .touchUpInside)
        return card
    }

    @objc private func replyTapped(_ sender: UIButton) {
        guard let text = sender.accessibilityValue else { return }
        onReplySelected?(text)
    }

    @objc private func closeTapped() { onClose?() }

    override func layoutSubviews() {
        super.layoutSubviews()
        let pad: CGFloat = 16
        titleLabel.frame = CGRect(x: pad, y: 14, width: bounds.width - 60, height: 22)
        closeButton.frame = CGRect(x: bounds.width - 44, y: 10, width: 32, height: 32)
        stackView.frame = CGRect(x: pad, y: 44, width: bounds.width - pad * 2, height: bounds.height - 52)
    }
}
