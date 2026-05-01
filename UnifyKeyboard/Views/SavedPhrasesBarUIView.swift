import UIKit

class SavedPhrasesBarUIView: UIView {

    var onPhraseTap: ((String) -> Void)?
    var onPhraseDelete: ((Int) -> Void)?

    private let scrollView = UIScrollView()
    private let starIcon = UILabel()
    private var pillButtons: [UIButton] = []

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = UIColor.systemBackground.withAlphaComponent(0.9)

        starIcon.text = "★"
        starIcon.font = .systemFont(ofSize: 14)
        starIcon.textColor = .systemYellow
        addSubview(starIcon)

        scrollView.showsHorizontalScrollIndicator = false
        addSubview(scrollView)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        let h = bounds.height
        starIcon.frame = CGRect(x: 8, y: 0, width: 20, height: h)
        scrollView.frame = CGRect(x: 30, y: 0, width: bounds.width - 38, height: h)
    }

    func reload() {
        pillButtons.forEach { $0.removeFromSuperview() }
        pillButtons.removeAll()

        let phrases = SharedSettings.shared.savedPhrases
        var x: CGFloat = 0
        let h: CGFloat = bounds.height > 0 ? bounds.height - 8 : 24
        let y: CGFloat = 4

        for (i, phrase) in phrases.enumerated() {
            guard let translation = phrase["translation"], !translation.isEmpty else { continue }
            let display = String(translation.prefix(30))

            let btn = UIButton(type: .custom)
            btn.setTitle(display, for: .normal)
            btn.titleLabel?.font = .systemFont(ofSize: 12)
            btn.setTitleColor(.label, for: .normal)
            btn.backgroundColor = UIColor.tertiarySystemFill
            btn.layer.cornerRadius = h / 2
            btn.contentEdgeInsets = UIEdgeInsets(top: 4, left: 12, bottom: 4, right: 12)
            btn.sizeToFit()
            btn.frame = CGRect(x: x, y: y, width: btn.frame.width + 12, height: h)
            btn.tag = i
            btn.addTarget(self, action: #selector(pillTapped(_:)), for: .touchUpInside)

            let longPress = UILongPressGestureRecognizer(target: self, action: #selector(pillLongPressed(_:)))
            btn.addGestureRecognizer(longPress)

            scrollView.addSubview(btn)
            pillButtons.append(btn)
            x += btn.frame.width + 8
        }

        scrollView.contentSize = CGSize(width: x, height: bounds.height)
    }

    var hasContent: Bool {
        let phrases = SharedSettings.shared.savedPhrases
        return !phrases.isEmpty
    }

    @objc private func pillTapped(_ sender: UIButton) {
        let phrases = SharedSettings.shared.savedPhrases
        let idx = sender.tag
        guard idx < phrases.count, let translation = phrases[idx]["translation"] else { return }
        onPhraseTap?(translation)
    }

    @objc private func pillLongPressed(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began, let btn = gesture.view as? UIButton else { return }
        onPhraseDelete?(btn.tag)
    }
}
