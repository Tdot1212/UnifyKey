import UIKit

class TranslationPreviewCardUIView: UIView {

    // MARK: - Callbacks
    var onClose: (() -> Void)?
    var onEdit: (() -> Void)?
    var onBookmark: (() -> Void)?
    var onSend: (() -> Void)?
    var onToneSelected: ((String) -> Void)?

    // MARK: - Public state
    var originalText: String = "" {
        didSet { originalLabel.text = originalText }
    }
    var translatedText: String = "" {
        didSet { translationLabel.text = translatedText }
    }

    // MARK: - UI elements
    private let contentScrollView = UIScrollView()
    private let titleLabel = UILabel()
    private let closeButton = UIButton(type: .custom)
    private let youWroteHeader = UILabel()
    private let originalBg = UIView()
    private let originalLabel = UILabel()
    private let willSendHeader = UILabel()
    private let translationBorder = UIView()
    private let translationLabel = UILabel()
    private let editHintLabel = UILabel()
    private let backTranslationLabel = UILabel()
    private let contextIcon = UILabel()
    private let contextNoteLabel = UILabel()
    private let contextRow = UIView()
    private let toneHeader = UILabel()
    private var tonePills: [UIButton] = []
    private let toneSpinner = UIActivityIndicatorView(style: .medium)
    private let buttonRow = UIView()
    private let editButton = UIButton(type: .custom)
    private let bookmarkButton = UIButton(type: .custom)
    private let sendButton = UIButton(type: .custom)

    private var selectedTone: String?
    private var isBookmarked = false
    var isIncomingMode = false
    var isReplyMode = false
    var incomingText: String = ""

    // MARK: - Init

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: - Setup

    private func setupUI() {
        backgroundColor = .systemBackground
        layer.cornerRadius = 16
        layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.1
        layer.shadowRadius = 10
        layer.shadowOffset = CGSize(width: 0, height: -2)

        // Scrollable content area (everything except bottom buttons)
        contentScrollView.showsVerticalScrollIndicator = true
        contentScrollView.alwaysBounceVertical = false
        addSubview(contentScrollView)

        // Title
        titleLabel.text = "Translation Preview"
        titleLabel.font = .systemFont(ofSize: 16, weight: .semibold)
        titleLabel.textColor = .label
        contentScrollView.addSubview(titleLabel)

        // Close button
        let xConfig = UIImage.SymbolConfiguration(pointSize: 14, weight: .semibold)
        closeButton.setImage(UIImage(systemName: "xmark", withConfiguration: xConfig), for: .normal)
        closeButton.tintColor = .secondaryLabel
        closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        contentScrollView.addSubview(closeButton)

        // YOU WROTE:
        configureHeader(youWroteHeader, text: "YOU WROTE:")
        contentScrollView.addSubview(youWroteHeader)

        originalBg.backgroundColor = .secondarySystemFill
        originalBg.layer.cornerRadius = 8
        contentScrollView.addSubview(originalBg)

        originalLabel.font = .systemFont(ofSize: 15)
        originalLabel.textColor = .label
        originalLabel.numberOfLines = 0
        originalBg.addSubview(originalLabel)

        // WILL SEND AS:
        configureHeader(willSendHeader, text: "WILL SEND AS:")
        contentScrollView.addSubview(willSendHeader)

        translationBorder.backgroundColor = .tertiarySystemFill
        translationBorder.layer.cornerRadius = 8
        translationBorder.layer.borderWidth = 1
        translationBorder.layer.borderColor = UIColor.separator.cgColor
        contentScrollView.addSubview(translationBorder)

        translationLabel.font = .systemFont(ofSize: 16)
        translationLabel.textColor = .label
        translationLabel.numberOfLines = 0
        translationBorder.addSubview(translationLabel)

        editHintLabel.text = "Tap Edit to modify"
        editHintLabel.font = .systemFont(ofSize: 11)
        editHintLabel.textColor = .tertiaryLabel
        contentScrollView.addSubview(editHintLabel)

        // Back-translation (hidden by default)
        backTranslationLabel.font = .italicSystemFont(ofSize: 13)
        backTranslationLabel.textColor = .secondaryLabel
        backTranslationLabel.numberOfLines = 0
        backTranslationLabel.isHidden = true
        contentScrollView.addSubview(backTranslationLabel)

        // Context note (hidden by default)
        contextRow.isHidden = true
        contentScrollView.addSubview(contextRow)

        contextIcon.text = "\u{2139}\u{FE0F}"
        contextIcon.font = .systemFont(ofSize: 13)
        contextRow.addSubview(contextIcon)

        contextNoteLabel.font = .italicSystemFont(ofSize: 12)
        contextNoteLabel.textColor = .secondaryLabel
        contextNoteLabel.numberOfLines = 0
        contextRow.addSubview(contextNoteLabel)

        // TONE:
        configureHeader(toneHeader, text: "TONE:")
        contentScrollView.addSubview(toneHeader)

        for tone in ["Formal", "Friendly", "Direct"] {
            let pill = UIButton(type: .custom)
            pill.setTitle(tone, for: .normal)
            pill.titleLabel?.font = .systemFont(ofSize: 12, weight: .medium)
            pill.layer.cornerRadius = 14
            pill.clipsToBounds = true
            pill.contentEdgeInsets = UIEdgeInsets(top: 6, left: 14, bottom: 6, right: 14)
            pill.addTarget(self, action: #selector(toneTapped(_:)), for: .touchUpInside)
            contentScrollView.addSubview(pill)
            tonePills.append(pill)
        }
        updateToneAppearance()

        toneSpinner.hidesWhenStopped = true
        contentScrollView.addSubview(toneSpinner)

        // Bottom buttons — fixed at bottom, NOT in scroll view
        addSubview(buttonRow)

        // Edit button (outlined)
        editButton.setTitle(" Edit", for: .normal)
        editButton.setImage(UIImage(systemName: "pencil"), for: .normal)
        editButton.titleLabel?.font = .systemFont(ofSize: 15, weight: .medium)
        editButton.tintColor = .systemBlue
        editButton.setTitleColor(.systemBlue, for: .normal)
        editButton.layer.cornerRadius = 10
        editButton.layer.borderColor = UIColor.systemBlue.cgColor
        editButton.layer.borderWidth = 1
        editButton.addTarget(self, action: #selector(editTapped), for: .touchUpInside)
        buttonRow.addSubview(editButton)

        // Bookmark button
        bookmarkButton.setImage(UIImage(systemName: "star"), for: .normal)
        bookmarkButton.tintColor = UIColor.systemYellow
        bookmarkButton.backgroundColor = .tertiarySystemFill
        bookmarkButton.layer.cornerRadius = 10
        bookmarkButton.addTarget(self, action: #selector(bookmarkTapped), for: .touchUpInside)
        buttonRow.addSubview(bookmarkButton)

        // Send button (filled blue)
        sendButton.setTitle(" Send", for: .normal)
        let arrowConfig = UIImage.SymbolConfiguration(pointSize: 13, weight: .semibold)
        sendButton.setImage(UIImage(systemName: "arrow.up.right", withConfiguration: arrowConfig), for: .normal)
        sendButton.titleLabel?.font = .systemFont(ofSize: 15, weight: .semibold)
        sendButton.tintColor = .white
        sendButton.setTitleColor(.white, for: .normal)
        sendButton.backgroundColor = .systemBlue
        sendButton.layer.cornerRadius = 10
        sendButton.addTarget(self, action: #selector(sendTapped), for: .touchUpInside)
        buttonRow.addSubview(sendButton)
    }

    private func configureHeader(_ label: UILabel, text: String) {
        let attr = NSAttributedString(string: text, attributes: [
            .font: UIFont.systemFont(ofSize: 12, weight: .medium),
            .foregroundColor: UIColor.secondaryLabel,
            .kern: 1.0
        ])
        label.attributedText = attr
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        translationBorder.layer.borderColor = UIColor.separator.cgColor
        editButton.layer.borderColor = UIColor.systemBlue.cgColor
        for pill in tonePills where pill.title(for: .normal) != selectedTone {
            pill.layer.borderColor = UIColor.separator.cgColor
        }
    }

    // MARK: - Layout

    override func layoutSubviews() {
        super.layoutSubviews()
        let w = bounds.width
        let h = bounds.height
        let pad: CGFloat = 16
        let contentW = w - pad * 2

        // Reserve space for bottom buttons
        let btnAreaH: CGFloat = 64
        contentScrollView.frame = CGRect(x: 0, y: 0, width: w, height: h - btnAreaH)

        var y: CGFloat = 16

        // Title row
        titleLabel.frame = CGRect(x: pad, y: y, width: contentW - 30, height: 22)
        closeButton.frame = CGRect(x: w - pad - 28, y: y - 4, width: 28, height: 28)
        y += 32

        // YOU WROTE:
        youWroteHeader.frame = CGRect(x: pad, y: y, width: contentW, height: 16)
        y += 20

        let origSize = originalLabel.sizeThatFits(CGSize(width: contentW - 24, height: CGFloat.greatestFiniteMagnitude))
        let origH = max(36, min(origSize.height + 16, 90))
        originalBg.frame = CGRect(x: pad, y: y, width: contentW, height: origH)
        originalLabel.frame = CGRect(x: 12, y: 8, width: contentW - 24, height: origH - 16)
        y += origH + 16

        // WILL SEND AS:
        willSendHeader.frame = CGRect(x: pad, y: y, width: contentW, height: 16)
        y += 20

        let transSize = translationLabel.sizeThatFits(CGSize(width: contentW - 24, height: CGFloat.greatestFiniteMagnitude))
        let transH = max(40, min(transSize.height + 16, 120))
        translationBorder.frame = CGRect(x: pad, y: y, width: contentW, height: transH)
        translationLabel.frame = CGRect(x: 12, y: 8, width: contentW - 24, height: transH - 16)
        y += transH + 8

        if !isIncomingMode {
            editHintLabel.frame = CGRect(x: pad, y: y, width: contentW, height: 14)
            y += 20
        }

        // Back-translation
        if !backTranslationLabel.isHidden {
            let btSize = backTranslationLabel.sizeThatFits(CGSize(width: contentW, height: 80))
            let btH = max(18, btSize.height)
            backTranslationLabel.frame = CGRect(x: pad, y: y, width: contentW, height: btH)
            y += btH + 10
        }

        // Context note
        if !contextRow.isHidden {
            let noteSize = contextNoteLabel.sizeThatFits(CGSize(width: contentW - 24, height: 80))
            let noteH = max(20, noteSize.height)
            contextRow.frame = CGRect(x: pad, y: y, width: contentW, height: noteH)
            contextIcon.frame = CGRect(x: 0, y: 0, width: 18, height: noteH)
            contextNoteLabel.frame = CGRect(x: 22, y: 0, width: contentW - 24, height: noteH)
            y += noteH + 12
        }

        // TONE: (hidden in incoming mode)
        if !isIncomingMode {
            toneHeader.frame = CGRect(x: pad, y: y, width: contentW, height: 16)
            y += 20

            var tx: CGFloat = pad
            for pill in tonePills {
                pill.sizeToFit()
                let pillW = pill.frame.width + 16
                pill.frame = CGRect(x: tx, y: y, width: pillW, height: 28)
                tx += pillW + 8
            }
            toneSpinner.frame = CGRect(x: tx + 4, y: y + 2, width: 24, height: 24)
            y += 40
        }

        y += 8
        contentScrollView.contentSize = CGSize(width: w, height: y)

        // Bottom buttons — fixed at bottom
        let btnH: CGFloat = 48
        let bookmarkW: CGFloat = 48
        let spacing: CGFloat = 8
        buttonRow.frame = CGRect(x: pad, y: h - btnAreaH + 4, width: contentW, height: btnH)
        if isIncomingMode {
            let copyW = contentW - bookmarkW - spacing
            bookmarkButton.frame = CGRect(x: 0, y: 0, width: bookmarkW, height: btnH)
            sendButton.frame = CGRect(x: bookmarkW + spacing, y: 0, width: copyW, height: btnH)
        } else {
            let actionW = (contentW - bookmarkW - spacing * 2) / 2
            editButton.frame = CGRect(x: 0, y: 0, width: actionW, height: btnH)
            bookmarkButton.frame = CGRect(x: actionW + spacing, y: 0, width: bookmarkW, height: btnH)
            sendButton.frame = CGRect(x: actionW + spacing + bookmarkW + spacing, y: 0, width: actionW, height: btnH)
        }
    }

    // MARK: - Public Methods

    func updateTranslation(_ text: String) {
        translatedText = text
        translationLabel.textColor = .label
        translationLabel.alpha = 1.0
        toneSpinner.stopAnimating()
        backTranslationLabel.isHidden = true
        setNeedsLayout()
    }

    func updateBackTranslation(_ text: String) {
        if text.isEmpty {
            backTranslationLabel.isHidden = true
        } else {
            backTranslationLabel.text = "(\(text))"
            backTranslationLabel.isHidden = false
        }
        setNeedsLayout()
    }

    func updateContextNote(_ note: String) {
        contextNoteLabel.text = note
        contextRow.isHidden = false
        setNeedsLayout()
    }

    func showRetranslating() {
        toneSpinner.startAnimating()
        translationLabel.alpha = 0.5
    }

    func showRetranslateError() {
        toneSpinner.stopAnimating()
        translationLabel.textColor = .label
        translationLabel.alpha = 1.0
    }

    func configureIncomingMode() {
        isIncomingMode = true
        titleLabel.text = "Clipboard Translation"
        configureHeader(youWroteHeader, text: "THEY SENT:")
        configureHeader(willSendHeader, text: "TRANSLATION:")
        editHintLabel.isHidden = true
        toneHeader.isHidden = true
        for pill in tonePills { pill.isHidden = true }
        editButton.isHidden = true
        sendButton.setTitle(" Copy", for: .normal)
        let copyConfig = UIImage.SymbolConfiguration(pointSize: 13, weight: .semibold)
        sendButton.setImage(UIImage(systemName: "doc.on.doc", withConfiguration: copyConfig), for: .normal)
        setNeedsLayout()
    }

    func configureReplyMode() {
        isReplyMode = true
        titleLabel.text = "Suggested Reply"
        configureHeader(youWroteHeader, text: "THEY SAID:")
        configureHeader(willSendHeader, text: "SUGGESTED REPLY:")
        editHintLabel.text = "Tap Edit to modify before sending"
        sendButton.setTitle(" Use Reply", for: .normal)
        let sendConfig = UIImage.SymbolConfiguration(pointSize: 13, weight: .semibold)
        sendButton.setImage(UIImage(systemName: "arrow.up.right", withConfiguration: sendConfig), for: .normal)
        if !incomingText.isEmpty {
            originalLabel.text = incomingText
        }
        setNeedsLayout()
    }

    func showBookmarkConfirmed() {
        isBookmarked = true
        let config = UIImage.SymbolConfiguration(pointSize: 17, weight: .medium)
        bookmarkButton.setImage(UIImage(systemName: "star.fill", withConfiguration: config), for: .normal)
    }

    // MARK: - Tone

    private func updateToneAppearance() {
        for pill in tonePills {
            let title = pill.title(for: .normal)
            if title == selectedTone {
                pill.backgroundColor = .systemBlue
                pill.setTitleColor(.white, for: .normal)
                pill.layer.borderWidth = 0
            } else {
                pill.backgroundColor = .clear
                pill.setTitleColor(.label, for: .normal)
                pill.layer.borderWidth = 1
                pill.layer.borderColor = UIColor.separator.cgColor
            }
        }
    }

    @objc private func toneTapped(_ sender: UIButton) {
        guard let title = sender.title(for: .normal) else { return }
        if selectedTone == title {
            selectedTone = nil
        } else {
            selectedTone = title
        }
        updateToneAppearance()

        if let tone = selectedTone {
            let instruction: String
            switch tone {
            case "Formal":
                instruction = "FORMAL TONE: Use the most polite and respectful form of the language. Add honorifics. In Chinese, use \u{60A8} instead of \u{4F60}, add \u{8BF7}\u{95EE}, use formal sentence endings. In English, use 'Would you', 'May I', 'I would appreciate'. This is for a boss, a new client, or someone you deeply respect."
            case "Friendly":
                instruction = "FRIENDLY TONE: Use casual, warm language like texting a good friend or close colleague. In Chinese, use casual particles like \u{554A}\u{3001}\u{5440}\u{3001}\u{5462}\u{3001}\u{561B}, use colloquial expressions. In English, use contractions, casual phrasing. This is someone you're comfortable with."
            case "Direct":
                instruction = "DIRECT TONE: Use the absolute minimum words needed. No pleasantries, no fillers, no politeness markers. Just the core message. As short as possible. In Chinese, drop unnecessary particles. In English, use the fewest words possible."
            default:
                instruction = tone
            }
            onToneSelected?(instruction)
        }
    }

    // MARK: - Actions

    @objc private func closeTapped() { onClose?() }
    @objc private func editTapped() { onEdit?() }

    @objc private func bookmarkTapped() {
        guard !isBookmarked else { return }
        onBookmark?()
    }

    @objc private func sendTapped() { onSend?() }
}
