import UIKit
import Translation

class KeyboardViewController: UIInputViewController {

    // MARK: - State
    private var isShifted = false
    private var currentPage: KeyboardPage = .letters
    private var showGlobeSwitchKey = false
    private let haptic = UIImpactFeedbackGenerator(style: .light)
    private let notificationHaptic = UINotificationFeedbackGenerator()

    // Dedicated, throttled haptic for individual key presses.
    // Separate from `haptic` so the per-keystroke path stays minimal.
    // .light = lowest-latency style; throttle prevents buildup during fast typing.
    private let keyHaptic = UIImpactFeedbackGenerator(style: .light)
    private var lastHapticTime: CFAbsoluteTime = 0
    private let hapticThrottleMs: CFAbsoluteTime = 0.03  // 30ms minimum between haptics

    // Cached settings — avoids keychain IPC on every keystroke
    private var cachedHapticEnabled: Bool = true
    private var lastClipboardCheckTime: CFAbsoluteTime = 0
    private var translationTask: Task<Void, Never>?
    private var currentTargetLanguage: SupportedLanguage?
    private var heightConstraint: NSLayoutConstraint?
    private var isEditingTranslation = false
    private var currentOriginalText = ""
    private var currentTranslatedText = ""
    private var idleResetTimer: DispatchWorkItem?

    // Translation source tracking
    private enum TranslationSource { case cache, offline, apple, ai }
    private var lastTranslationSource: TranslationSource = .ai

    // Translation cache
    private var translationCache: [String: String] = [:]
    private let maxCacheSize = 30

    // Tone re-translation cache (tone name → translated text)
    private var toneCache: [String: (translation: String, backTranslation: String)] = [:]

    // MARK: - View References
    private var translationBar: TranslationBarUIView!
    private var suggestionBar: SuggestionBarUIView!
    private var touchSurface: KeyboardTouchSurface!

    // Local text cache — avoids expensive IPC on every keystroke
    private var localTextCache: String = ""

    private func appendToCache(_ s: String) {
        localTextCache += s
        if localTextCache.count > 200 {
            localTextCache = String(localTextCache.suffix(200))
        }
    }
    private var textSyncTimer: Timer?
    private var languagePickerOverlay: UIView?
    private var previewCard: TranslationPreviewCardUIView?
    private var editingBanner: UIView?

    // MARK: - Lifecycle

    deinit {
        textSyncTimer?.invalidate()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.isExclusiveTouch = true
        showGlobeSwitchKey = needsInputModeSwitchKey
        haptic.prepare()
        notificationHaptic.prepare()
        keyHaptic.prepare()
        // Record Full Access state so the main app's settings can warn the
        // user — UIFeedbackGenerator silently no-ops without it.
        SharedSettings.shared.hasKeyboardFullAccess = self.hasFullAccess
        cachedHapticEnabled = SharedSettings.shared.hapticFeedbackEnabled
        buildKeyboard()

        // Periodic sync to keep cache consistent with proxy (e.g. autocorrect, dictation)
        textSyncTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            self.localTextCache = String((self.textDocumentProxy.documentContextBeforeInput ?? "").suffix(200))
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        if heightConstraint == nil {
            let c = view.heightAnchor.constraint(equalToConstant: 300)
            c.priority = UILayoutPriority(999)
            c.isActive = true
            heightConstraint = c
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        checkClipboard()
        // Retry after 0.5s in case clipboard wasn't ready
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.checkClipboard()
        }
        // Retry again after 1.5s
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            self?.checkClipboard()
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        UserWordFrequency.shared.flush()
        UserBigramPredictor.shared.flush()
    }

    override func textDidChange(_ textInput: UITextInput?) {
        super.textDidChange(textInput)
        // Sync local cache from proxy (catches external changes, autocorrect, etc.)
        localTextCache = String((textDocumentProxy.documentContextBeforeInput ?? "").suffix(200))
        // Throttle clipboard checks to at most once per 3 seconds
        if !isClipboardTranslation {
            let now = CFAbsoluteTimeGetCurrent()
            if now - lastClipboardCheckTime > 3.0 {
                lastClipboardCheckTime = now
                checkClipboard()
            }
        }
    }

    // MARK: - Build Keyboard

    private func buildKeyboard() {
        view.subviews.forEach { $0.removeFromSuperview() }
        view.backgroundColor = keyboardBgColor

        let mainStack = UIStackView()
        mainStack.axis = .vertical
        mainStack.distribution = .fill
        mainStack.spacing = 0
        mainStack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(mainStack)

        NSLayoutConstraint.activate([
            mainStack.topAnchor.constraint(equalTo: view.topAnchor),
            mainStack.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            mainStack.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            mainStack.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])

        // 1. Translation bar (50pt)
        translationBar = TranslationBarUIView()
        translationBar.heightAnchor.constraint(equalToConstant: 50).isActive = true
        translationBar.onSendTranslation = { [weak self] in self?.translateButtonTapped() }
        translationBar.onActionLongPress = { [weak self] in self?.translateAndShowPreview() }
        translationBar.onLanguageTap = { [weak self] in self?.cycleTargetLanguage() }
        translationBar.onLanguageLongPress = { [weak self] in self?.showLanguagePicker() }
        translationBar.onReplyTap = { [weak self] in
            self?.generateReply()
        }
        translationBar.onDismissClipboard = { [weak self] in
            self?.exitClipboardMode()
        }
        translationBar.onTranslationTapped = { [weak self] in
            guard let self = self else { return }
            self.idleResetTimer?.cancel()

            // If we have smart replies cached, reshow the popup
            if !self.smartReplies.isEmpty && self.isClipboardTranslation {
                self.showSmartReplyPopup()
                return
            }

            // If clipboard translation active but replies were cleared, regenerate
            if self.isClipboardTranslation && !self.currentTranslatedText.isEmpty {
                let targetLang = self.resolveTargetLanguage()
                self.generateSmartReplies(translatedMessage: self.currentTranslatedText, targetLang: targetLang)
                return
            }

            // Normal outgoing translation — show preview card
            guard !self.currentTranslatedText.isEmpty else { return }
            self.showPreviewCard()
        }
        mainStack.addArrangedSubview(translationBar)

        let targetLang = resolveTargetLanguage()
        translationBar.updateTargetLanguage(targetLang.rawValue)

        // 2. Suggestion bar (36pt)
        suggestionBar = SuggestionBarUIView()
        suggestionBar.heightAnchor.constraint(equalToConstant: 36).isActive = true
        suggestionBar.onSuggestionTap = { [weak self] word in self?.acceptSuggestion(word) }
        mainStack.addArrangedSubview(suggestionBar)

        showPlaceholderSuggestions()

        // 3. Key touch surface — single Core Graphics view, no UIButtons
        touchSurface = KeyboardTouchSurface()
        touchSurface.delegate = self
        touchSurface.setContentHuggingPriority(UILayoutPriority(1), for: .vertical)
        touchSurface.setContentCompressionResistancePriority(UILayoutPriority(1), for: .vertical)
        mainStack.addArrangedSubview(touchSurface)

        let keysMinHeight = touchSurface.heightAnchor.constraint(greaterThanOrEqualToConstant: 200)
        keysMinHeight.priority = UILayoutPriority(999)
        keysMinHeight.isActive = true

        touchSurface.configure(shifted: isShifted, pinyinMode: isPinyinMode, page: currentPage)
    }

    private func showPlaceholderSuggestions() {
        guard !isPinyinMode else { return }
        suggestionBar.update(suggestions: [
            WordSuggestion(word: "the", isAutocorrect: false),
            WordSuggestion(word: "I", isAutocorrect: true),
            WordSuggestion(word: "and", isAutocorrect: false),
        ])
    }

    private var suggestionWorkItem: DispatchWorkItem?
    private var suggestionTimer: DispatchWorkItem?
    private var lastKeyPressTime: CFAbsoluteTime = 0

    private func scheduleSuggestionUpdate() {
        lastKeyPressTime = CFAbsoluteTimeGetCurrent()
        suggestionTimer?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            let elapsed = CFAbsoluteTimeGetCurrent() - self.lastKeyPressTime
            if elapsed < 0.12 { return }
            self.updateWordSuggestions()
        }
        suggestionTimer = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
    }

    private func updateWordSuggestions() {
        guard !isPinyinMode else { return }
        let fullBefore = localTextCache
        guard !fullBefore.isEmpty else {
            showPlaceholderSuggestions()
            return
        }

        let before = String(fullBefore.suffix(100))

        let components = before.components(separatedBy: CharacterSet.whitespacesAndNewlines)
        if let lastWord = components.last, !lastWord.isEmpty, lastWord.count < 3,
           !before.hasSuffix(" "), !before.hasSuffix("\n") {
            let predictions = NextWordPredictor.shared.predict(after: before)
            if !predictions.isEmpty {
                let results = predictions.prefix(3).map { WordSuggestion(word: $0, isAutocorrect: false) }
                suggestionBar.update(suggestions: Array(results))
            }
            return
        }

        suggestionWorkItem?.cancel()

        let work = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            var results: [WordSuggestion] = []

            // Compute predictions once, reuse across fallback paths
            let userPredictions = UserBigramPredictor.shared.predict(after: before)
            let staticPredictions = NextWordPredictor.shared.predict(after: before)
            var seen = Set<String>()
            var merged: [String] = []
            for p in userPredictions + staticPredictions {
                if !seen.contains(p) {
                    merged.append(p)
                    seen.insert(p)
                }
            }
            let predictions = Array(merged.prefix(3))

            if before.hasSuffix(" ") || before.hasSuffix("\n") {
                if !predictions.isEmpty {
                    results = predictions.map { WordSuggestion(word: $0, isAutocorrect: false) }
                }
            }

            if results.isEmpty {
                let lang = WordSuggestionEngine.shared.detectTypingLanguage(before)
                results = WordSuggestionEngine.shared.suggestions(beforeCursor: before, language: lang)
            }

            if results.isEmpty {
                results = predictions.map { WordSuggestion(word: $0, isAutocorrect: false) }
            }

            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                if !results.isEmpty {
                    self.suggestionBar.update(suggestions: results)
                } else {
                    self.showPlaceholderSuggestions()
                }
            }
        }

        suggestionWorkItem = work
        DispatchQueue.global(qos: .userInitiated).async(execute: work)
    }

    // MARK: - Pinyin State
    private var isPinyinMode = false
    private var pinyinBuffer = ""

    // MARK: - Keyboard Background
    private var keyboardBgColor: UIColor {
        traitCollection.userInterfaceStyle == .dark
            ? UIColor(white: 0.12, alpha: 1)
            : UIColor(red: 0.82, green: 0.827, blue: 0.851, alpha: 1)
    }

    private func acceptSuggestion(_ word: String) {
        // Reopen smart reply popup
        if word == "\u{1F4AC} Replies" {
            if !smartReplies.isEmpty {
                showSmartReplyPopup()
            } else if isClipboardTranslation && !currentTranslatedText.isEmpty {
                generateSmartReplies(translatedMessage: currentTranslatedText, targetLang: resolveTargetLanguage())
            }
            return
        }

        // Smart reply — already in target language, clear field and insert
        if smartReplies.contains(where: { $0.targetText == word }) {
            let before = textDocumentProxy.documentContextBeforeInput ?? ""
            for _ in 0..<before.count {
                textDocumentProxy.deleteBackward()
            }
            textDocumentProxy.insertText(word)
            smartReplies.removeAll()
            translationBar.showTranslation(original: word, translation: word)
            translationBar.isClipboardMode = false
            notificationHaptic.notificationOccurred(.success)
            isClipboardTranslation = false
            scheduleIdleReset()
            showPlaceholderSuggestions()
            return
        }

        // Pinyin mode: insert Chinese candidate and clear buffer
        if isPinyinMode && !pinyinBuffer.isEmpty {
            pinyinBuffer = ""
            textDocumentProxy.insertText(word)

            // Predict next character based on the last character inserted
            let lastChar = String(word.suffix(1))
            let nextPredictions = PinyinEngine.shared.predictNextCharacter(after: lastChar)
            if !nextPredictions.isEmpty {
                suggestionBar.updatePinyin(candidates: nextPredictions)
            } else {
                suggestionBar.clear()
            }
            return
        }

        // Pinyin mode with empty buffer: user tapped a next-char prediction
        if isPinyinMode {
            textDocumentProxy.insertText(word)
            let lastChar = String(word.suffix(1))
            let nextPredictions = PinyinEngine.shared.predictNextCharacter(after: lastChar)
            if !nextPredictions.isEmpty {
                suggestionBar.updatePinyin(candidates: nextPredictions)
            } else {
                suggestionBar.clear()
            }
            return
        }

        let before = String(localTextCache.suffix(50))
        let components = before.components(separatedBy: CharacterSet.whitespacesAndNewlines)
        if let partial = components.last {
            for _ in 0..<partial.count {
                textDocumentProxy.deleteBackward()
            }
        }
        textDocumentProxy.insertText(word + " ")
        UserWordFrequency.shared.recordWord(word)

        scheduleSuggestionUpdate()
    }

    // MARK: - Current Message Extraction

    /// Extract the most recently completed word from a text buffer
    private func extractLastWord(from text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let components = trimmed.components(separatedBy: CharacterSet.whitespacesAndNewlines)
        guard let last = components.last, !last.isEmpty else { return nil }
        return last
    }

    /// Returns only the current line/message (text after last newline before cursor)
    private func getCurrentMessage() -> String {
        let before = localTextCache
        if let lastNewlineRange = before.range(of: "\n", options: .backwards) {
            return String(before[lastNewlineRange.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return before.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Deletes only the current message (N characters before cursor), not the entire field
    private func deleteCurrentMessage(length: Int) {
        // Cancel suggestions during bulk deletion
        suggestionTimer?.cancel()
        suggestionWorkItem?.cancel()

        for _ in 0..<length {
            textDocumentProxy.deleteBackward()
        }
        // Sync cache after bulk deletion
        localTextCache = String((textDocumentProxy.documentContextBeforeInput ?? "").suffix(200))
    }

    // MARK: - Translate Button (One-Tap: translate + replace current message only)

    private func translateButtonTapped() {
        // If in review mode, open preview card
        if translationBar.isReviewMode {
            idleResetTimer?.cancel()
            if isClipboardTranslation {
                showIncomingPreviewCard()
            } else {
                showPreviewCard()
            }
            return
        }

        let currentMessage = getCurrentMessage()
        guard !currentMessage.isEmpty else { return }

        // Record the sentence the user just composed
        UserBigramPredictor.shared.recordSentence(currentMessage)

        // Clear clipboard and tone state for new translation
        isClipboardTranslation = false
        toneCache.removeAll()

        // Cancel any pending idle reset
        idleResetTimer?.cancel()

        // SMART SWITCH: detect typed language and auto-flip if same as target
        var targetLang = resolveTargetLanguage()
        let detectedCode = LanguageDetector.shared.detectLanguage(currentMessage)
        let detectedLang = detectedCode.flatMap {
            SupportedLanguage(rawValue: $0.components(separatedBy: "-").first ?? $0)
        }
        if let detected = detectedLang, detected == targetLang {
            let userNative = SharedSettings.shared.selectedLanguage
            if detected == userNative {
                targetLang = detected == .english ? .chinese : .english
            } else {
                targetLang = userNative
            }
            currentTargetLanguage = targetLang
            translationBar.updateTargetLanguage(targetLang.rawValue)
        }

        // Check cache first — instant replace
        let cacheKey = "\(currentMessage)|\(targetLang.rawValue)"
        if let cached = translationCache[cacheKey] {
            lastTranslationSource = .cache
            currentOriginalText = currentMessage
            currentTranslatedText = cached
            deleteCurrentMessage(length: currentMessage.count)
            textDocumentProxy.insertText(cached)
            translationBar.showTranslation(original: currentMessage, translation: cached)
            translationBar.showSpeed(sourceLabel(.cache))
            self.notificationHaptic.notificationOccurred(.success)
            scheduleIdleReset()
            return
        }

        translationBar.showOriginal(currentMessage)
        translationBar.showTranslating()

        let startTime = CFAbsoluteTimeGetCurrent()
        let messageLength = currentMessage.count

        translationTask?.cancel()
        translationTask = Task { [weak self] in
            guard let self = self else { return }
            let translated = await self.translateText(currentMessage)

            guard !Task.isCancelled else { return }

            await MainActor.run {
                if let translated = translated {
                    let elapsed = CFAbsoluteTimeGetCurrent() - startTime
                    let speed = elapsed < 0.1 ? "" : String(format: " %.1fs", elapsed)
                    let label = self.sourceLabel(self.lastTranslationSource) + speed

                    // Store for preview card access
                    self.currentOriginalText = currentMessage
                    self.currentTranslatedText = translated

                    // Show what happened in the translation bar
                    self.translationBar.showTranslation(original: currentMessage, translation: translated)
                    self.translationBar.showSpeed(label)

                    // Replace only the current message
                    self.deleteCurrentMessage(length: messageLength)
                    self.textDocumentProxy.insertText(translated)

                    // Cache result
                    self.translationCache[cacheKey] = translated
                    if self.translationCache.count > self.maxCacheSize {
                        self.translationCache.removeAll()
                    }

                    // Haptic feedback
                    self.notificationHaptic.notificationOccurred(.success)

                    // Reset to idle after 5 seconds
                    self.scheduleIdleReset()
                } else {
                    self.translationBar.showError("Translation failed \u{2014} tap to retry")
                }
            }
        }
    }

    private func scheduleIdleReset() {
        idleResetTimer?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.translationBar.showIdle()
        }
        idleResetTimer = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.0, execute: work)
    }

    // MARK: - Long-Press: Translate + Show Preview Card

    private func translateAndShowPreview() {
        let currentMessage = getCurrentMessage()
        guard !currentMessage.isEmpty else { return }

        haptic.impactOccurred()
        translationBar.showOriginal(currentMessage)
        translationBar.showTranslating()

        translationTask?.cancel()
        translationTask = Task { [weak self] in
            guard let self = self else { return }

            // Check cache
            let targetLang = self.resolveTargetLanguage()
            let cacheKey = "\(currentMessage)|\(targetLang.rawValue)"
            if let cached = self.translationCache[cacheKey] {
                await MainActor.run {
                    self.translationBar.showTranslation(original: currentMessage, translation: cached)
                    self.currentOriginalText = currentMessage
                    self.currentTranslatedText = cached
                    self.showPreviewCard()
                }
                return
            }

            let translated = await self.translateText(currentMessage)

            guard !Task.isCancelled else { return }

            await MainActor.run {
                if let translated = translated {
                    self.translationBar.showTranslation(original: currentMessage, translation: translated)
                    self.translationCache[cacheKey] = translated
                    if self.translationCache.count > self.maxCacheSize {
                        self.translationCache.removeAll()
                    }
                    self.currentOriginalText = currentMessage
                    self.currentTranslatedText = translated
                    self.showPreviewCard()
                } else {
                    self.translationBar.showError("Translation failed")
                }
            }
        }
    }

    private func translateText(_ text: String) async -> String? {
        let targetLang = resolveTargetLanguage()

        // Detect what language the text is actually written in
        let detectedCode = LanguageDetector.shared.detectLanguage(text)
        let detectedPrefix = detectedCode?.components(separatedBy: "-").first ?? detectedCode

        // Don't translate if text is already in the target language
        if let dp = detectedPrefix, dp == targetLang.rawValue {
            return nil
        }

        // Determine source language name from detection, fall back to user's native language
        let fromName: String
        let fromCode: String
        if let dp = detectedPrefix, let detected = SupportedLanguage(rawValue: dp) {
            fromName = detected.fullLanguageName
            fromCode = detected.rawValue
        } else {
            let userLang = SharedSettings.shared.selectedLanguage
            fromName = userLang.fullLanguageName
            fromCode = userLang.rawValue
        }

        // TIER 0: Offline common phrases (instant, free)
        if let offline = OfflineTranslator.shared.translate(
            text: text,
            from: fromName,
            to: targetLang.fullLanguageName
        ) {
            lastTranslationSource = .offline
            return offline
        }

        // TIER 1: Apple on-device translation (free, instant if language downloaded)
        if #available(iOS 26.0, *) {
            do {
                let sourceLang = Locale.Language(identifier: fromCode)
                let targetLocale = Locale.Language(identifier: targetLang.rawValue)
                let session = TranslationSession(installedSource: sourceLang, target: targetLocale)
                let response = try await session.translate(text)
                lastTranslationSource = .apple
                return response.targetText
            } catch {
                // Language not installed or not supported — fall through to AI
            }
        }

        // TIER 2: AI API (costs tokens)
        do {
            guard let service = AIServiceFactory.createCurrentService() else { return nil }

            let result = try await service.translate(
                text: text,
                from: fromName,
                to: targetLang.fullLanguageName,
                context: SharedSettings.shared.industryContext,
                tone: nil,
                generateReply: false
            )

            UsageTracker.shared.recordCall(
                provider: SharedSettings.shared.selectedProvider.rawValue,
                inputText: text,
                outputText: result.translation
            )

            lastTranslationSource = .ai
            return result.translation
        } catch {
            return nil
        }
    }

    private func sourceLabel(_ source: TranslationSource) -> String {
        switch source {
        case .cache: return "\u{26A1} cached"
        case .offline: return "\u{26A1} instant"
        case .apple: return "\u{26A1} Apple"
        case .ai: return "AI"
        }
    }

    // MARK: - Clipboard Detection

    private var isClipboardTranslation = false
    private var lastClipboardContent = ""
    private var smartReplies: [(targetText: String, userText: String)] = []
    private var smartReplyPopup: SmartReplyPopupUIView?

    private func checkClipboard() {
        // Read clipboard — returns nil without Full Access
        guard let clipboardText = UIPasteboard.general.string else {
            #if DEBUG
            print("[Clipboard] No clipboard text (Full Access needed?)")
            #endif
            return
        }
        let trimmed = clipboardText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count >= 2 else { return }

        // Don't re-process the same content
        guard trimmed != lastClipboardContent else {
            #if DEBUG
            print("[Clipboard] Same content, skipping")
            #endif
            return
        }

        // Detect language
        let detectedCode = LanguageDetector.shared.detectLanguage(trimmed)
        let langCode = detectedCode?.components(separatedBy: "-").first ?? ""
        let userLangCode = SharedSettings.shared.selectedLanguage.rawValue
        #if DEBUG
        print("[Clipboard] detected=\(langCode) user=\(userLangCode) text=\(trimmed.prefix(30))")
        #endif

        // Only translate if it's a DIFFERENT language than user's native
        guard !langCode.isEmpty, langCode != userLangCode else {
            #if DEBUG
            print("[Clipboard] Same language or undetected, skipping")
            #endif
            return
        }

        lastClipboardContent = trimmed
        #if DEBUG
        print("[Clipboard] Starting translation...")
        #endif

        // Set target language to the sender's language (so replies go back in their language)
        if let detectedLang = SupportedLanguage(rawValue: langCode) {
            currentTargetLanguage = detectedLang
            translationBar.updateTargetLanguage(detectedLang.rawValue)
        }

        let displayOriginal = trimmed.count > 40 ? String(trimmed.prefix(40)) + "..." : trimmed

        // Check cache
        if let cached = ClipboardMonitor.shared.lastTranslation,
           ClipboardMonitor.shared.lastProcessedString == trimmed {
            currentOriginalText = trimmed
            currentTranslatedText = cached
            isClipboardTranslation = true
            translationBar.showClipboardTranslation(original: trimmed, translation: cached)
            generateSmartReplies(translatedMessage: cached, targetLang: resolveTargetLanguage())
            return
        }

        // Show loading state
        translationBar.showClipboardLoading(original: trimmed)

        // Translate to user's language
        Task { [weak self] in
            guard let self = self else { return }
            let translated = await self.translateClipboardText(trimmed)

            await MainActor.run {
                if let result = translated {
                    ClipboardMonitor.shared.cacheResult(original: trimmed, translation: result, suggestedReply: nil)
                    self.currentOriginalText = trimmed
                    self.currentTranslatedText = result
                    self.isClipboardTranslation = true
                    self.translationBar.showClipboardTranslation(original: trimmed, translation: result)
                    self.generateSmartReplies(translatedMessage: result, targetLang: self.resolveTargetLanguage())
                } else {
                    self.translationBar.showError("Could not translate clipboard")
                }
            }
        }
    }

    private func translateClipboardText(_ text: String) async -> String? {
        let userLangName = SharedSettings.shared.selectedLanguage.fullLanguageName
        let detectedCode = LanguageDetector.shared.detectLanguage(text) ?? "zh"
        let fromLangCode = detectedCode.components(separatedBy: "-").first ?? detectedCode
        let fromName: String
        if let lang = SupportedLanguage(rawValue: fromLangCode) {
            fromName = lang.fullLanguageName
        } else {
            fromName = fromLangCode
        }

        // Try AI translation
        guard let service = AIServiceFactory.createCurrentService() else { return nil }
        do {
            let result = try await service.translate(
                text: text,
                from: fromName,
                to: userLangName,
                context: SharedSettings.shared.industryContext,
                tone: nil,
                generateReply: false
            )
            return result.translation
        } catch {
            return nil
        }
    }

    private func generateSmartReplies(translatedMessage: String, targetLang: SupportedLanguage) {
        #if DEBUG
        print("[SmartReplies] Generating for: \(translatedMessage.prefix(40)) → \(targetLang.rawValue)")
        #endif
        guard let service = AIServiceFactory.createCurrentService() else {
            #if DEBUG
            print("[SmartReplies] No AI service available")
            #endif
            return
        }

        let settings = SharedSettings.shared
        let userLangName = settings.selectedLanguage.fullLanguageName
        let targetLangName = targetLang.fullLanguageName

        suggestionBar.update(suggestions: [
            WordSuggestion(word: "Generating replies...", isAutocorrect: false),
        ])

        let prompt = """
        Someone sent me: "\(translatedMessage)"

        Give me 3 short replies. For each, give the \(targetLangName) version AND the \(userLangName) translation.
        Rules: each reply 2-10 words, sound natural like texting, do NOT repeat what they said.
        Reply 1: positive/enthusiastic. Reply 2: follow-up question. Reply 3: casual acknowledgment.

        Format EXACTLY like this (use | separator):
        \(targetLangName) text | \(userLangName) text

        Respond with ONLY 3 lines in this format. Nothing else.
        """

        Task { [weak self] in
            guard let self = self else { return }
            do {
                let rawResponse = try await service.sendRawPrompt(prompt)

                var parsed: [(targetText: String, userText: String)] = []
                let lines = rawResponse
                    .components(separatedBy: .newlines)
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }

                for line in lines {
                    let parts = line.components(separatedBy: "|")
                    if parts.count >= 2 {
                        let target = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
                            .replacingOccurrences(of: "\"", with: "")
                        let user = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
                            .replacingOccurrences(of: "\"", with: "")
                        if !target.isEmpty && !user.isEmpty {
                            parsed.append((targetText: target, userText: user))
                        }
                    }
                }

                await MainActor.run {
                    #if DEBUG
                    print("[SmartReplies] Parsed \(parsed.count) replies")
                    #endif
                    if parsed.count >= 2 {
                        self.smartReplies = Array(parsed.prefix(3))
                        for r in self.smartReplies {
                            #if DEBUG
                            print("[SmartReplies]   \(r.targetText) | \(r.userText)")
                            #endif
                        }
                        self.showSmartReplyPopup()
                    } else {
                        #if DEBUG
                        print("[SmartReplies] Not enough replies, raw: \(rawResponse.prefix(100))")
                        #endif
                        self.showPlaceholderSuggestions()
                    }
                }
            } catch {
                #if DEBUG
                print("[SmartReplies] Error: \(error)")
                #endif
                await MainActor.run { self.showPlaceholderSuggestions() }
            }
        }
    }

    // MARK: - Target Language

    private func resolveTargetLanguage() -> SupportedLanguage {
        if let target = currentTargetLanguage { return target }
        let userLang = SharedSettings.shared.selectedLanguage
        let target: SupportedLanguage = (userLang == .english) ? .chinese : .english
        currentTargetLanguage = target
        return target
    }

    private func cycleTargetLanguage() {
        let languages: [SupportedLanguage] = [
            .chinese, .english, .spanish, .japanese, .korean, .arabic, .french, .german
        ]
        let current = resolveTargetLanguage()
        let userLang = SharedSettings.shared.selectedLanguage

        if let idx = languages.firstIndex(of: current) {
            var nextIdx = (idx + 1) % languages.count
            if languages[nextIdx] == userLang {
                nextIdx = (nextIdx + 1) % languages.count
            }
            currentTargetLanguage = languages[nextIdx]
        } else {
            currentTargetLanguage = .chinese
        }
        translationBar.updateTargetLanguage(currentTargetLanguage!.rawValue)
        translationBar.showIdle()
        idleResetTimer?.cancel()
    }

    // MARK: - Preview Card

    private func showPreviewCard() {
        guard previewCard == nil else { return }
        #if DEBUG
        print("DEBUG Preview: original='\(currentOriginalText)' translated='\(currentTranslatedText)'")
        #endif
        guard !currentTranslatedText.isEmpty else { return }

        let card = TranslationPreviewCardUIView()
        card.originalText = currentOriginalText
        card.translatedText = currentTranslatedText

        card.onClose = { [weak self] in self?.dismissPreviewCard() }
        card.onEdit = { [weak self] in self?.editTranslation() }
        card.onBookmark = { [weak self] in self?.bookmarkTranslation() }
        card.onSend = { [weak self] in self?.confirmSendTranslation() }
        card.onToneSelected = { [weak self] tone in self?.retranslateWithTone(tone) }

        let topOffset: CGFloat = 50
        let cardH = view.bounds.height - topOffset
        card.frame = CGRect(x: 0, y: view.bounds.height, width: view.bounds.width, height: cardH)
        view.addSubview(card)

        UIView.animate(withDuration: 0.25, delay: 0, options: .curveEaseOut) {
            card.frame.origin.y = topOffset
        }

        previewCard = card

        // Fetch back-translation so user can understand what they're sending
        Task { [weak self] in
            guard let self = self else { return }
            guard let service = AIServiceFactory.createCurrentService() else { return }
            let settings = SharedSettings.shared
            let targetLang = self.resolveTargetLanguage()

            // Best-effort back-translation. Failure is acceptable: the primary
            // translation already succeeded; this is purely a verification step
            // so the user can see what their message round-trips back to. No UI
            // error needed if it fails.
            let backResult = try? await service.translate(
                text: self.currentTranslatedText,
                from: targetLang.fullLanguageName,
                to: settings.selectedLanguage.fullLanguageName,
                context: settings.industryContext,
                tone: nil,
                generateReply: false
            )

            await MainActor.run {
                self.previewCard?.updateBackTranslation(backResult?.translation ?? "")
            }
        }
    }

    private func showIncomingPreviewCard() {
        guard previewCard == nil else { return }
        guard !currentTranslatedText.isEmpty else { return }

        let card = TranslationPreviewCardUIView()
        card.originalText = currentOriginalText
        card.translatedText = currentTranslatedText
        card.configureIncomingMode()

        card.onClose = { [weak self] in self?.dismissPreviewCard() }
        card.onBookmark = { [weak self] in self?.bookmarkTranslation() }
        card.onSend = { [weak self] in
            // Copy translation to clipboard
            UIPasteboard.general.string = self?.currentTranslatedText
            self?.dismissPreviewCard()
            self?.translationBar.showMessage("Copied to clipboard")
            self?.translationBar.isClipboardMode = false
            self?.notificationHaptic.notificationOccurred(.success)
            self?.isClipboardTranslation = false
        }

        let topOffset: CGFloat = 50
        let cardH = view.bounds.height - topOffset
        card.frame = CGRect(x: 0, y: view.bounds.height, width: view.bounds.width, height: cardH)
        view.addSubview(card)

        UIView.animate(withDuration: 0.25, delay: 0, options: .curveEaseOut) {
            card.frame.origin.y = topOffset
        }

        previewCard = card
    }

    // MARK: - AI Reply Generation

    private func generateReply() {
        guard !currentOriginalText.isEmpty else { return }
        guard let service = AIServiceFactory.createCurrentService() else {
            translationBar.showError("Set up API key first")
            return
        }

        translationBar.showMessage("\u{1F4AC} Thinking...")

        let targetLang = resolveTargetLanguage()

        let prompt = """
        Someone sent: "\(currentTranslatedText)"

        Write a single natural reply in \(targetLang.fullLanguageName). Rules:
        - 1-2 sentences max
        - Sound like a real person, not AI
        - Be friendly and engaging
        - Do NOT repeat what they said
        - Do NOT ask the same question back

        Respond with ONLY the reply text.
        """

        Task { [weak self] in
            guard let self = self else { return }
            do {
                let reply = try await service.sendRawPrompt(prompt)

                await MainActor.run {
                    let cleaned = reply.trimmingCharacters(in: .whitespacesAndNewlines)
                    self.textDocumentProxy.insertText(cleaned)
                    self.translationBar.showTranslation(original: cleaned, translation: cleaned)
                    self.translationBar.isClipboardMode = false
                    self.currentTranslatedText = cleaned
                    self.notificationHaptic.notificationOccurred(.success)
                    self.isClipboardTranslation = false
                    self.scheduleIdleReset()
                    self.showPlaceholderSuggestions()
                }
            } catch {
                await MainActor.run {
                    self.translationBar.showError("Reply failed \u{2014} type manually")
                    self.showPlaceholderSuggestions()
                }
            }
        }
    }

    private func dismissPreviewCard() {
        guard let card = previewCard else { return }
        UIView.animate(withDuration: 0.2, delay: 0, options: .curveEaseIn, animations: {
            card.frame.origin.y = self.view.bounds.height
        }, completion: { _ in
            card.removeFromSuperview()
        })
        previewCard = nil
    }

    private func editTranslation() {
        dismissPreviewCard()

        // Replace current message with translation for editing
        let msg = getCurrentMessage()
        deleteCurrentMessage(length: msg.count)
        textDocumentProxy.insertText(currentTranslatedText)

        isEditingTranslation = true
        showEditingBanner()

        translationBar.showIdle()
    }

    private func showEditingBanner() {
        editingBanner?.removeFromSuperview()

        let banner = UIView()
        banner.backgroundColor = UIColor.systemBlue.withAlphaComponent(0.12)
        banner.frame = CGRect(x: 0, y: 0, width: view.bounds.width, height: 32)

        let icon = UIImageView(image: UIImage(systemName: "pencil.circle.fill"))
        icon.tintColor = .systemBlue
        icon.frame = CGRect(x: 12, y: 6, width: 20, height: 20)
        banner.addSubview(icon)

        let label = UILabel()
        label.text = "Editing translation \u{2014} tap \u{2713} when done"
        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.textColor = .systemBlue
        label.frame = CGRect(x: 40, y: 6, width: view.bounds.width - 120, height: 20)
        banner.addSubview(label)

        let doneBtn = UIButton(type: .custom)
        doneBtn.setImage(UIImage(systemName: "checkmark.circle.fill"), for: .normal)
        doneBtn.tintColor = .systemGreen
        doneBtn.frame = CGRect(x: view.bounds.width - 44, y: 2, width: 28, height: 28)
        doneBtn.addTarget(self, action: #selector(editingDoneTapped), for: .touchUpInside)
        banner.addSubview(doneBtn)

        let cancelBtn = UIButton(type: .custom)
        cancelBtn.setImage(UIImage(systemName: "xmark.circle.fill"), for: .normal)
        cancelBtn.tintColor = .secondaryLabel
        cancelBtn.frame = CGRect(x: view.bounds.width - 76, y: 2, width: 28, height: 28)
        cancelBtn.addTarget(self, action: #selector(editingCancelTapped), for: .touchUpInside)
        banner.addSubview(cancelBtn)

        view.addSubview(banner)
        editingBanner = banner
    }

    @objc private func editingDoneTapped() {
        isEditingTranslation = false
        editingBanner?.removeFromSuperview()
        editingBanner = nil
        self.notificationHaptic.notificationOccurred(.success)
    }

    @objc private func editingCancelTapped() {
        isEditingTranslation = false
        editingBanner?.removeFromSuperview()
        editingBanner = nil
        // Replace current (edited) text with original
        let msg = getCurrentMessage()
        deleteCurrentMessage(length: msg.count)
        textDocumentProxy.insertText(currentOriginalText)
    }

    private func bookmarkTranslation() {
        SharedSettings.shared.addSavedPhrase(original: currentOriginalText, translation: currentTranslatedText)
        previewCard?.showBookmarkConfirmed()
        self.notificationHaptic.notificationOccurred(.success)
    }

    private func confirmSendTranslation() {
        dismissPreviewCard()

        // Replace current message with translation
        let msg = getCurrentMessage()
        deleteCurrentMessage(length: msg.count)
        textDocumentProxy.insertText(currentTranslatedText)
        translationBar.showIdle()

        self.notificationHaptic.notificationOccurred(.success)
    }

    private func retranslateWithTone(_ tone: String) {
        // Check cache first — instant switch
        if let cached = toneCache[tone] {
            currentTranslatedText = cached.translation
            previewCard?.updateTranslation(cached.translation)
            previewCard?.updateBackTranslation(cached.backTranslation)
            return
        }

        previewCard?.showRetranslating()

        Task { [weak self] in
            guard let self = self else { return }
            do {
                let settings = SharedSettings.shared
                let targetLang = self.resolveTargetLanguage()
                guard let service = AIServiceFactory.createCurrentService() else {
                    await MainActor.run { self.previewCard?.showRetranslateError() }
                    return
                }

                // Call 1: Translate with tone
                let result = try await service.translate(
                    text: self.currentOriginalText,
                    from: settings.selectedLanguage.fullLanguageName,
                    to: targetLang.fullLanguageName,
                    context: settings.industryContext,
                    tone: tone,
                    generateReply: false
                )

                await MainActor.run {
                    self.currentTranslatedText = result.translation
                    self.previewCard?.updateTranslation(result.translation)
                    if let note = result.contextNote, !note.isEmpty {
                        self.previewCard?.updateContextNote(note)
                    }
                }

                // Call 2: Back-translate so user can understand the feeling.
                // Best-effort — failure here doesn't surface as a UI error; the
                // primary translation already succeeded and the back-translation
                // is purely informational.
                let backResult = try? await service.translate(
                    text: result.translation,
                    from: targetLang.fullLanguageName,
                    to: settings.selectedLanguage.fullLanguageName,
                    context: settings.industryContext,
                    tone: nil,
                    generateReply: false
                )

                let backText = backResult?.translation ?? ""
                await MainActor.run {
                    self.previewCard?.updateBackTranslation(backText)
                    // Cache both translation and back-translation
                    self.toneCache[tone] = (translation: result.translation, backTranslation: backText)
                }
            } catch {
                await MainActor.run {
                    self.previewCard?.showRetranslateError()
                }
            }
        }
    }

    // MARK: - Text Field Helpers

    // MARK: - Language Picker Overlay

    private func showLanguagePicker() {
        guard languagePickerOverlay == nil else { return }
        haptic.impactOccurred()

        let userLang = SharedSettings.shared.selectedLanguage

        let overlay = UIView(frame: view.bounds)
        overlay.backgroundColor = UIColor.black.withAlphaComponent(0.4)
        overlay.alpha = 0

        let dismissTap = UITapGestureRecognizer(target: self, action: #selector(dismissLanguagePicker))
        overlay.addGestureRecognizer(dismissTap)

        let pickerW: CGFloat = min(260, view.bounds.width - 40)
        let rowH: CGFloat = 40
        let allLanguages: [SupportedLanguage] = [.english] + SupportedLanguage.allCases.filter { $0 != .english }
        let pickerH: CGFloat = min(CGFloat(allLanguages.count) * rowH, 280)

        let container = UIView()
        container.backgroundColor = traitCollection.userInterfaceStyle == .dark
            ? UIColor(white: 0.2, alpha: 1)
            : .systemBackground
        container.layer.cornerRadius = 12
        container.layer.borderWidth = 0.5
        container.layer.borderColor = UIColor.separator.cgColor
        container.clipsToBounds = true

        let pickerX = (view.bounds.width - pickerW) / 2
        let pickerY: CGFloat = 8
        container.frame = CGRect(x: pickerX, y: pickerY, width: pickerW, height: pickerH)

        let scrollView = UIScrollView(frame: container.bounds)
        scrollView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        scrollView.showsVerticalScrollIndicator = true

        let contentH = CGFloat(allLanguages.count) * rowH
        scrollView.contentSize = CGSize(width: pickerW, height: contentH)

        let current = resolveTargetLanguage()

        for (i, lang) in allLanguages.enumerated() {
            let rowView = UIButton(type: .custom)
            rowView.frame = CGRect(x: 0, y: CGFloat(i) * rowH, width: pickerW, height: rowH)
            rowView.tag = i

            let label = UILabel()
            label.text = lang.displayName
            label.font = .systemFont(ofSize: 15, weight: lang == current ? .semibold : .regular)
            label.textColor = lang == current ? .systemBlue : .label
            label.translatesAutoresizingMaskIntoConstraints = false
            rowView.addSubview(label)

            NSLayoutConstraint.activate([
                label.leadingAnchor.constraint(equalTo: rowView.leadingAnchor, constant: 16),
                label.centerYAnchor.constraint(equalTo: rowView.centerYAnchor),
            ])

            if lang == current {
                let check = UIImageView(image: UIImage(systemName: "checkmark"))
                check.tintColor = .systemBlue
                check.translatesAutoresizingMaskIntoConstraints = false
                rowView.addSubview(check)
                NSLayoutConstraint.activate([
                    check.trailingAnchor.constraint(equalTo: rowView.trailingAnchor, constant: -16),
                    check.centerYAnchor.constraint(equalTo: rowView.centerYAnchor),
                ])
            }

            if i < allLanguages.count - 1 {
                let sep = UIView()
                sep.backgroundColor = .separator
                sep.frame = CGRect(x: 16, y: rowH - 0.5, width: pickerW - 32, height: 0.5)
                rowView.addSubview(sep)
            }

            rowView.addTarget(self, action: #selector(languageSelected(_:)), for: .touchUpInside)
            scrollView.addSubview(rowView)
        }

        container.addSubview(scrollView)
        overlay.addSubview(container)
        view.addSubview(overlay)
        languagePickerOverlay = overlay

        container.transform = CGAffineTransform(scaleX: 0.8, y: 0.8)
        UIView.animate(withDuration: 0.2, delay: 0, options: .curveEaseOut) {
            overlay.alpha = 1
            container.transform = .identity
        }
    }

    @objc private func languageSelected(_ sender: UIButton) {
        let allLanguages: [SupportedLanguage] = [.english] + SupportedLanguage.allCases.filter { $0 != .english }
        let idx = sender.tag
        guard idx >= 0, idx < allLanguages.count else { return }

        let selected = allLanguages[idx]
        currentTargetLanguage = selected
        translationBar.updateTargetLanguage(selected.rawValue)
        translationBar.showIdle()
        idleResetTimer?.cancel()

        dismissLanguagePicker()
    }

    @objc private func dismissLanguagePicker() {
        guard let overlay = languagePickerOverlay else { return }
        UIView.animate(withDuration: 0.15, delay: 0, options: .curveEaseIn, animations: {
            overlay.alpha = 0
        }, completion: { _ in
            overlay.removeFromSuperview()
        })
        languagePickerOverlay = nil
    }

    // MARK: - Pinyin Input

    private func handlePinyinKeyTap(_ letter: String) {
        pinyinBuffer += letter
        updatePinyinCandidates()
    }

    private func handlePinyinBackspace() {
        pinyinBuffer = String(pinyinBuffer.dropLast())
        if pinyinBuffer.isEmpty {
            suggestionBar.clear()
        } else {
            updatePinyinCandidates()
        }
    }

    private func handlePinyinSpace() {
        // Select first candidate
        let candidates = PinyinEngine.shared.candidates(for: pinyinBuffer)
        if let first = candidates.first {
            pinyinBuffer = ""
            textDocumentProxy.insertText(first)

            // Predict next character
            let lastChar = String(first.suffix(1))
            let nextPredictions = PinyinEngine.shared.predictNextCharacter(after: lastChar)
            if !nextPredictions.isEmpty {
                suggestionBar.updatePinyin(candidates: nextPredictions)
            } else {
                suggestionBar.clear()
            }
        } else {
            // No candidates — commit buffer as raw text
            let raw = pinyinBuffer
            pinyinBuffer = ""
            textDocumentProxy.insertText(raw)
            suggestionBar.clear()
        }
    }

    private func updatePinyinCandidates() {
        let buffer = pinyinBuffer
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let candidates = PinyinEngine.shared.candidates(for: buffer)
            DispatchQueue.main.async { [weak self] in
                guard let self = self, self.pinyinBuffer == buffer else { return }
                if candidates.isEmpty {
                    self.suggestionBar.updatePinyin(candidates: [buffer])
                } else {
                    self.suggestionBar.updatePinyin(candidates: candidates)
                }
            }
        }
    }

    // MARK: - Long-Press Language Input Picker

    private func showLanguageInputPicker() {
        guard languagePickerOverlay == nil else { return }
        haptic.impactOccurred()

        let overlay = UIView(frame: view.bounds)
        overlay.backgroundColor = UIColor.black.withAlphaComponent(0.4)
        overlay.alpha = 0

        let dismissTap = UITapGestureRecognizer(target: self, action: #selector(dismissLanguagePicker))
        overlay.addGestureRecognizer(dismissTap)

        let isDark = traitCollection.userInterfaceStyle == .dark
        let pickerW: CGFloat = min(280, view.bounds.width - 32)
        let rowH: CGFloat = 40
        let headerH: CGFloat = 30

        // "Type in:" section: English, Pinyin
        let inputOptions: [(String, Bool)] = [
            ("English", !isPinyinMode),
            ("Pinyin (中文)", isPinyinMode)
        ]

        // "Translate to:" section: all languages (English first, then rest)
        let userLang = SharedSettings.shared.selectedLanguage
        let allLanguages: [SupportedLanguage] = [.english] + SupportedLanguage.allCases.filter { $0 != .english }
        let currentTarget = resolveTargetLanguage()

        let inputSectionH = headerH + CGFloat(inputOptions.count) * rowH
        let translateSectionH = headerH + CGFloat(allLanguages.count) * rowH
        let totalContentH = inputSectionH + translateSectionH
        let pickerH = min(totalContentH, view.bounds.height - 20)

        let container = UIView()
        container.backgroundColor = isDark ? UIColor(white: 0.2, alpha: 1) : .systemBackground
        container.layer.cornerRadius = 12
        container.layer.borderWidth = 0.5
        container.layer.borderColor = UIColor.separator.cgColor
        container.clipsToBounds = true

        let pickerX = (view.bounds.width - pickerW) / 2
        let pickerY: CGFloat = 8
        container.frame = CGRect(x: pickerX, y: pickerY, width: pickerW, height: pickerH)

        let scrollView = UIScrollView(frame: container.bounds)
        scrollView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        scrollView.showsVerticalScrollIndicator = true
        scrollView.contentSize = CGSize(width: pickerW, height: totalContentH)

        var y: CGFloat = 0

        // --- "TYPE IN:" header ---
        let typeHeader = UILabel(frame: CGRect(x: 16, y: y + 8, width: pickerW - 32, height: 16))
        typeHeader.text = "TYPE IN:"
        typeHeader.font = .systemFont(ofSize: 11, weight: .semibold)
        typeHeader.textColor = .secondaryLabel
        scrollView.addSubview(typeHeader)
        y += headerH

        // Input language rows
        for (i, option) in inputOptions.enumerated() {
            let rowBtn = UIButton(type: .custom)
            rowBtn.frame = CGRect(x: 0, y: y, width: pickerW, height: rowH)
            rowBtn.tag = i // 0 = English, 1 = Pinyin

            let label = UILabel()
            label.text = option.0
            label.font = .systemFont(ofSize: 15, weight: option.1 ? .semibold : .regular)
            label.textColor = option.1 ? .systemBlue : .label
            label.translatesAutoresizingMaskIntoConstraints = false
            rowBtn.addSubview(label)
            NSLayoutConstraint.activate([
                label.leadingAnchor.constraint(equalTo: rowBtn.leadingAnchor, constant: 16),
                label.centerYAnchor.constraint(equalTo: rowBtn.centerYAnchor),
            ])

            if option.1 {
                let check = UIImageView(image: UIImage(systemName: "checkmark"))
                check.tintColor = .systemBlue
                check.translatesAutoresizingMaskIntoConstraints = false
                rowBtn.addSubview(check)
                NSLayoutConstraint.activate([
                    check.trailingAnchor.constraint(equalTo: rowBtn.trailingAnchor, constant: -16),
                    check.centerYAnchor.constraint(equalTo: rowBtn.centerYAnchor),
                ])
            }

            let sep = UIView()
            sep.backgroundColor = .separator
            sep.frame = CGRect(x: 16, y: rowH - 0.5, width: pickerW - 32, height: 0.5)
            rowBtn.addSubview(sep)

            rowBtn.addTarget(self, action: #selector(inputLanguageSelected(_:)), for: .touchUpInside)
            scrollView.addSubview(rowBtn)
            y += rowH
        }

        // --- "TRANSLATE TO:" header ---
        let translateHeader = UILabel(frame: CGRect(x: 16, y: y + 8, width: pickerW - 32, height: 16))
        translateHeader.text = "TRANSLATE TO:"
        translateHeader.font = .systemFont(ofSize: 11, weight: .semibold)
        translateHeader.textColor = .secondaryLabel
        scrollView.addSubview(translateHeader)
        y += headerH

        // Target language rows
        for (i, lang) in allLanguages.enumerated() {
            let rowBtn = UIButton(type: .custom)
            rowBtn.frame = CGRect(x: 0, y: y, width: pickerW, height: rowH)
            rowBtn.tag = 100 + i // offset to distinguish from input language

            let label = UILabel()
            label.text = lang.displayName
            label.font = .systemFont(ofSize: 15, weight: lang == currentTarget ? .semibold : .regular)
            label.textColor = lang == currentTarget ? .systemBlue : .label
            label.translatesAutoresizingMaskIntoConstraints = false
            rowBtn.addSubview(label)
            NSLayoutConstraint.activate([
                label.leadingAnchor.constraint(equalTo: rowBtn.leadingAnchor, constant: 16),
                label.centerYAnchor.constraint(equalTo: rowBtn.centerYAnchor),
            ])

            if lang == currentTarget {
                let check = UIImageView(image: UIImage(systemName: "checkmark"))
                check.tintColor = .systemBlue
                check.translatesAutoresizingMaskIntoConstraints = false
                rowBtn.addSubview(check)
                NSLayoutConstraint.activate([
                    check.trailingAnchor.constraint(equalTo: rowBtn.trailingAnchor, constant: -16),
                    check.centerYAnchor.constraint(equalTo: rowBtn.centerYAnchor),
                ])
            }

            if i < allLanguages.count - 1 {
                let sep = UIView()
                sep.backgroundColor = .separator
                sep.frame = CGRect(x: 16, y: rowH - 0.5, width: pickerW - 32, height: 0.5)
                rowBtn.addSubview(sep)
            }

            rowBtn.addTarget(self, action: #selector(pickerLanguageSelected(_:)), for: .touchUpInside)
            scrollView.addSubview(rowBtn)
            y += rowH
        }

        container.addSubview(scrollView)
        overlay.addSubview(container)
        view.addSubview(overlay)
        languagePickerOverlay = overlay

        container.transform = CGAffineTransform(scaleX: 0.8, y: 0.8)
        UIView.animate(withDuration: 0.2, delay: 0, options: .curveEaseOut) {
            overlay.alpha = 1
            container.transform = .identity
        }
    }

    @objc private func inputLanguageSelected(_ sender: UIButton) {
        let wantPinyin = sender.tag == 1
        if wantPinyin != isPinyinMode {
            isPinyinMode = wantPinyin
            pinyinBuffer = ""
            suggestionBar.clear()
            if !isPinyinMode {
                showPlaceholderSuggestions()
            }
            touchSurface.configure(shifted: isShifted, pinyinMode: isPinyinMode, page: currentPage)
        }
        dismissLanguagePicker()
    }

    @objc private func pickerLanguageSelected(_ sender: UIButton) {
        let allLanguages: [SupportedLanguage] = [.english] + SupportedLanguage.allCases.filter { $0 != .english }
        let idx = sender.tag - 100
        guard idx >= 0, idx < allLanguages.count else { return }

        let selected = allLanguages[idx]
        currentTargetLanguage = selected
        translationBar.updateTargetLanguage(selected.rawValue)
        translationBar.showIdle()
        idleResetTimer?.cancel()

        dismissLanguagePicker()
    }

    // MARK: - Smart Reply Popup

    private func showSmartReplyPopup() {
        #if DEBUG
        print("[SmartReplyPopup] Showing popup with \(smartReplies.count) replies, bounds=\(view.bounds)")
        #endif
        smartReplyPopup?.removeFromSuperview()
        showPlaceholderSuggestions()

        let popup = SmartReplyPopupUIView()
        popup.setReplies(smartReplies)

        popup.onReplySelected = { [weak self] replyText in
            guard let self = self else { return }
            // Clear text field
            let before = self.textDocumentProxy.documentContextBeforeInput ?? ""
            for _ in 0..<before.count {
                self.textDocumentProxy.deleteBackward()
            }
            // Insert reply
            self.textDocumentProxy.insertText(replyText)
            self.notificationHaptic.notificationOccurred(.success)
            self.dismissSmartReplyPopup()
            self.translationBar.showIdle()
            self.smartReplies.removeAll()
            self.isClipboardTranslation = false
        }

        popup.onClose = { [weak self] in
            self?.dismissSmartReplyPopup()
            self?.showPlaceholderSuggestions()
        }

        let topOffset: CGFloat = 50
        let popupHeight = view.bounds.height - topOffset
        popup.frame = CGRect(x: 0, y: view.bounds.height, width: view.bounds.width, height: popupHeight)
        view.addSubview(popup)

        UIView.animate(withDuration: 0.25, delay: 0, options: .curveEaseOut) {
            popup.frame.origin.y = topOffset
        }

        smartReplyPopup = popup
    }

    private func exitClipboardMode() {
        isClipboardTranslation = false
        smartReplies.removeAll()

        if smartReplyPopup != nil {
            dismissSmartReplyPopup()
        }

        translationBar.showIdle()
        showPlaceholderSuggestions()
        idleResetTimer?.cancel()

        // Suppress immediate retrigger from the same clipboard content
        lastClipboardContent = UIPasteboard.general.string?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        haptic.impactOccurred()
    }

    private func dismissSmartReplyPopup() {
        guard let popup = smartReplyPopup else { return }
        UIView.animate(withDuration: 0.2, delay: 0, options: .curveEaseIn, animations: {
            popup.frame.origin.y = self.view.bounds.height
        }) { _ in
            popup.removeFromSuperview()
            self.smartReplyPopup = nil

            // Show "Replies" button so user can reopen
            if !self.smartReplies.isEmpty {
                self.suggestionBar.update(suggestions: [
                    WordSuggestion(word: "\u{1F4AC} Replies", isAutocorrect: false),
                ])
            } else {
                self.showPlaceholderSuggestions()
            }
        }
    }

    // MARK: - Dark Mode

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if traitCollection.userInterfaceStyle != previousTraitCollection?.userInterfaceStyle {
            touchSurface?.setNeedsDisplay()
            view.backgroundColor = keyboardBgColor
        }
    }
}

// MARK: - KeyboardTouchSurfaceDelegate

extension KeyboardViewController: KeyboardTouchSurfaceDelegate {

    // Throttled, opt-out per-keystroke haptic. Must stay on the main thread —
    // UIFeedbackGenerator is not thread-safe.
    private func fireKeyHaptic(intensity: CGFloat = 0.4) {
        guard cachedHapticEnabled else { return }

        let now = CFAbsoluteTimeGetCurrent()
        guard now - lastHapticTime > hapticThrottleMs else { return }

        keyHaptic.impactOccurred(intensity: intensity)
        keyHaptic.prepare()
        lastHapticTime = now
    }

    func keyPressed(_ key: String) {
        fireKeyHaptic()
        if smartReplyPopup != nil { dismissSmartReplyPopup() }
        if !smartReplies.isEmpty { smartReplies.removeAll() }

        if isPinyinMode && currentPage == .letters {
            handlePinyinKeyTap(key.lowercased())
            return
        }

        textDocumentProxy.insertText(key)
        appendToCache(key)

        if isShifted && currentPage == .letters {
            isShifted = false
            touchSurface.updateShift(false)
        }

        // Record sentence on terminal punctuation
        if key == "." || key == "?" || key == "!" {
            let message = getCurrentMessage()
            if !message.isEmpty {
                UserBigramPredictor.shared.recordSentence(message)
            }
        }

        if key.rangeOfCharacter(from: .letters) != nil {
            scheduleSuggestionUpdate()
        }
    }

    func backspacePressed() {
        fireKeyHaptic()
        if isPinyinMode && !pinyinBuffer.isEmpty {
            handlePinyinBackspace()
            return
        }
        textDocumentProxy.deleteBackward()
        if !localTextCache.isEmpty { localTextCache.removeLast() }
    }

    func backspaceLongPressed() {
        // Slightly stronger pulse — word delete is a more impactful action.
        fireKeyHaptic(intensity: 0.6)
        if isPinyinMode && !pinyinBuffer.isEmpty {
            pinyinBuffer = ""
            suggestionBar.clear()
            return
        }

        let text = localTextCache
        if text.isEmpty {
            textDocumentProxy.deleteBackward()
            return
        }

        var charsToDelete = 0
        var idx = text.index(before: text.endIndex)

        while idx >= text.startIndex && text[idx].isWhitespace {
            charsToDelete += 1
            if idx == text.startIndex { break }
            idx = text.index(before: idx)
        }

        if idx >= text.startIndex && !text[idx].isWhitespace {
            while idx >= text.startIndex && !text[idx].isWhitespace {
                charsToDelete += 1
                if idx == text.startIndex { break }
                idx = text.index(before: idx)
            }
        }

        if charsToDelete == 0 { charsToDelete = 1 }

        for _ in 0..<charsToDelete {
            textDocumentProxy.deleteBackward()
            if !localTextCache.isEmpty { localTextCache.removeLast() }
        }
    }

    func backspaceReleased() {}

    func spacePressed() {
        fireKeyHaptic()
        if isPinyinMode && !pinyinBuffer.isEmpty {
            handlePinyinSpace()
            return
        }
        if let lastWord = extractLastWord(from: localTextCache) {
            UserWordFrequency.shared.recordWord(lastWord)
        }
        textDocumentProxy.insertText(" ")
        appendToCache(" ")
        scheduleSuggestionUpdate()
    }

    func returnPressed() {
        fireKeyHaptic()
        if let lastWord = extractLastWord(from: localTextCache) {
            UserWordFrequency.shared.recordWord(lastWord)
        }

        // Record what was typed before pressing return
        let message = getCurrentMessage()
        if !message.isEmpty {
            UserBigramPredictor.shared.recordSentence(message)
        }

        textDocumentProxy.insertText("\n")
        appendToCache("\n")
    }

    func shiftPressed() {
        fireKeyHaptic()
        isShifted.toggle()
        touchSurface.updateShift(isShifted)
    }

    func numberTogglePressed() {
        fireKeyHaptic()
        currentPage = (currentPage == .letters) ? .numbers1 : .letters
        touchSurface.configure(shifted: isShifted, pinyinMode: isPinyinMode, page: currentPage)
    }

    func pinyinTogglePressed() {
        fireKeyHaptic()
        isPinyinMode.toggle()
        pinyinBuffer = ""
        suggestionBar.clear()
        if !isPinyinMode { showPlaceholderSuggestions() }
        touchSurface.configure(shifted: isShifted, pinyinMode: isPinyinMode, page: currentPage)
    }

    func pinyinToggleLongPressed() {
        showLanguageInputPicker()
    }
}
