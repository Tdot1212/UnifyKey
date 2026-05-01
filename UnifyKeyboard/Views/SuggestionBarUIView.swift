import UIKit

class SuggestionBarUIView: UIView {

    var onSuggestionTap: ((String) -> Void)?

    private var buttons: [UIButton] = []
    private var dividers: [UIView] = []
    private let pinyinScrollView = UIScrollView()
    private var pinyinButtons: [UIButton] = []
    private var isPinyinActive = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = UIColor.systemBackground.withAlphaComponent(0.95)
        buildSlots()

        pinyinScrollView.showsHorizontalScrollIndicator = false
        pinyinScrollView.isHidden = true
        addSubview(pinyinScrollView)
    }

    required init?(coder: NSCoder) { fatalError() }

    override var intrinsicContentSize: CGSize {
        return CGSize(width: UIView.noIntrinsicMetric, height: 36)
    }

    private func buildSlots() {
        for i in 0..<3 {
            let btn = UIButton(type: .custom)
            btn.titleLabel?.font = .systemFont(ofSize: 15)
            btn.setTitleColor(.label, for: .normal)
            btn.tag = i
            btn.addTarget(self, action: #selector(slotTapped(_:)), for: .touchUpInside)
            addSubview(btn)
            buttons.append(btn)
        }
        for _ in 0..<2 {
            let div = UIView()
            div.backgroundColor = .separator
            addSubview(div)
            dividers.append(div)
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let w = bounds.width
        let h = bounds.height

        if isPinyinActive {
            pinyinScrollView.frame = CGRect(x: 0, y: 0, width: w, height: h)
        }

        let slotW = w / 3
        for (i, btn) in buttons.enumerated() {
            btn.frame = CGRect(x: slotW * CGFloat(i), y: 0, width: slotW, height: h)
        }
        for (i, div) in dividers.enumerated() {
            let x = slotW * CGFloat(i + 1)
            div.frame = CGRect(x: x, y: 6, width: 0.5, height: h - 12)
        }
    }

    func update(suggestions: [WordSuggestion]) {
        for (i, btn) in buttons.enumerated() {
            if i < suggestions.count {
                let s = suggestions[i]
                btn.setTitle(s.word, for: .normal)
                btn.titleLabel?.font = s.isAutocorrect
                    ? .systemFont(ofSize: 15, weight: .bold)
                    : .systemFont(ofSize: 15)
                btn.isHidden = false
            } else {
                btn.setTitle(nil, for: .normal)
                btn.isHidden = true
            }
        }
        dividers.forEach { $0.isHidden = suggestions.count < 2 }
    }

    private var pinyinSeparators: [UIView] = []

    func updatePinyin(candidates: [String]) {
        isPinyinActive = true
        buttons.forEach { $0.isHidden = true }
        dividers.forEach { $0.isHidden = true }
        pinyinScrollView.isHidden = false

        while pinyinButtons.count < candidates.count {
            let btn = UIButton(type: .custom)
            btn.setTitleColor(.label, for: .normal)
            btn.addTarget(self, action: #selector(pinyinSlotTapped(_:)), for: .touchUpInside)
            pinyinScrollView.addSubview(btn)
            pinyinButtons.append(btn)
        }
        while pinyinSeparators.count < candidates.count {
            let sep = UIView()
            sep.backgroundColor = .separator
            pinyinScrollView.addSubview(sep)
            pinyinSeparators.append(sep)
        }

        for (i, btn) in pinyinButtons.enumerated() {
            btn.isHidden = i >= candidates.count
        }
        for (i, sep) in pinyinSeparators.enumerated() {
            sep.isHidden = i >= candidates.count || i == 0
        }

        let h = bounds.height
        var x: CGFloat = 8

        for (i, candidate) in candidates.enumerated() {
            let btn = pinyinButtons[i]
            btn.setTitle(candidate, for: .normal)
            btn.titleLabel?.font = i == 0
                ? .systemFont(ofSize: 18, weight: .bold)
                : .systemFont(ofSize: 18)

            let size = (candidate as NSString).size(withAttributes: [.font: UIFont.systemFont(ofSize: 18)])
            let btnW = max(40, size.width + 20)
            btn.frame = CGRect(x: x, y: 0, width: btnW, height: h)

            if i > 0 {
                pinyinSeparators[i].frame = CGRect(x: x - 4, y: 8, width: 0.5, height: h - 16)
                pinyinSeparators[i].isHidden = false
            }

            x += btnW + 8
        }

        pinyinScrollView.contentSize = CGSize(width: x, height: h)
        pinyinScrollView.frame = CGRect(x: 0, y: 0, width: bounds.width, height: h)
    }

    func clear() {
        isPinyinActive = false
        pinyinScrollView.isHidden = true
        pinyinButtons.forEach { $0.removeFromSuperview() }
        pinyinButtons.removeAll()
        buttons.forEach { $0.setTitle(nil, for: .normal); $0.isHidden = true }
        dividers.forEach { $0.isHidden = true }
    }

    @objc private func slotTapped(_ sender: UIButton) {
        if let title = sender.title(for: .normal), !title.isEmpty {
            onSuggestionTap?(title)
        }
    }

    @objc private func pinyinSlotTapped(_ sender: UIButton) {
        if let title = sender.title(for: .normal), !title.isEmpty {
            onSuggestionTap?(title)
        }
    }
}
