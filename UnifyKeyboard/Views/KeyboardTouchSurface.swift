import UIKit

protocol KeyboardTouchSurfaceDelegate: AnyObject {
    func keyPressed(_ key: String)
    func backspacePressed()
    func backspaceLongPressed()
    func backspaceReleased()
    func spacePressed()
    func returnPressed()
    func shiftPressed()
    func numberTogglePressed()
    func pinyinTogglePressed()
    func pinyinToggleLongPressed()
}

class KeyboardTouchSurface: UIView {

    weak var delegate: KeyboardTouchSurfaceDelegate?

    struct KeyRegion {
        let rect: CGRect
        let key: String
        let isSpecial: Bool
        let displayText: String
        let fontSize: CGFloat
    }

    private var keyRegions: [KeyRegion] = []
    private var activeKeyIndex: Int? = nil
    private var isShifted = false
    private var isPinyinMode = false
    private var currentPage: KeyboardPage = .letters
    private var lastLayoutSize: CGSize = .zero
    private var backspaceTimer: Timer?
    private var backspaceRepeatCount = 0
    private var backspaceWordMode = false
    private var langLongPressTimer: Timer?
    private var langLongPressFired = false

    private var keyBg: UIColor = .white
    private var specialBg: UIColor = UIColor(red: 0.678, green: 0.702, blue: 0.737, alpha: 1)
    private var textColor: UIColor = .label
    private var bgColor: UIColor = UIColor(red: 0.82, green: 0.827, blue: 0.851, alpha: 1)

    private let letterRows: [[String]] = [
        ["q","w","e","r","t","y","u","i","o","p"],
        ["a","s","d","f","g","h","j","k","l"],
        ["z","x","c","v","b","n","m"]
    ]

    private let numberRows1: [[String]] = [
        ["1","2","3","4","5","6","7","8","9","0"],
        ["-","/",":",";","(",")","$","&","@","\""],
        [".",",","?","!","'"]
    ]

    private let numberRows2: [[String]] = [
        ["[","]","{","}","#","%","^","*","+","="],
        ["_","\\","|","~","<",">","€","£","¥","•"],
        [".",",","?","!","'"]
    ]

    override init(frame: CGRect) {
        super.init(frame: frame)
        isMultipleTouchEnabled = false
        isExclusiveTouch = true
        contentMode = .redraw
    }

    required init?(coder: NSCoder) { fatalError() }

    func configure(shifted: Bool, pinyinMode: Bool, page: KeyboardPage) {
        let changed = shifted != isShifted || pinyinMode != isPinyinMode || page != currentPage
        isShifted = shifted
        isPinyinMode = pinyinMode
        currentPage = page
        if changed {
            computeRegions()
            setNeedsDisplay()
        }
    }

    func updateShift(_ shifted: Bool) {
        guard shifted != isShifted else { return }
        isShifted = shifted

        for i in 0..<keyRegions.count {
            let r = keyRegions[i]
            if !r.isSpecial && currentPage == .letters {
                let baseKey = r.key.lowercased()
                let newDisplay = shifted ? baseKey.uppercased() : baseKey
                if r.displayText != newDisplay {
                    keyRegions[i] = KeyRegion(
                        rect: r.rect,
                        key: shifted ? baseKey.uppercased() : baseKey,
                        isSpecial: false,
                        displayText: newDisplay,
                        fontSize: r.fontSize
                    )
                }
            }
        }

        if let shiftRegion = keyRegions.first(where: { $0.key == "__shift__" }) {
            let dirtyRect = CGRect(
                x: 0, y: 0,
                width: bounds.width,
                height: shiftRegion.rect.maxY + 4
            )
            setNeedsDisplay(dirtyRect)
        } else {
            setNeedsDisplay()
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        if bounds.size != lastLayoutSize && bounds.width > 0 && bounds.height > 50 {
            lastLayoutSize = bounds.size
            updateColors()
            computeRegions()
            setNeedsDisplay()
        }
    }

    private func updateColors() {
        let isDark = traitCollection.userInterfaceStyle == .dark
        keyBg = isDark ? UIColor(white: 0.35, alpha: 1) : .white
        specialBg = isDark ? UIColor(white: 0.25, alpha: 1) : UIColor(red: 0.678, green: 0.702, blue: 0.737, alpha: 1)
        textColor = .label
        bgColor = isDark ? UIColor(white: 0.12, alpha: 1) : UIColor(red: 0.82, green: 0.827, blue: 0.851, alpha: 1)
        backgroundColor = bgColor
    }

    private func computeRegions() {
        keyRegions.removeAll()

        let w = bounds.width
        let h = bounds.height
        guard w > 0, h > 50 else { return }

        let spacing: CGFloat = 6
        let vSpacing: CGFloat = 8
        let bottomRowH: CGFloat = 42
        let letterAreaH = h - bottomRowH - vSpacing
        let rowH = (letterAreaH - vSpacing * 2) / 3

        let rows: [[String]]
        switch currentPage {
        case .letters: rows = letterRows
        case .numbers1: rows = numberRows1
        case .numbers2: rows = numberRows2
        }

        var y: CGFloat = 0

        for (rowIdx, row) in rows.enumerated() {
            if rowIdx == 2 && currentPage == .letters {
                let specialW: CGFloat = 42
                let availableW = w - (spacing + specialW + spacing) * 2
                let keyW = (availableW - spacing * CGFloat(row.count - 1)) / CGFloat(row.count)

                keyRegions.append(KeyRegion(
                    rect: CGRect(x: spacing, y: y, width: specialW, height: rowH),
                    key: "__shift__", isSpecial: true,
                    displayText: isShifted ? "⬆" : "⇧", fontSize: 18
                ))

                var x = spacing + specialW + spacing
                for key in row {
                    let display = isShifted ? key.uppercased() : key
                    keyRegions.append(KeyRegion(
                        rect: CGRect(x: x, y: y, width: keyW, height: rowH),
                        key: display, isSpecial: false,
                        displayText: display, fontSize: 22
                    ))
                    x += keyW + spacing
                }

                keyRegions.append(KeyRegion(
                    rect: CGRect(x: w - spacing - specialW, y: y, width: specialW, height: rowH),
                    key: "__backspace__", isSpecial: true,
                    displayText: "⌫", fontSize: 18
                ))
            } else if rowIdx == 2 && currentPage != .letters {
                let specialW: CGFloat = 42
                let availableW = w - (spacing + specialW + spacing) * 2
                let keyW = (availableW - spacing * CGFloat(row.count - 1)) / CGFloat(row.count)

                let toggleTitle = currentPage == .numbers1 ? "#+=" : "123"
                keyRegions.append(KeyRegion(
                    rect: CGRect(x: spacing, y: y, width: specialW, height: rowH),
                    key: "__symtoggle__", isSpecial: true,
                    displayText: toggleTitle, fontSize: 14
                ))

                var x = spacing + specialW + spacing
                for key in row {
                    keyRegions.append(KeyRegion(
                        rect: CGRect(x: x, y: y, width: keyW, height: rowH),
                        key: key, isSpecial: false,
                        displayText: key, fontSize: 20
                    ))
                    x += keyW + spacing
                }

                keyRegions.append(KeyRegion(
                    rect: CGRect(x: w - spacing - specialW, y: y, width: specialW, height: rowH),
                    key: "__backspace__", isSpecial: true,
                    displayText: "⌫", fontSize: 18
                ))
            } else {
                let count = CGFloat(row.count)
                let totalSpacing = spacing * (count + 1)
                let keyW = (w - totalSpacing) / count
                let rowW = count * keyW + (count - 1) * spacing
                var x = (w - rowW) / 2

                for key in row {
                    let display = (currentPage == .letters && isShifted) ? key.uppercased() : key
                    keyRegions.append(KeyRegion(
                        rect: CGRect(x: x, y: y, width: keyW, height: rowH),
                        key: display, isSpecial: false,
                        displayText: display, fontSize: currentPage == .letters ? 22 : 20
                    ))
                    x += keyW + spacing
                }
            }
            y += rowH + vSpacing
        }

        let smallW: CGFloat = 44
        let returnW: CGFloat = 80
        let fixedW = smallW * 2 + returnW + spacing * 4
        let spaceW = w - fixedW
        var bx: CGFloat = spacing

        let numTitle = currentPage == .letters ? "123" : "ABC"
        keyRegions.append(KeyRegion(
            rect: CGRect(x: bx, y: y, width: smallW, height: bottomRowH),
            key: "__numtoggle__", isSpecial: true,
            displayText: numTitle, fontSize: 15
        ))
        bx += smallW + spacing

        let langTitle = isPinyinMode ? "拼" : "EN"
        keyRegions.append(KeyRegion(
            rect: CGRect(x: bx, y: y, width: smallW, height: bottomRowH),
            key: "__langtoggle__", isSpecial: true,
            displayText: langTitle, fontSize: 14
        ))
        bx += smallW + spacing

        let spaceTitle = isPinyinMode ? "选择" : "space"
        keyRegions.append(KeyRegion(
            rect: CGRect(x: bx, y: y, width: spaceW, height: bottomRowH),
            key: "__space__", isSpecial: false,
            displayText: spaceTitle, fontSize: 16
        ))
        bx += spaceW + spacing

        keyRegions.append(KeyRegion(
            rect: CGRect(x: bx, y: y, width: returnW, height: bottomRowH),
            key: "__return__", isSpecial: true,
            displayText: "return", fontSize: 15
        ))
    }

    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }

        ctx.setFillColor(bgColor.cgColor)
        ctx.fill(rect)

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center

        for (index, region) in keyRegions.enumerated() {
            // Skip keys outside dirty rect
            if !region.rect.insetBy(dx: -4, dy: -4).intersects(rect) {
                continue
            }

            let bg: UIColor
            if index == activeKeyIndex {
                bg = UIColor.systemBlue.withAlphaComponent(0.3)
            } else if region.key == "__langtoggle__" && isPinyinMode {
                bg = .systemBlue
            } else if region.isSpecial {
                bg = specialBg
            } else {
                bg = keyBg
            }

            let path = UIBezierPath(roundedRect: region.rect, cornerRadius: 5)
            ctx.setFillColor(bg.cgColor)
            ctx.addPath(path.cgPath)
            ctx.fillPath()

            let textColorForKey: UIColor
            if region.key == "__langtoggle__" && isPinyinMode {
                textColorForKey = .white
            } else if region.key == "__shift__" && isShifted {
                textColorForKey = .systemBlue
            } else {
                textColorForKey = textColor
            }

            let attrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: region.fontSize, weight: region.isSpecial ? .medium : .regular),
                .foregroundColor: textColorForKey,
                .paragraphStyle: paragraphStyle
            ]

            let textSize = region.displayText.size(withAttributes: attrs)
            let textRect = CGRect(
                x: region.rect.midX - textSize.width / 2,
                y: region.rect.midY - textSize.height / 2,
                width: textSize.width,
                height: textSize.height
            )
            region.displayText.draw(in: textRect, withAttributes: attrs)
        }
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let pt = touches.first?.location(in: self) else { return }
        if let idx = keyRegions.firstIndex(where: { $0.rect.insetBy(dx: -2, dy: -2).contains(pt) }) {
            activeKeyIndex = idx

            let region = keyRegions[idx]
            handleKeyAction(region)

            setNeedsDisplay(region.rect.insetBy(dx: -4, dy: -4))

            if region.key == "__backspace__" {
                backspaceRepeatCount = 0
                backspaceWordMode = false
                backspaceTimer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: false) { [weak self] _ in
                    self?.delegate?.backspaceLongPressed()
                    self?.backspaceWordMode = true
                    self?.startBackspaceRepeat()
                }
            } else if region.key == "__langtoggle__" {
                langLongPressFired = false
                langLongPressTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { [weak self] _ in
                    self?.langLongPressFired = true
                    self?.delegate?.pinyinToggleLongPressed()
                }
            }
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let pt = touches.first?.location(in: self) else { return }
        let newIdx = keyRegions.firstIndex(where: { $0.rect.insetBy(dx: -2, dy: -2).contains(pt) })
        if newIdx != activeKeyIndex {
            let oldRect = activeKeyIndex.flatMap { keyRegions[$0].rect }
            activeKeyIndex = newIdx
            if let r = oldRect { setNeedsDisplay(r.insetBy(dx: -4, dy: -4)) }
            if let idx = newIdx { setNeedsDisplay(keyRegions[idx].rect.insetBy(dx: -4, dy: -4)) }

            if newIdx == nil || keyRegions[newIdx!].key != "__backspace__" {
                backspaceTimer?.invalidate()
                backspaceTimer = nil
                delegate?.backspaceReleased()
            }
            langLongPressTimer?.invalidate()
            langLongPressTimer = nil
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        if let idx = activeKeyIndex {
            setNeedsDisplay(keyRegions[idx].rect.insetBy(dx: -4, dy: -4))
        }
        activeKeyIndex = nil
        backspaceTimer?.invalidate()
        backspaceTimer = nil
        langLongPressTimer?.invalidate()
        langLongPressTimer = nil
        delegate?.backspaceReleased()
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        if let idx = activeKeyIndex {
            setNeedsDisplay(keyRegions[idx].rect.insetBy(dx: -4, dy: -4))
        }
        activeKeyIndex = nil
        backspaceTimer?.invalidate()
        backspaceTimer = nil
        langLongPressTimer?.invalidate()
        langLongPressTimer = nil
        delegate?.backspaceReleased()
    }

    private func handleKeyAction(_ region: KeyRegion) {
        switch region.key {
        case "__shift__": delegate?.shiftPressed()
        case "__backspace__": delegate?.backspacePressed()
        case "__space__": delegate?.spacePressed()
        case "__return__": delegate?.returnPressed()
        case "__numtoggle__": delegate?.numberTogglePressed()
        case "__langtoggle__":
            if !langLongPressFired {
                delegate?.pinyinTogglePressed()
            }
        case "__symtoggle__":
            currentPage = (currentPage == .numbers1) ? .numbers2 : .numbers1
            computeRegions()
            setNeedsDisplay()
        default:
            delegate?.keyPressed(region.key)
        }
    }

    private func startBackspaceRepeat() {
        backspaceTimer?.invalidate()
        backspaceRepeatCount = 0
        backspaceWordMode = false
        backspaceTimer = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            self.backspaceRepeatCount += 1

            if self.backspaceRepeatCount >= 10 && !self.backspaceWordMode {
                self.backspaceWordMode = true
            }

            if self.backspaceWordMode {
                self.delegate?.backspaceLongPressed()
            } else {
                self.delegate?.backspacePressed()
            }
        }
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if traitCollection.userInterfaceStyle != previousTraitCollection?.userInterfaceStyle {
            updateColors()
            setNeedsDisplay()
        }
    }
}
