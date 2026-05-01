import UIKit

class TranslationBarUIView: UIView {

    var onSendTranslation: (() -> Void)?
    var onActionLongPress: (() -> Void)?
    var onLanguageTap: (() -> Void)?
    var onLanguageLongPress: (() -> Void)?
    var onReplyTap: (() -> Void)?
    var onTranslationTapped: (() -> Void)?
    var onDismissClipboard: (() -> Void)?
    var currentTranslation: String?
    var currentOriginal: String?
    var isClipboardMode = false {
        didSet { updateActionIconForMode() }
    }

    private let languagePill = UIButton(type: .custom)
    private let originalLabel = UILabel()
    private let translationLabel = UILabel()
    private let speedLabel = UILabel()
    private let actionButton = UIButton(type: .custom)
    private let replyButton = UIButton(type: .custom)
    private let separator = UIView()
    private let textAreaOverlay = UIView()
    private(set) var isReviewMode = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setupUI() {
        backgroundColor = UIColor.systemBackground.withAlphaComponent(0.95)

        languagePill.setTitle("→ 中文", for: .normal)
        languagePill.titleLabel?.font = .systemFont(ofSize: 11, weight: .bold)
        languagePill.setTitleColor(.white, for: .normal)
        languagePill.backgroundColor = .systemBlue
        languagePill.layer.cornerRadius = 10
        languagePill.clipsToBounds = true
        languagePill.addTarget(self, action: #selector(languageTapped), for: .touchUpInside)
        addSubview(languagePill)

        // Long press on language pill
        let langLongPress = UILongPressGestureRecognizer(target: self, action: #selector(languageLongPressed(_:)))
        langLongPress.minimumPressDuration = 0.5
        languagePill.addGestureRecognizer(langLongPress)

        originalLabel.font = .systemFont(ofSize: 11)
        originalLabel.textColor = .secondaryLabel
        originalLabel.numberOfLines = 1
        originalLabel.lineBreakMode = .byTruncatingTail
        addSubview(originalLabel)

        translationLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        translationLabel.textColor = .tertiaryLabel
        translationLabel.numberOfLines = 1
        translationLabel.lineBreakMode = .byTruncatingTail
        translationLabel.text = "Type your message, then tap \u{2192} to translate"
        addSubview(translationLabel)

        speedLabel.font = .systemFont(ofSize: 10, weight: .medium)
        speedLabel.textColor = .tertiaryLabel
        speedLabel.textAlignment = .right
        speedLabel.isHidden = true
        addSubview(speedLabel)

        replyButton.setTitle("Reply?", for: .normal)
        replyButton.titleLabel?.font = .systemFont(ofSize: 13, weight: .semibold)
        replyButton.setTitleColor(.systemBlue, for: .normal)
        replyButton.addTarget(self, action: #selector(replyTapped), for: .touchUpInside)
        replyButton.isHidden = true
        addSubview(replyButton)

        // Action button — always blue → arrow, 36pt
        let config = UIImage.SymbolConfiguration(pointSize: 20, weight: .medium)
        actionButton.setImage(UIImage(systemName: "arrow.right.circle.fill", withConfiguration: config), for: .normal)
        actionButton.tintColor = .systemBlue
        actionButton.addTarget(self, action: #selector(actionTapped), for: .touchUpInside)
        addSubview(actionButton)

        // Long press on action button for preview card
        let actionLongPress = UILongPressGestureRecognizer(target: self, action: #selector(actionLongPressed(_:)))
        actionLongPress.minimumPressDuration = 0.5
        actionButton.addGestureRecognizer(actionLongPress)

        separator.backgroundColor = .separator
        addSubview(separator)

        // Transparent overlay on text area — tappable when translation showing
        textAreaOverlay.backgroundColor = .clear
        let textTap = UITapGestureRecognizer(target: self, action: #selector(translationTextTapped))
        textAreaOverlay.addGestureRecognizer(textTap)
        addSubview(textAreaOverlay)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let w = bounds.width
        let h = bounds.height

        languagePill.frame = CGRect(x: 8, y: (h - 24) / 2, width: 50, height: 24)

        let textX: CGFloat = 66
        // Action button always visible on right
        var rightUsed: CGFloat = 8 + 36 + 4
        if !replyButton.isHidden { rightUsed += 50 }
        let textW = w - textX - rightUsed

        let speedW: CGFloat = speedLabel.isHidden ? 0 : 44
        originalLabel.frame = CGRect(x: textX, y: 5, width: textW - speedW, height: 16)
        translationLabel.frame = CGRect(x: textX, y: 23, width: textW - speedW, height: 22)
        if !speedLabel.isHidden {
            speedLabel.frame = CGRect(x: textX + textW - speedW, y: 5, width: speedW, height: 16)
        }

        // Action button on far right
        actionButton.frame = CGRect(x: w - 8 - 36, y: (h - 36) / 2, width: 36, height: 36)

        if !replyButton.isHidden {
            let rx = w - 8 - 36 - 4 - 46
            replyButton.frame = CGRect(x: rx, y: (h - 26) / 2, width: 46, height: 26)
        }

        separator.frame = CGRect(x: 0, y: h - 0.5, width: w, height: 0.5)

        // Text area overlay covers the label region
        let actionX = actionButton.frame.minX
        textAreaOverlay.frame = CGRect(x: textX, y: 0, width: actionX - textX - 4, height: h)
    }

    // MARK: - Display States

    func showIdle() {
        originalLabel.text = ""
        translationLabel.text = "Type your message, then tap \u{2192} to translate"
        translationLabel.textColor = .tertiaryLabel
        currentTranslation = nil
        currentOriginal = nil
        isClipboardMode = false
        isReviewMode = false
        setActionIcon(review: false)
        replyButton.isHidden = true
        speedLabel.isHidden = true
        actionButton.isEnabled = true
        setNeedsLayout()
    }

    func showOriginal(_ text: String) {
        originalLabel.text = text
        currentOriginal = text
    }

    func showTranslating() {
        translationLabel.text = "Translating..."
        translationLabel.textColor = .secondaryLabel
        currentTranslation = nil
        isReviewMode = false
        setActionIcon(review: false)
        actionButton.isEnabled = false
        setNeedsLayout()
    }

    func showTranslation(original: String, translation: String) {
        originalLabel.text = original
        translationLabel.text = translation
        translationLabel.textColor = .label
        currentTranslation = translation
        currentOriginal = original
        isReviewMode = true
        setActionIcon(review: true)
        actionButton.isEnabled = true
        setNeedsLayout()
    }

    func showError(_ message: String) {
        translationLabel.text = message
        translationLabel.textColor = .systemRed
        currentTranslation = nil
        isReviewMode = false
        setActionIcon(review: false)
        actionButton.isEnabled = true
        setNeedsLayout()
    }

    func showMessage(_ message: String) {
        translationLabel.text = message
        translationLabel.textColor = .secondaryLabel
        let msg = message
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
            if self?.translationLabel.text == msg {
                self?.showIdle()
            }
        }
    }

    func showClipboardLoading(original: String) {
        isClipboardMode = true
        isReviewMode = false
        let truncated = original.count > 40 ? String(original.prefix(40)) + "..." : original
        originalLabel.text = truncated
        translationLabel.text = "Translating clipboard..."
        translationLabel.textColor = .secondaryLabel
        currentOriginal = original
        currentTranslation = nil
        replyButton.isHidden = true
        // Keep the X icon (set by isClipboardMode didSet) so user can cancel during load
        actionButton.isEnabled = true
        setNeedsLayout()
    }

    func showClipboardTranslation(original: String, translation: String) {
        isClipboardMode = true
        isReviewMode = true
        let truncated = original.count > 40 ? String(original.prefix(40)) + "..." : original
        originalLabel.text = truncated
        translationLabel.text = translation
        translationLabel.textColor = .label
        currentTranslation = translation
        currentOriginal = original
        replyButton.isHidden = false
        actionButton.isEnabled = true
        setClipboardReviewIcon()
        setNeedsLayout()
    }

    private func setClipboardReviewIcon() {
        let config = UIImage.SymbolConfiguration(pointSize: 20, weight: .medium)
        actionButton.setImage(UIImage(systemName: "xmark.circle.fill", withConfiguration: config), for: .normal)
        actionButton.tintColor = .systemOrange
    }

    private func updateActionIconForMode() {
        if isClipboardMode {
            setClipboardReviewIcon()
        } else {
            setActionIcon(review: isReviewMode)
        }
    }

    func showSpeed(_ text: String) {
        speedLabel.text = text
        speedLabel.textColor = text.contains("AI") ? .systemBlue : .systemGreen
        speedLabel.isHidden = false
        setNeedsLayout()
    }

    func updateTargetLanguage(_ code: String) {
        let names: [String: String] = [
            "zh": "中文", "en": "EN", "es": "ES", "ja": "日本語",
            "ko": "한국", "ar": "عربي", "fr": "FR", "de": "DE",
            "pt": "PT", "ru": "RU", "it": "IT", "th": "ไทย",
            "vi": "VN", "id": "ID", "hi": "हिंदी"
        ]
        languagePill.setTitle("→ \(names[code] ?? code.uppercased())", for: .normal)
        languagePill.sizeToFit()
        let pillW = max(50, languagePill.frame.width + 16)
        languagePill.frame.size.width = pillW
        setNeedsLayout()
    }

    private func setActionIcon(review: Bool) {
        let config = UIImage.SymbolConfiguration(pointSize: 20, weight: .medium)
        if review {
            actionButton.setImage(UIImage(systemName: "ellipsis.circle.fill", withConfiguration: config), for: .normal)
            actionButton.tintColor = .systemGreen
        } else {
            actionButton.setImage(UIImage(systemName: "arrow.right.circle.fill", withConfiguration: config), for: .normal)
            actionButton.tintColor = .systemBlue
        }
    }

    @objc private func actionTapped() {
        if isClipboardMode {
            onDismissClipboard?()
        } else {
            onSendTranslation?()
        }
    }
    @objc private func languageTapped() { onLanguageTap?() }
    @objc private func replyTapped() { onReplyTap?() }

    @objc private func translationTextTapped() {
        guard currentTranslation != nil else { return }
        onTranslationTapped?()
    }

    @objc private func languageLongPressed(_ gesture: UILongPressGestureRecognizer) {
        if gesture.state == .began {
            onLanguageLongPress?()
        }
    }

    @objc private func actionLongPressed(_ gesture: UILongPressGestureRecognizer) {
        if gesture.state == .began {
            onActionLongPress?()
        }
    }
}
