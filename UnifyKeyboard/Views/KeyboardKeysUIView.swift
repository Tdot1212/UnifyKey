import UIKit

enum KeyboardPage { case letters, numbers1, numbers2 }

class KeyboardKeysUIView: UIView {

    var onKeyTap: ((String) -> Void)?
    var onBackspace: (() -> Void)?
    var onSpace: (() -> Void)?
    var onReturn: (() -> Void)?
    var onShift: (() -> Void)?
    var onNumberToggle: (() -> Void)?
    var onPinyinToggle: (() -> Void)?

    private var keyButtons: [UIButton] = []
    private var shiftButton: UIButton?
    private(set) var isShifted = false
    private(set) var currentPage: KeyboardPage = .letters
    private(set) var isPinyinMode = false
    private var lastLayoutSize: CGSize = .zero
    private var backspaceTimer: Timer?

    private let letterRows = [
        ["q", "w", "e", "r", "t", "y", "u", "i", "o", "p"],
        ["a", "s", "d", "f", "g", "h", "j", "k", "l"],
        ["z", "x", "c", "v", "b", "n", "m"]
    ]

    private let numberRows1 = [
        ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"],
        ["-", "/", ":", ";", "(", ")", "$", "&", "@", "\""],
        [".", ",", "?", "!", "'"]
    ]

    private let numberRows2 = [
        ["[", "]", "{", "}", "#", "%", "^", "*", "+", "="],
        ["_", "\\", "|", "~", "<", ">", "€", "£", "¥", "•"],
        [".", ",", "?", "!", "'"]
    ]

    override init(frame: CGRect) {
        super.init(frame: frame)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        let w = bounds.width
        let h = bounds.height
        guard w > 0, h > 50 else { return }
        if lastLayoutSize == bounds.size && !subviews.isEmpty { return }
        lastLayoutSize = bounds.size
        rebuildKeys()
    }

    func setPage(_ page: KeyboardPage) {
        currentPage = page
        lastLayoutSize = .zero
        setNeedsLayout()
    }

    func setPinyinMode(_ enabled: Bool) {
        isPinyinMode = enabled
        lastLayoutSize = .zero
        setNeedsLayout()
    }

    private var activeRows: [[String]] {
        switch currentPage {
        case .letters: return letterRows
        case .numbers1: return numberRows1
        case .numbers2: return numberRows2
        }
    }

    private func rebuildKeys() {
        subviews.forEach { $0.removeFromSuperview() }
        keyButtons.removeAll()
        shiftButton = nil

        let w = bounds.width
        let h = bounds.height
        let rows = activeRows

        let keySpacingH: CGFloat = 6
        let keySpacingV: CGFloat = 10
        let bottomRowHeight: CGFloat = 42

        let availableHeight = h - bottomRowHeight - (keySpacingV * 2)
        let rowHeight = min(46, max(30, (availableHeight - keySpacingV * CGFloat(rows.count - 1)) / CGFloat(rows.count)))

        backspaceTimer?.invalidate()
        backspaceTimer = nil

        let isDark = traitCollection.userInterfaceStyle == .dark
        let keyBg: UIColor = isDark ? UIColor(white: 0.31, alpha: 1) : .white
        let specialBg: UIColor = isDark ? UIColor(white: 0.23, alpha: 1) : UIColor(red: 0.68, green: 0.70, blue: 0.73, alpha: 1)
        backgroundColor = isDark ? UIColor(white: 0.17, alpha: 1) : UIColor(red: 0.82, green: 0.83, blue: 0.85, alpha: 1)

        var y: CGFloat = keySpacingV / 2

        for (rowIndex, row) in rows.enumerated() {
            let keyCount = CGFloat(row.count)

            if rowIndex == 2 {
                let specialW: CGFloat = 40
                let availableForKeys = w - (keySpacingH + specialW + keySpacingH) * 2
                let adjustedKeyWidth = (availableForKeys - keySpacingH * (keyCount - 1)) / keyCount

                if currentPage == .letters {
                    let shiftBtn = makeSpecialKey(symbol: isShifted ? "shift.fill" : "shift", width: specialW, height: rowHeight, bg: specialBg)
                    shiftBtn.frame.origin = CGPoint(x: keySpacingH, y: y)
                    shiftBtn.addTarget(self, action: #selector(shiftTapped), for: .touchUpInside)
                    addSubview(shiftBtn)
                    shiftButton = shiftBtn
                } else {
                    let toggleTitle = currentPage == .numbers1 ? "#+=" : "123"
                    let toggleBtn = makeTextKey(toggleTitle, width: specialW, height: rowHeight, bg: specialBg)
                    toggleBtn.frame.origin = CGPoint(x: keySpacingH, y: y)
                    toggleBtn.addTarget(self, action: #selector(symbolToggleTapped), for: .touchUpInside)
                    addSubview(toggleBtn)
                }

                var x = keySpacingH + specialW + keySpacingH
                for key in row {
                    let btn = makeLetterKey(key, width: adjustedKeyWidth, height: rowHeight, bg: keyBg)
                    btn.frame.origin = CGPoint(x: x, y: y)
                    addSubview(btn)
                    keyButtons.append(btn)
                    x += adjustedKeyWidth + keySpacingH
                }

                let bsBtn = makeSpecialKey(symbol: "delete.left", width: specialW, height: rowHeight, bg: specialBg)
                bsBtn.frame.origin = CGPoint(x: w - keySpacingH - specialW, y: y)
                bsBtn.addTarget(self, action: #selector(backspaceTapped), for: .touchUpInside)
                let longPress = UILongPressGestureRecognizer(target: self, action: #selector(backspaceLongPressed(_:)))
                longPress.minimumPressDuration = 0.3
                bsBtn.addGestureRecognizer(longPress)
                addSubview(bsBtn)
            } else {
                let totalSpacing = keySpacingH * (keyCount + 1)
                let keyWidth = (w - totalSpacing) / keyCount
                let rowWidth = keyCount * keyWidth + (keyCount - 1) * keySpacingH
                var x = (w - rowWidth) / 2

                for key in row {
                    let btn = makeLetterKey(key, width: keyWidth, height: rowHeight, bg: keyBg)
                    btn.frame.origin = CGPoint(x: x, y: y)
                    addSubview(btn)
                    keyButtons.append(btn)
                    x += keyWidth + keySpacingH
                }
            }
            y += rowHeight + keySpacingV
        }

        // Bottom row
        let bottomY = y
        let smallKeyW: CGFloat = 42
        let returnW: CGFloat = 76
        let bottomSpacing = keySpacingH * 4
        let fixedW = smallKeyW * 2 + returnW
        let spaceW = w - fixedW - bottomSpacing
        var bx: CGFloat = keySpacingH

        let numTitle = currentPage == .letters ? "123" : "ABC"
        let numBtn = makeTextKey(numTitle, width: smallKeyW, height: bottomRowHeight, bg: specialBg)
        numBtn.frame.origin = CGPoint(x: bx, y: bottomY)
        numBtn.addTarget(self, action: #selector(numberToggleTapped), for: .touchUpInside)
        addSubview(numBtn)
        bx += smallKeyW + keySpacingH

        let langTitle = isPinyinMode ? "拼" : "EN"
        let langBg = isPinyinMode ? UIColor.systemBlue : specialBg
        let langBtn = makeTextKey(langTitle, width: smallKeyW, height: bottomRowHeight, bg: langBg)
        langBtn.titleLabel?.font = .systemFont(ofSize: 14, weight: .semibold)
        if isPinyinMode { langBtn.setTitleColor(.white, for: .normal) }
        langBtn.frame.origin = CGPoint(x: bx, y: bottomY)
        langBtn.addTarget(self, action: #selector(pinyinToggleTapped), for: .touchUpInside)
        addSubview(langBtn)
        bx += smallKeyW + keySpacingH

        let spaceBtn = UIButton(type: .custom)
        spaceBtn.frame = CGRect(x: bx, y: bottomY, width: spaceW, height: bottomRowHeight)
        styleKey(spaceBtn, bg: keyBg)
        spaceBtn.setTitle(isPinyinMode ? "选择" : "space", for: .normal)
        spaceBtn.setTitleColor(.label, for: .normal)
        spaceBtn.titleLabel?.font = .systemFont(ofSize: 15)
        spaceBtn.addTarget(self, action: #selector(spaceTapped), for: .touchUpInside)
        addSubview(spaceBtn)
        bx += spaceW + keySpacingH

        let retBtn = makeTextKey("return", width: returnW, height: bottomRowHeight, bg: specialBg)
        retBtn.frame.origin = CGPoint(x: bx, y: bottomY)
        retBtn.addTarget(self, action: #selector(returnTapped), for: .touchUpInside)
        addSubview(retBtn)
    }

    // MARK: - Key Factories

    private func makeLetterKey(_ letter: String, width: CGFloat, height: CGFloat, bg: UIColor) -> UIButton {
        let btn = UIButton(type: .custom)
        btn.frame.size = CGSize(width: width, height: height)
        styleKey(btn, bg: bg)
        let display = (currentPage == .letters && isShifted) ? letter.uppercased() : letter
        btn.setTitle(display, for: .normal)
        btn.setTitleColor(.label, for: .normal)
        btn.titleLabel?.font = currentPage == .letters ? .systemFont(ofSize: 22) : .systemFont(ofSize: 20)
        btn.addTarget(self, action: #selector(letterTapped(_:)), for: .touchDown)
        return btn
    }

    private func makeSpecialKey(symbol: String, width: CGFloat, height: CGFloat, bg: UIColor) -> UIButton {
        let btn = UIButton(type: .custom)
        btn.frame.size = CGSize(width: width, height: height)
        styleKey(btn, bg: bg)
        let config = UIImage.SymbolConfiguration(pointSize: 18)
        btn.setImage(UIImage(systemName: symbol, withConfiguration: config), for: .normal)
        btn.tintColor = .label
        return btn
    }

    private func makeTextKey(_ title: String, width: CGFloat, height: CGFloat, bg: UIColor) -> UIButton {
        let btn = UIButton(type: .custom)
        btn.frame.size = CGSize(width: width, height: height)
        styleKey(btn, bg: bg)
        btn.setTitle(title, for: .normal)
        btn.setTitleColor(.label, for: .normal)
        btn.titleLabel?.font = .systemFont(ofSize: 15)
        return btn
    }

    // NO SHADOWS — just background + corner radius
    private func styleKey(_ btn: UIButton, bg: UIColor) {
        btn.backgroundColor = bg
        btn.layer.cornerRadius = 5
    }

    // MARK: - Public

    func updateShiftState(_ shifted: Bool) {
        isShifted = shifted
        guard currentPage == .letters else { return }
        for btn in keyButtons {
            if let title = btn.title(for: .normal) {
                btn.setTitle(shifted ? title.uppercased() : title.lowercased(), for: .normal)
            }
        }
        let config = UIImage.SymbolConfiguration(pointSize: 18)
        shiftButton?.setImage(UIImage(systemName: shifted ? "shift.fill" : "shift", withConfiguration: config), for: .normal)
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if traitCollection.userInterfaceStyle != previousTraitCollection?.userInterfaceStyle {
            lastLayoutSize = .zero
            setNeedsLayout()
        }
    }

    // MARK: - Actions

    // NO TRANSFORM, NO BACKGROUND CHANGE — just alpha for speed
    @objc private func letterTapped(_ sender: UIButton) {
        sender.alpha = 0.4
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            sender.alpha = 1.0
        }
        if let letter = sender.title(for: .normal) { onKeyTap?(letter) }
    }

    @objc private func backspaceTapped() { onBackspace?() }

    @objc private func backspaceLongPressed(_ gesture: UILongPressGestureRecognizer) {
        switch gesture.state {
        case .began:
            backspaceTimer = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { [weak self] _ in
                self?.onBackspace?()
            }
        case .ended, .cancelled:
            backspaceTimer?.invalidate()
            backspaceTimer = nil
        default:
            break
        }
    }

    @objc private func spaceTapped() { onSpace?() }
    @objc private func returnTapped() { onReturn?() }
    @objc private func shiftTapped() { onShift?() }
    @objc private func numberToggleTapped() { onNumberToggle?() }
    @objc private func pinyinToggleTapped() { onPinyinToggle?() }
    @objc private func symbolToggleTapped() {
        currentPage = (currentPage == .numbers1) ? .numbers2 : .numbers1
        lastLayoutSize = .zero
        setNeedsLayout()
    }
}
