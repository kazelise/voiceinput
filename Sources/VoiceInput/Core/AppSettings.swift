import Foundation
import AppKit
import Combine

// MARK: - ASRBackend

enum ASRBackend: String, CaseIterable {
    case sonioxRealtime
    case openAICompatible

    var displayName: String {
        switch self {
        case .sonioxRealtime:   return "Realtime"
        case .openAICompatible: return "Just transcribe"
        }
    }

    /// Compact label for the voice-box mode chip.
    var chipLabel: String {
        switch self {
        case .sonioxRealtime:   return "Realtime"
        case .openAICompatible: return "Transcribe"
        }
    }
}

// MARK: - TranslateTarget

enum TranslateTarget: String, CaseIterable {
    case english
    case chineseSimplified
    case chineseTraditional
    case korean

    var displayName: String {
        switch self {
        case .english:           return "English"
        case .chineseSimplified: return "简体中文"
        case .chineseTraditional:return "繁體中文"
        case .korean:            return "한국어"
        }
    }

    var shortLabel: String {
        switch self {
        case .english:           return "EN"
        case .chineseSimplified: return "简"
        case .chineseTraditional:return "繁"
        case .korean:            return "KO"
        }
    }
}

// MARK: - AppSettings

final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    private let defaults = UserDefaults.standard

    // MARK: Keys (verbatim per SPEC)
    private enum Key {
        static let appEnabled                   = "appEnabled"
        static let languageHints                = "languageHints"
        static let hotkeyKey                    = "hotkeyKey"
        static let customHotkeyKeyCode          = "customHotkeyKeyCode"
        static let customHotkeyModifierFlags    = "customHotkeyModifierFlags"
        static let customHotkeyKeyEquivalent    = "customHotkeyKeyEquivalent"
        static let tapHoldThresholdMs           = "tapHoldThresholdMs"
        static let doublePressWindowMs          = "doublePressWindowMs"
        static let holdForgiveMs                = "holdForgiveMs"
        static let silenceDurationMs            = "silenceDurationMs"
        static let asrBackend                   = "asrBackend"
        static let sonioxAPIKey                 = "sonioxAPIKey"
        static let sonioxModel                  = "sonioxModel"
        static let httpASRBaseURL               = "httpASRBaseURL"
        static let httpASRAPIKey                = "httpASRAPIKey"
        static let httpASRModel                 = "httpASRModel"
        static let polishEnabled                = "polishEnabled"
        static let polishBaseURL                = "polishBaseURL"
        static let polishAPIKey                 = "polishAPIKey"
        static let polishModel                  = "polishModel"
        static let translateEnabled             = "translateEnabled"
        static let translateTarget              = "translateTarget"
        static let translateBaseURL             = "translateBaseURL"
        static let translateAPIKey              = "translateAPIKey"
        static let translateModel               = "translateModel"
        static let polishReasoningEffort        = "polishReasoningEffort"
        static let vocabularyJSON               = "vocabularyJSON"
        static let voiceBoxOpacity              = "voiceBoxOpacity"
        static let voiceBoxVerticalPosition     = "voiceBoxVerticalPosition"
        static let voiceBoxOriginX              = "voiceBoxOriginX"
        static let voiceBoxOriginY              = "voiceBoxOriginY"
        static let voiceBoxCompact              = "voiceBoxCompact"
        static let voiceBoxWidth                = "voiceBoxWidth"
        static let voiceBoxHeight               = "voiceBoxHeight"
        static let voiceBoxOriginSaved          = "voiceBoxOriginSaved"
        static let capsuleWidth                 = "capsuleWidth"
        static let capsuleHeight                = "capsuleHeight"
        static let appearancePreference         = "appearancePreference"
        static let mediaAutoPause               = "mediaAutoPause"
        static let historyEnabled               = "historyEnabled"
        static let historyKeepAudio             = "historyKeepAudio"
        static let historyMaxSessions           = "historyMaxSessions"
    }

    // The default modifier flags value: cmd | opt | ctrl | shift
    private static let defaultModifierFlagsRawValue: Int = {
        let flags: NSEvent.ModifierFlags = [.command, .option, .control, .shift]
        return Int(flags.rawValue)
    }()

    private init() {
        let d = defaults
        // Seed defaults the first time the app runs.
        if d.object(forKey: Key.appEnabled) == nil            { d.set(true, forKey: Key.appEnabled) }
        if d.object(forKey: Key.languageHints) == nil         { d.set("zh,en", forKey: Key.languageHints) }
        if d.object(forKey: Key.hotkeyKey) == nil             { d.set(HotkeyKey.fn.rawValue, forKey: Key.hotkeyKey) }
        if d.object(forKey: Key.customHotkeyKeyCode) == nil   { d.set(24, forKey: Key.customHotkeyKeyCode) }
        if d.object(forKey: Key.customHotkeyModifierFlags) == nil {
            d.set(AppSettings.defaultModifierFlagsRawValue, forKey: Key.customHotkeyModifierFlags)
        }
        if d.object(forKey: Key.customHotkeyKeyEquivalent) == nil { d.set("=", forKey: Key.customHotkeyKeyEquivalent) }
        if d.object(forKey: Key.tapHoldThresholdMs) == nil    { d.set(200, forKey: Key.tapHoldThresholdMs) }
        if d.object(forKey: Key.doublePressWindowMs) == nil   { d.set(350, forKey: Key.doublePressWindowMs) }
        if d.object(forKey: Key.holdForgiveMs) == nil         { d.set(300, forKey: Key.holdForgiveMs) }
        if d.object(forKey: Key.silenceDurationMs) == nil     { d.set(2500, forKey: Key.silenceDurationMs) }
        if d.object(forKey: Key.asrBackend) == nil            { d.set(ASRBackend.sonioxRealtime.rawValue, forKey: Key.asrBackend) }
        if d.object(forKey: Key.sonioxAPIKey) == nil          { d.set("", forKey: Key.sonioxAPIKey) }
        if d.object(forKey: Key.sonioxModel) == nil           { d.set("stt-rt-v4", forKey: Key.sonioxModel) }
        if d.object(forKey: Key.httpASRBaseURL) == nil        { d.set("https://api.openai.com/v1", forKey: Key.httpASRBaseURL) }
        if d.object(forKey: Key.httpASRAPIKey) == nil         { d.set("", forKey: Key.httpASRAPIKey) }
        if d.object(forKey: Key.httpASRModel) == nil          { d.set("gpt-4o-mini-transcribe", forKey: Key.httpASRModel) }
        if d.object(forKey: Key.polishEnabled) == nil         { d.set(true, forKey: Key.polishEnabled) }
        if d.object(forKey: Key.polishBaseURL) == nil         { d.set("https://openrouter.ai/api/v1", forKey: Key.polishBaseURL) }
        if d.object(forKey: Key.polishAPIKey) == nil          { d.set("", forKey: Key.polishAPIKey) }
        if d.object(forKey: Key.polishModel) == nil           { d.set("openai/gpt-oss-120b:free", forKey: Key.polishModel) }
        if d.object(forKey: Key.translateEnabled) == nil      { d.set(false, forKey: Key.translateEnabled) }
        if d.object(forKey: Key.translateTarget) == nil       { d.set(TranslateTarget.english.rawValue, forKey: Key.translateTarget) }
        if d.object(forKey: Key.translateBaseURL) == nil      { d.set("http://127.0.0.1:11434/v1", forKey: Key.translateBaseURL) }
        if d.object(forKey: Key.translateAPIKey) == nil       { d.set("", forKey: Key.translateAPIKey) }
        if d.object(forKey: Key.translateModel) == nil        { d.set("hy-mt2-1.8b-translate:latest", forKey: Key.translateModel) }
        if d.object(forKey: Key.polishReasoningEffort) == nil { d.set("low", forKey: Key.polishReasoningEffort) }
        if d.object(forKey: Key.vocabularyJSON) == nil        { d.set("[]", forKey: Key.vocabularyJSON) }
        if d.object(forKey: Key.voiceBoxOpacity) == nil       { d.set(0.25, forKey: Key.voiceBoxOpacity) }
        if d.object(forKey: Key.voiceBoxVerticalPosition) == nil { d.set(0.62, forKey: Key.voiceBoxVerticalPosition) }
        if d.object(forKey: Key.voiceBoxOriginX) == nil       { d.set(-1.0, forKey: Key.voiceBoxOriginX) }
        if d.object(forKey: Key.voiceBoxOriginY) == nil       { d.set(-1.0, forKey: Key.voiceBoxOriginY) }
        if d.object(forKey: Key.voiceBoxCompact) == nil       { d.set(false, forKey: Key.voiceBoxCompact) }
        if d.object(forKey: Key.voiceBoxWidth) == nil         { d.set(680.0, forKey: Key.voiceBoxWidth) }
        if d.object(forKey: Key.voiceBoxHeight) == nil        { d.set(200.0, forKey: Key.voiceBoxHeight) }
        if d.object(forKey: Key.capsuleWidth) == nil          { d.set(300.0, forKey: Key.capsuleWidth) }
        if d.object(forKey: Key.capsuleHeight) == nil         { d.set(46.0, forKey: Key.capsuleHeight) }
        if d.object(forKey: Key.voiceBoxOriginSaved) == nil   {
            // Migrate from the old (-1, -1) sentinel scheme.
            let hadOrigin = d.double(forKey: Key.voiceBoxOriginX) >= 0
                && d.double(forKey: Key.voiceBoxOriginY) >= 0
            d.set(hadOrigin, forKey: Key.voiceBoxOriginSaved)
        }
        if d.object(forKey: Key.appearancePreference) == nil  { d.set("system", forKey: Key.appearancePreference) }
        if d.object(forKey: Key.mediaAutoPause) == nil        { d.set(true, forKey: Key.mediaAutoPause) }
        if d.object(forKey: Key.historyEnabled) == nil        { d.set(true, forKey: Key.historyEnabled) }
        if d.object(forKey: Key.historyKeepAudio) == nil      { d.set(true, forKey: Key.historyKeepAudio) }
        if d.object(forKey: Key.historyMaxSessions) == nil    { d.set(200, forKey: Key.historyMaxSessions) }
    }

    // MARK: - General

    @Published var appEnabled: Bool = UserDefaults.standard.bool(forKey: Key.appEnabled) {
        didSet { defaults.set(appEnabled, forKey: Key.appEnabled) }
    }

    @Published var languageHints: String = UserDefaults.standard.string(forKey: Key.languageHints) ?? "zh,en" {
        didSet { defaults.set(languageHints, forKey: Key.languageHints) }
    }

    // MARK: - Hotkey

    @Published var hotkeyKey: HotkeyKey = {
        let raw = UserDefaults.standard.string(forKey: Key.hotkeyKey) ?? HotkeyKey.fn.rawValue
        return HotkeyKey(rawValue: raw) ?? .fn
    }() {
        didSet { defaults.set(hotkeyKey.rawValue, forKey: Key.hotkeyKey) }
    }

    @Published var customHotkeyKeyCode: Int = {
        let v = UserDefaults.standard.integer(forKey: Key.customHotkeyKeyCode)
        return v == 0 ? 24 : v
    }() {
        didSet { defaults.set(customHotkeyKeyCode, forKey: Key.customHotkeyKeyCode) }
    }

    @Published var customHotkeyModifierFlags: Int = {
        let v = UserDefaults.standard.integer(forKey: Key.customHotkeyModifierFlags)
        return v == 0 ? AppSettings.defaultModifierFlagsRawValue : v
    }() {
        didSet { defaults.set(customHotkeyModifierFlags, forKey: Key.customHotkeyModifierFlags) }
    }

    @Published var customHotkeyKeyEquivalent: String = UserDefaults.standard.string(forKey: Key.customHotkeyKeyEquivalent) ?? "=" {
        didSet { defaults.set(customHotkeyKeyEquivalent, forKey: Key.customHotkeyKeyEquivalent) }
    }

    @Published var tapHoldThresholdMs: Int = {
        let v = UserDefaults.standard.integer(forKey: Key.tapHoldThresholdMs)
        return v == 0 ? 200 : v
    }() {
        didSet { defaults.set(tapHoldThresholdMs, forKey: Key.tapHoldThresholdMs) }
    }

    @Published var doublePressWindowMs: Int = {
        let v = UserDefaults.standard.integer(forKey: Key.doublePressWindowMs)
        return v == 0 ? 350 : v
    }() {
        didSet { defaults.set(doublePressWindowMs, forKey: Key.doublePressWindowMs) }
    }

    @Published var holdForgiveMs: Int = {
        let v = UserDefaults.standard.integer(forKey: Key.holdForgiveMs)
        return v == 0 ? 300 : v
    }() {
        didSet { defaults.set(holdForgiveMs, forKey: Key.holdForgiveMs) }
    }

    @Published var silenceDurationMs: Int = {
        let v = UserDefaults.standard.integer(forKey: Key.silenceDurationMs)
        return v == 0 ? 2500 : v
    }() {
        didSet { defaults.set(silenceDurationMs, forKey: Key.silenceDurationMs) }
    }

    // MARK: - ASR

    @Published var asrBackend: ASRBackend = {
        let raw = UserDefaults.standard.string(forKey: Key.asrBackend) ?? ASRBackend.sonioxRealtime.rawValue
        return ASRBackend(rawValue: raw) ?? .sonioxRealtime
    }() {
        didSet { defaults.set(asrBackend.rawValue, forKey: Key.asrBackend) }
    }

    @Published var sonioxAPIKey: String = UserDefaults.standard.string(forKey: Key.sonioxAPIKey) ?? "" {
        didSet { defaults.set(sonioxAPIKey, forKey: Key.sonioxAPIKey) }
    }

    @Published var sonioxModel: String = {
        let v = UserDefaults.standard.string(forKey: Key.sonioxModel) ?? "stt-rt-v4"
        return v.isEmpty ? "stt-rt-v4" : v
    }() {
        didSet { defaults.set(sonioxModel, forKey: Key.sonioxModel) }
    }

    @Published var httpASRBaseURL: String = {
        let v = UserDefaults.standard.string(forKey: Key.httpASRBaseURL) ?? "https://api.openai.com/v1"
        return v.isEmpty ? "https://api.openai.com/v1" : v
    }() {
        didSet { defaults.set(httpASRBaseURL, forKey: Key.httpASRBaseURL) }
    }

    @Published var httpASRAPIKey: String = UserDefaults.standard.string(forKey: Key.httpASRAPIKey) ?? "" {
        didSet { defaults.set(httpASRAPIKey, forKey: Key.httpASRAPIKey) }
    }

    @Published var httpASRModel: String = {
        let v = UserDefaults.standard.string(forKey: Key.httpASRModel) ?? "gpt-4o-mini-transcribe"
        return v.isEmpty ? "gpt-4o-mini-transcribe" : v
    }() {
        didSet { defaults.set(httpASRModel, forKey: Key.httpASRModel) }
    }

    // MARK: - Refinement

    @Published var polishEnabled: Bool = UserDefaults.standard.bool(forKey: Key.polishEnabled) {
        didSet { defaults.set(polishEnabled, forKey: Key.polishEnabled) }
    }

    @Published var polishBaseURL: String = {
        let v = UserDefaults.standard.string(forKey: Key.polishBaseURL) ?? "https://openrouter.ai/api/v1"
        return v.isEmpty ? "https://openrouter.ai/api/v1" : v
    }() {
        didSet { defaults.set(polishBaseURL, forKey: Key.polishBaseURL) }
    }

    @Published var polishAPIKey: String = UserDefaults.standard.string(forKey: Key.polishAPIKey) ?? "" {
        didSet { defaults.set(polishAPIKey, forKey: Key.polishAPIKey) }
    }

    @Published var polishModel: String = {
        let v = UserDefaults.standard.string(forKey: Key.polishModel) ?? "openai/gpt-oss-120b:free"
        return v.isEmpty ? "openai/gpt-oss-120b:free" : v
    }() {
        didSet { defaults.set(polishModel, forKey: Key.polishModel) }
    }

    @Published var translateEnabled: Bool = UserDefaults.standard.bool(forKey: Key.translateEnabled) {
        didSet { defaults.set(translateEnabled, forKey: Key.translateEnabled) }
    }

    @Published var translateTarget: TranslateTarget = {
        let raw = UserDefaults.standard.string(forKey: Key.translateTarget) ?? TranslateTarget.english.rawValue
        return TranslateTarget(rawValue: raw) ?? .english
    }() {
        didSet { defaults.set(translateTarget.rawValue, forKey: Key.translateTarget) }
    }

    @Published var translateBaseURL: String = {
        let v = UserDefaults.standard.string(forKey: Key.translateBaseURL) ?? "http://127.0.0.1:11434/v1"
        return v.isEmpty ? "http://127.0.0.1:11434/v1" : v
    }() {
        didSet { defaults.set(translateBaseURL, forKey: Key.translateBaseURL) }
    }

    @Published var translateAPIKey: String = UserDefaults.standard.string(forKey: Key.translateAPIKey) ?? "" {
        didSet { defaults.set(translateAPIKey, forKey: Key.translateAPIKey) }
    }

    @Published var translateModel: String = {
        let v = UserDefaults.standard.string(forKey: Key.translateModel) ?? "hy-mt2-1.8b-translate:latest"
        return v.isEmpty ? "hy-mt2-1.8b-translate:latest" : v
    }() {
        didSet { defaults.set(translateModel, forKey: Key.translateModel) }
    }

    // MARK: - Vocabulary

    @Published var vocabularyJSON: String = {
        let v = UserDefaults.standard.string(forKey: Key.vocabularyJSON) ?? "[]"
        return v.isEmpty ? "[]" : v
    }() {
        didSet { defaults.set(vocabularyJSON, forKey: Key.vocabularyJSON) }
    }

    // MARK: - Appearance

    @Published var voiceBoxOpacity: Double = {
        // object(forKey:) to distinguish unset (nil) from explicitly 0
        if UserDefaults.standard.object(forKey: Key.voiceBoxOpacity) != nil {
            return UserDefaults.standard.double(forKey: Key.voiceBoxOpacity)
        }
        return 0.25
    }() {
        didSet { defaults.set(voiceBoxOpacity, forKey: Key.voiceBoxOpacity) }
    }

    @Published var voiceBoxVerticalPosition: Double = {
        if UserDefaults.standard.object(forKey: Key.voiceBoxVerticalPosition) != nil {
            return UserDefaults.standard.double(forKey: Key.voiceBoxVerticalPosition)
        }
        return 0.62
    }() {
        didSet { defaults.set(voiceBoxVerticalPosition, forKey: Key.voiceBoxVerticalPosition) }
    }

    /// Whether voiceBoxOriginX/Y holds a user-placed position. A separate flag
    /// (not a coordinate sentinel) because origins are legitimately negative on
    /// monitors left of / below the primary display.
    @Published var voiceBoxOriginSaved: Bool = UserDefaults.standard.bool(forKey: Key.voiceBoxOriginSaved) {
        didSet { defaults.set(voiceBoxOriginSaved, forKey: Key.voiceBoxOriginSaved) }
    }

    /// Custom voice-box origin saved after the user drags the panel.
    /// Only meaningful when voiceBoxOriginSaved is true.
    @Published var voiceBoxOriginX: Double = {
        if UserDefaults.standard.object(forKey: Key.voiceBoxOriginX) != nil {
            return UserDefaults.standard.double(forKey: Key.voiceBoxOriginX)
        }
        return -1.0
    }() {
        didSet { defaults.set(voiceBoxOriginX, forKey: Key.voiceBoxOriginX) }
    }

    @Published var voiceBoxOriginY: Double = {
        if UserDefaults.standard.object(forKey: Key.voiceBoxOriginY) != nil {
            return UserDefaults.standard.double(forKey: Key.voiceBoxOriginY)
        }
        return -1.0
    }() {
        didSet { defaults.set(voiceBoxOriginY, forKey: Key.voiceBoxOriginY) }
    }

    /// Reasoning effort sent with polish requests: "off" | "low" | "medium" | "high".
    /// OpenRouter endpoints get {"reasoning": {"effort": X}}; other
    /// OpenAI-compatible endpoints (OpenAI, Cerebras, …) get "reasoning_effort".
    @Published var polishReasoningEffort: String = UserDefaults.standard.string(forKey: Key.polishReasoningEffort) ?? "low" {
        didSet { defaults.set(polishReasoningEffort, forKey: Key.polishReasoningEffort) }
    }

    /// Whether the voice box is collapsed into its compact capsule form.
    @Published var voiceBoxCompact: Bool = UserDefaults.standard.bool(forKey: Key.voiceBoxCompact) {
        didSet { defaults.set(voiceBoxCompact, forKey: Key.voiceBoxCompact) }
    }

    /// User-resized voice-box dimensions (points), persisted after edge drags.
    @Published var voiceBoxWidth: Double = {
        if UserDefaults.standard.object(forKey: Key.voiceBoxWidth) != nil {
            return UserDefaults.standard.double(forKey: Key.voiceBoxWidth)
        }
        return 680
    }() {
        didSet { defaults.set(voiceBoxWidth, forKey: Key.voiceBoxWidth) }
    }

    @Published var voiceBoxHeight: Double = {
        if UserDefaults.standard.object(forKey: Key.voiceBoxHeight) != nil {
            return UserDefaults.standard.double(forKey: Key.voiceBoxHeight)
        }
        return 200
    }() {
        didSet { defaults.set(voiceBoxHeight, forKey: Key.voiceBoxHeight) }
    }

    /// Compact-capsule dimensions (points), resizable independently of the box.
    @Published var capsuleWidth: Double = {
        if UserDefaults.standard.object(forKey: Key.capsuleWidth) != nil {
            return UserDefaults.standard.double(forKey: Key.capsuleWidth)
        }
        return 300
    }() {
        didSet { defaults.set(capsuleWidth, forKey: Key.capsuleWidth) }
    }

    @Published var capsuleHeight: Double = {
        if UserDefaults.standard.object(forKey: Key.capsuleHeight) != nil {
            return UserDefaults.standard.double(forKey: Key.capsuleHeight)
        }
        return 46
    }() {
        didSet { defaults.set(capsuleHeight, forKey: Key.capsuleHeight) }
    }

    /// "system" | "light" | "dark" — applied to NSApp.appearance at launch and on change.
    @Published var appearancePreference: String = UserDefaults.standard.string(forKey: Key.appearancePreference) ?? "system" {
        didSet { defaults.set(appearancePreference, forKey: Key.appearancePreference) }
    }

    @Published var mediaAutoPause: Bool = {
        if UserDefaults.standard.object(forKey: Key.mediaAutoPause) != nil {
            return UserDefaults.standard.bool(forKey: Key.mediaAutoPause)
        }
        return true
    }() {
        didSet { defaults.set(mediaAutoPause, forKey: Key.mediaAutoPause) }
    }

    @Published var historyEnabled: Bool = {
        if UserDefaults.standard.object(forKey: Key.historyEnabled) != nil {
            return UserDefaults.standard.bool(forKey: Key.historyEnabled)
        }
        return true
    }() {
        didSet { defaults.set(historyEnabled, forKey: Key.historyEnabled) }
    }

    @Published var historyKeepAudio: Bool = {
        if UserDefaults.standard.object(forKey: Key.historyKeepAudio) != nil {
            return UserDefaults.standard.bool(forKey: Key.historyKeepAudio)
        }
        return true
    }() {
        didSet { defaults.set(historyKeepAudio, forKey: Key.historyKeepAudio) }
    }

    @Published var historyMaxSessions: Int = {
        if UserDefaults.standard.object(forKey: Key.historyMaxSessions) != nil {
            return UserDefaults.standard.integer(forKey: Key.historyMaxSessions)
        }
        return 200
    }() {
        didSet { defaults.set(historyMaxSessions, forKey: Key.historyMaxSessions) }
    }

    // MARK: - Derived

    /// Parsed, trimmed, lowercased, non-empty language hint codes.
    var languageHintsArray: [String] {
        languageHints
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }
    }

    /// HotkeyShortcut built from stored custom hotkey properties.
    var hotkeyShortcut: HotkeyShortcut {
        HotkeyShortcut(
            keyCode: UInt16(max(0, min(customHotkeyKeyCode, Int(UInt16.max)))),
            modifierFlags: NSEvent.ModifierFlags(rawValue: UInt(customHotkeyModifierFlags)),
            keyEquivalent: customHotkeyKeyEquivalent
        )
    }

    /// Human-readable hotkey name for the overlay button label.
    var hotkeyDisplayName: String {
        hotkeyKey == .customShortcut ? hotkeyShortcut.displayString : hotkeyKey.displayName
    }
}
