import Cocoa
import SwiftUI
import Combine
import Security

final class AppInstanceLock {
    private let lockFilePath: String = {
        let fileManager = FileManager.default
        let baseDirectory = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        return baseDirectory
            .appendingPathComponent("AgentMonitor", isDirectory: true)
            .appendingPathComponent("agent_monitor.lock").path
    }()
    private var lockFd: Int32 = -1

    func acquire() -> Bool {
        let lockDir = URL(fileURLWithPath: lockFilePath).deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: lockDir, withIntermediateDirectories: true)

        let fd = open(lockFilePath, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard fd >= 0 else {
            NSLog("[AgentMonitor] Singleton: failed to open lock file")
            return true
        }

        guard flock(fd, LOCK_EX | LOCK_NB) == 0 else {
            let lockErrno = errno
            Darwin.close(fd)
            if lockErrno == EWOULDBLOCK {
                return false
            }
            NSLog("[AgentMonitor] Singleton: flock failed: %d", lockErrno)
            return true
        }

        lockFd = fd
        let pidLine = "\(getpid())\n"
        _ = ftruncate(fd, 0)
        _ = pidLine.withCString { ptr in
            Darwin.write(fd, ptr, strlen(ptr))
        }
        return true
    }

    func release() {
        guard lockFd >= 0 else { return }
        Darwin.close(lockFd)
        lockFd = -1
    }
}

// MARK: - Skin System

struct SkinColors {
    let working: Color
    let attention: Color
    let done: Color
    let starting: Color
    let headerText: Color
    let headerIcon: Color
    let sessionTitle: Color
    let sessionTitleStale: Color
    let sessionSubtext: Color
    let timestamp: Color
    let divider: Color
    let border: Color
    let shadow: Color
    let panelBackground: Color
    let permissionBackground: Color
    let buttonTextColor: Color
    let settingsAccent: Color
    let accent: Color
    let chevron: Color
    let killButton: Color
    let statusBadgeText: Color

    func statusColor(for status: String) -> Color {
        switch status {
        case "starting":  return starting
        case "working":   return working
        case "done":      return done
        case "attention": return attention
        default:          return starting
        }
    }
}

struct MonitorSkin: Identifiable, Equatable {
    let id: String
    let name: String
    let colors: SkinColors
    let material: NSVisualEffectView.Material
    let cornerRadius: CGFloat
    let usesVibrancy: Bool
    let fontDesign: Font.Design
    let headerFontDesign: Font.Design
    let dotSize: CGFloat
    let borderWidth: CGFloat

    static func == (lhs: MonitorSkin, rhs: MonitorSkin) -> Bool {
        lhs.id == rhs.id
    }

    // MARK: - Built-in Skins

    static let glass = MonitorSkin(
        id: "glass",
        name: "Glass",
        colors: SkinColors(
            working: .cyan,
            attention: .orange,
            done: Color(red: 0.3, green: 0.9, blue: 0.4),
            starting: Color(white: 0.5),
            headerText: .white.opacity(0.9),
            headerIcon: .white.opacity(0.6),
            sessionTitle: .white,
            sessionTitleStale: .white.opacity(0.35),
            sessionSubtext: .white.opacity(0.45),
            timestamp: .white.opacity(0.35),
            divider: .white.opacity(0.08),
            border: .white.opacity(0.15),
            shadow: .black.opacity(0.25),
            panelBackground: .clear,
            permissionBackground: .orange.opacity(0.05),
            buttonTextColor: .white.opacity(0.5),
            settingsAccent: .white.opacity(0.8),
            accent: .white.opacity(0.8),
            chevron: .white.opacity(0.25),
            killButton: .white.opacity(0.35),
            statusBadgeText: .white.opacity(0.5)
        ),
        material: .hudWindow,
        cornerRadius: 16,
        usesVibrancy: true,
        fontDesign: .default,
        headerFontDesign: .default,
        dotSize: 8,
        borderWidth: 0.5
    )

    static let terminal = MonitorSkin(
        id: "terminal",
        name: "Terminal",
        colors: SkinColors(
            working: Color(red: 0.659, green: 0.941, blue: 0.690),
            attention: Color(red: 1.000, green: 0.667, blue: 0.239),
            done: Color(red: 0.490, green: 0.784, blue: 0.541),
            starting: Color(red: 0.055, green: 0.157, blue: 0.094),
            headerText: Color(red: 0.490, green: 0.784, blue: 0.541),
            headerIcon: Color(red: 0.176, green: 0.416, blue: 0.271),
            sessionTitle: Color(red: 0.490, green: 0.784, blue: 0.541),
            sessionTitleStale: Color(red: 0.102, green: 0.251, blue: 0.157),
            sessionSubtext: Color(red: 0.176, green: 0.416, blue: 0.271),
            timestamp: Color(red: 0.176, green: 0.416, blue: 0.271),
            divider: Color(red: 0.055, green: 0.157, blue: 0.094),
            border: Color(red: 0.290, green: 0.600, blue: 0.408).opacity(0.6),
            shadow: .black.opacity(0.45),
            panelBackground: Color(red: 0.024, green: 0.063, blue: 0.039),
            permissionBackground: Color(red: 0.055, green: 0.157, blue: 0.094).opacity(0.4),
            buttonTextColor: Color(red: 0.176, green: 0.416, blue: 0.271),
            settingsAccent: Color(red: 0.490, green: 0.784, blue: 0.541),
            accent: Color(red: 0.490, green: 0.784, blue: 0.541),
            chevron: Color(red: 0.102, green: 0.251, blue: 0.157),
            killButton: Color(red: 0.176, green: 0.416, blue: 0.271),
            statusBadgeText: Color(red: 0.290, green: 0.600, blue: 0.408)
        ),
        material: .hudWindow,
        cornerRadius: 8,
        usesVibrancy: false,
        fontDesign: .monospaced,
        headerFontDesign: .monospaced,
        dotSize: 8,
        borderWidth: 0.5
    )

    static let teletype = MonitorSkin(
        id: "teletype",
        name: "Teletype",
        colors: SkinColors(
            working: Color(red: 0.659, green: 0.188, blue: 0.125),
            attention: Color(red: 0.769, green: 0.345, blue: 0.125),
            done: Color(red: 0.102, green: 0.078, blue: 0.063),
            starting: Color(red: 0.659, green: 0.620, blue: 0.541),
            headerText: Color(red: 0.239, green: 0.204, blue: 0.165),
            headerIcon: Color(red: 0.420, green: 0.373, blue: 0.306),
            sessionTitle: Color(red: 0.102, green: 0.078, blue: 0.063),
            sessionTitleStale: Color(red: 0.659, green: 0.620, blue: 0.541),
            sessionSubtext: Color(red: 0.420, green: 0.373, blue: 0.306),
            timestamp: Color(red: 0.420, green: 0.373, blue: 0.306),
            divider: Color(red: 0.847, green: 0.792, blue: 0.659),
            border: Color(red: 0.239, green: 0.204, blue: 0.165).opacity(0.15),
            shadow: Color(red: 0.102, green: 0.078, blue: 0.063).opacity(0.18),
            panelBackground: Color(red: 0.957, green: 0.918, blue: 0.835),
            permissionBackground: Color(red: 0.659, green: 0.188, blue: 0.125).opacity(0.06),
            buttonTextColor: Color(red: 0.420, green: 0.373, blue: 0.306),
            settingsAccent: Color(red: 0.239, green: 0.204, blue: 0.165),
            accent: Color(red: 0.239, green: 0.204, blue: 0.165),
            chevron: Color(red: 0.659, green: 0.620, blue: 0.541),
            killButton: Color(red: 0.659, green: 0.620, blue: 0.541),
            statusBadgeText: Color(red: 0.239, green: 0.204, blue: 0.165)
        ),
        material: .hudWindow,
        cornerRadius: 6,
        usesVibrancy: false,
        fontDesign: .default,
        headerFontDesign: .serif,
        dotSize: 7,
        borderWidth: 0.5
    )

    static let obsidian = MonitorSkin(
        id: "obsidian",
        name: "Obsidian",
        colors: SkinColors(
            working: Color(red: 0.3, green: 0.65, blue: 1.0),
            attention: Color(red: 1.0, green: 0.6, blue: 0.25),
            done: Color(red: 0.3, green: 0.8, blue: 0.5),
            starting: Color(red: 0.35, green: 0.35, blue: 0.38),
            headerText: Color(white: 0.65),
            headerIcon: Color(white: 0.5),
            sessionTitle: Color(white: 0.75),
            sessionTitleStale: Color(white: 0.45),
            sessionSubtext: Color(white: 0.5),
            timestamp: Color(white: 0.45),
            divider: Color(white: 0.0).opacity(0.4),
            border: .clear,  // depth comes from shadows, not strokes
            shadow: .black.opacity(0.6),
            panelBackground: Color(red: 0.11, green: 0.11, blue: 0.12),
            permissionBackground: Color(red: 1.0, green: 0.6, blue: 0.25).opacity(0.04),
            buttonTextColor: Color(white: 0.55),
            settingsAccent: Color(white: 0.65),
            accent: Color(red: 0.3, green: 0.65, blue: 1.0),
            chevron: Color(white: 0.4),
            killButton: Color(white: 0.5),
            statusBadgeText: Color(white: 0.55)
        ),
        material: .hudWindow,
        cornerRadius: 16,
        usesVibrancy: false,
        fontDesign: .default,
        headerFontDesign: .default,
        dotSize: 8,
        borderWidth: 0
    )

    static let allSkins: [MonitorSkin] = [glass, obsidian, terminal, teletype]

    static func skin(for id: String) -> MonitorSkin {
        allSkins.first(where: { $0.id == id }) ?? glass
    }
}

// MARK: - Skin Environment Key

private struct SkinKey: EnvironmentKey {
    static let defaultValue: MonitorSkin = .glass
}

extension EnvironmentValues {
    var skin: MonitorSkin {
        get { self[SkinKey.self] }
        set { self[SkinKey.self] = newValue }
    }
}

// MARK: - Config Manager

struct MonitorConfig: Codable {
    var tts_provider: String
    var elevenlabs: ElevenLabsConfig
    var say: SayConfig
    var announce: AnnounceConfig
    var skin: String?

    struct ElevenLabsConfig: Codable {
        var env_file: String
        var voice_id: String?
        var model: String
        var stability: Double
        var similarity_boost: Double
    }
    struct SayConfig: Codable {
        var voice: String
        var rate: Int
    }
    struct AnnounceConfig: Codable {
        var enabled: Bool
        var on_done: Bool
        var on_attention: Bool
        var on_start: Bool
        var volume: Double
    }
    struct UsageConfig: Codable {
        var enabled: Bool
    }
    struct SavedVoice: Codable {
        var id: String
        var name: String
    }
    struct GlassConfig: Codable {
        var blur: Double       // 0.0–1.0, maps to visual effect alpha
        var opacity: Double    // 0.0–1.0, dark floor alpha
        var tintR: Double
        var tintG: Double
        var tintB: Double
        var tintStrength: Double  // 0.0–1.0, tint layer alpha
    }
    var voices: [SavedVoice]?
    var usage: UsageConfig?
    var glass: GlassConfig?

    enum CodingKeys: String, CodingKey {
        case tts_provider
        case elevenlabs
        case say
        case announce
        case skin
        case voices
        case usage
        case glass
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        tts_provider = try container.decodeIfPresent(String.self, forKey: .tts_provider) ?? "say"
        elevenlabs = try container.decode(ElevenLabsConfig.self, forKey: .elevenlabs)
        say = try container.decode(SayConfig.self, forKey: .say)
        announce = try container.decode(AnnounceConfig.self, forKey: .announce)
        skin = try container.decodeIfPresent(String.self, forKey: .skin)
        voices = try container.decodeIfPresent([SavedVoice].self, forKey: .voices)
        usage = try container.decodeIfPresent(UsageConfig.self, forKey: .usage)
        glass = try container.decodeIfPresent(GlassConfig.self, forKey: .glass)
    }
}

// MARK: - ElevenLabs Voice Info

struct ElevenLabsVoice: Identifiable {
    let id: String
    let name: String
}

struct ElevenLabsVoicesResponse: Codable {
    struct Voice: Codable {
        let voice_id: String
        let name: String
        let category: String?
    }
    let voices: [Voice]
}

class VoiceFetcher: ObservableObject {
    @Published var voices: [ElevenLabsVoice] = []
    @Published var hasFetched = false
    private var apiKey: String?

    func loadAPIKey(envFilePath: String) {
        let expanded = (envFilePath as NSString).expandingTildeInPath
        guard let content = try? String(contentsOfFile: expanded, encoding: .utf8) else { return }
        for line in content.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("ELEVENLABS_API_KEY=") {
                apiKey = String(trimmed.dropFirst("ELEVENLABS_API_KEY=".count))
                break
            }
        }
    }

    func fetchVoices() {
        guard let apiKey = apiKey, !apiKey.isEmpty else { return }
        guard let url = URL(string: "https://api.elevenlabs.io/v1/voices") else { return }

        var request = URLRequest(url: url)
        request.setValue(apiKey, forHTTPHeaderField: "xi-api-key")

        URLSession.shared.dataTask(with: request) { [weak self] data, _, _ in
            guard let data = data,
                  let response = try? JSONDecoder().decode(ElevenLabsVoicesResponse.self, from: data) else {
                return
            }
            // Only show user's own voices (cloned, generated, professional), not premade
            let voices = response.voices
                .filter { $0.category != "premade" }
                .map { ElevenLabsVoice(id: $0.voice_id, name: $0.name) }
                .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            DispatchQueue.main.async {
                self?.voices = voices
                self?.hasFetched = true
            }
        }.resume()
    }

    func name(for voiceId: String) -> String? {
        voices.first(where: { $0.id == voiceId })?.name
    }

    func resolveVoiceName(id: String, completion: @escaping (String?) -> Void) {
        guard let apiKey = apiKey, !apiKey.isEmpty else { completion(nil); return }
        guard let url = URL(string: "https://api.elevenlabs.io/v1/voices/\(id)") else { completion(nil); return }
        var request = URLRequest(url: url)
        request.setValue(apiKey, forHTTPHeaderField: "xi-api-key")
        URLSession.shared.dataTask(with: request) { data, _, _ in
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let name = json["name"] as? String else {
                completion(nil)
                return
            }
            completion(name)
        }.resume()
    }

}

class ConfigManager: ObservableObject {
    @Published var config: MonitorConfig?
    @Published var currentSkin: MonitorSkin = .glass
    let voiceFetcher = VoiceFetcher()

    static let configPath: String = {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/.claude/monitor/config.json"
    }()

    init() {
        load()
        // Kick off voice fetch
        if let envFile = config?.elevenlabs.env_file {
            voiceFetcher.loadAPIKey(envFilePath: envFile)
            voiceFetcher.fetchVoices()
        }
    }

    func load() {
        guard let data = FileManager.default.contents(atPath: Self.configPath),
              let decoded = try? JSONDecoder().decode(MonitorConfig.self, from: data) else { return }
        self.config = decoded
        self.currentSkin = MonitorSkin.skin(for: decoded.skin ?? "glass")
    }

    func setSkin(_ skinId: String) {
        config?.skin = skinId
        currentSkin = MonitorSkin.skin(for: skinId)
        save()
        objectWillChange.send()
    }

    var skinId: String {
        config?.skin ?? "glass"
    }

    var ttsProvider: String {
        config?.tts_provider ?? "say"
    }

    func setTTSProvider(_ provider: String) {
        config?.tts_provider = provider
        save()
        objectWillChange.send()
    }

    var usesElevenLabsTTS: Bool {
        ttsProvider == "cache" || ttsProvider == "elevenlabs"
    }

    func setVoice(_ voiceId: String) {
        config?.elevenlabs.voice_id = voiceId
        save()
    }

    func toggleVoice() {
        config?.announce.enabled.toggle()
        save()
        objectWillChange.send()
    }

    var voiceEnabled: Bool {
        config?.announce.enabled ?? true
    }

    func toggleUsage() {
        if config?.usage == nil {
            config?.usage = MonitorConfig.UsageConfig(enabled: true)
        } else {
            config?.usage?.enabled.toggle()
        }
        save()
        objectWillChange.send()
    }

    var usageEnabled: Bool {
        config?.usage?.enabled ?? false
    }

    func save() {
        guard let config = config else { return }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(config) else { return }
        let tmpUrl = URL(fileURLWithPath: Self.configPath + ".tmp")
        try? data.write(to: tmpUrl)
        _ = try? FileManager.default.replaceItemAt(URL(fileURLWithPath: Self.configPath), withItemAt: tmpUrl)
    }

    var currentVoiceId: String {
        config?.elevenlabs.voice_id ?? ""
    }

    func voiceName(for id: String) -> String? {
        if let saved = config?.voices?.first(where: { $0.id == id }) {
            return saved.name
        }
        return voiceFetcher.name(for: id)
    }

    var allVoices: [ElevenLabsVoice] {
        var combined: [ElevenLabsVoice] = []
        var seenIds = Set<String>()
        if let saved = config?.voices {
            for v in saved {
                combined.append(ElevenLabsVoice(id: v.id, name: v.name))
                seenIds.insert(v.id)
            }
        }
        for v in voiceFetcher.voices {
            if !seenIds.contains(v.id) {
                combined.append(v)
            }
        }
        return combined
    }

    func addVoice(id: String, name: String) {
        var voices = config?.voices ?? []
        if !voices.contains(where: { $0.id == id }) {
            voices.append(MonitorConfig.SavedVoice(id: id, name: name))
            config?.voices = voices
            save()
        }
    }

    // MARK: - Glass tuning

    static let defaultGlass = MonitorConfig.GlassConfig(
        blur: 1.0, opacity: 0.5, tintR: 0.5, tintG: 0.5, tintB: 0.5, tintStrength: 0.0
    )

    var glassConfig: MonitorConfig.GlassConfig {
        config?.glass ?? Self.defaultGlass
    }

    func setGlass(_ glass: MonitorConfig.GlassConfig) {
        config?.glass = glass
        save()
        objectWillChange.send()
    }
}

// MARK: - Usage Data Model

struct UsageWindow: Codable {
    let utilization: Double
    let resets_at: String

    var utilizationPercent: Double { min(utilization, 100) }

    var resetsAtDate: Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: resets_at) { return d }
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: resets_at)
    }

    var resetCountdown: String {
        guard let target = resetsAtDate else { return "" }
        let remaining = target.timeIntervalSince(Date())
        guard remaining > 0 else { return "now" }
        let days = Int(remaining / 86400)
        let hours = Int((remaining.truncatingRemainder(dividingBy: 86400)) / 3600)
        let mins = Int((remaining.truncatingRemainder(dividingBy: 3600)) / 60)
        if days > 0 { return "\(days)d \(hours)h" }
        if hours > 0 { return "\(hours)h \(mins)m" }
        return "\(mins)m"
    }

    var barColor: Color {
        if utilizationPercent > 80 { return .red }
        if utilizationPercent > 50 { return .yellow }
        return .green
    }
}

struct ExtraUsageInfo: Codable {
    let is_enabled: Bool?
    let monthly_limit: Double?
    let used_credits: Double?
    let utilization: Double?
    let currency: String?

    var usedDollars: Double { (used_credits ?? 0) / 100.0 }
    var limitDollars: Double { (monthly_limit ?? 0) / 100.0 }
}

struct UsageResponse: Codable {
    let five_hour: UsageWindow?
    let seven_day: UsageWindow?
    let seven_day_sonnet: UsageWindow?
    let seven_day_opus: UsageWindow?
    let extra_usage: ExtraUsageInfo?
}

// MARK: - Usage Fetcher

class UsageFetcher: ObservableObject {
    @Published var usage: UsageResponse?
    @Published var error: String?
    @Published var lastFetched: Date?
    @Published var isEnabled: Bool = true
    private var timer: Timer?
    private var pollInterval: TimeInterval = 300 // 5 minutes
    private let maxPollInterval: TimeInterval = 900 // 15 minutes
    private let minFetchGap: TimeInterval = 120 // 2 minutes — won't re-fetch if younger

    // Cached credentials — read from Keychain once, reuse until expired
    private var cachedToken: String?
    private var tokenExpiresAt: Date?

    private let credentialsPath: String = {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/.claude/.credentials.json"
    }()

    init(enabled: Bool = true) {
        self.isEnabled = enabled
        guard enabled else { return }
        fetch()
        schedulePoll()
    }

    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        if enabled {
            fetch()
            schedulePoll()
        } else {
            timer?.invalidate()
            timer = nil
            usage = nil
            error = nil
            lastFetched = nil
        }
    }

    private func schedulePoll() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: false) { [weak self] _ in
            self?.fetch()
            self?.schedulePoll()
        }
    }

    /// Called on popover open — skips if data is fresh
    func fetchIfStale() {
        if let last = lastFetched, Date().timeIntervalSince(last) < minFetchGap { return }
        fetch()
    }

    func fetch() {
        guard let token = getToken() else {
            DispatchQueue.main.async { self.error = "No credentials" }
            return
        }

        guard let url = URL(string: "https://api.anthropic.com/api/oauth/usage") else { return }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("claude-monitor/1.0", forHTTPHeaderField: "User-Agent")

        URLSession.shared.dataTask(with: request) { [weak self] data, response, err in
            guard let self = self else { return }
            DispatchQueue.main.async {
                if let err = err {
                    self.error = err.localizedDescription
                    return
                }
                guard let data = data else {
                    self.error = "No data"
                    return
                }
                if let httpResponse = response as? HTTPURLResponse {
                    if httpResponse.statusCode == 429 {
                        // Back off: double poll interval, cap at max
                        self.pollInterval = min(self.pollInterval * 2, self.maxPollInterval)
                        self.schedulePoll()
                        self.error = "Rate limited — backing off to \(Int(self.pollInterval / 60))m"
                        NSLog("[AgentMonitor] Usage 429 — poll interval now %.0fs", self.pollInterval)
                        return
                    }
                    if httpResponse.statusCode == 401 {
                        // Token might be stale — clear cache so next fetch re-reads Keychain
                        self.cachedToken = nil
                        self.tokenExpiresAt = nil
                        self.error = "Auth expired"
                        return
                    }
                    if httpResponse.statusCode != 200 {
                        self.error = "HTTP \(httpResponse.statusCode)"
                        return
                    }
                }
                do {
                    let decoded = try JSONDecoder().decode(UsageResponse.self, from: data)
                    self.usage = decoded
                    self.error = nil
                    self.lastFetched = Date()
                    // Reset poll interval on success
                    if self.pollInterval != 300 {
                        self.pollInterval = 300
                        self.schedulePoll()
                    }
                } catch {
                    self.error = "Parse error"
                    NSLog("[AgentMonitor] Usage parse error: %@", error.localizedDescription)
                }
            }
        }.resume()
    }

    // MARK: - Token management (cached, read Keychain at most once per expiry cycle)

    private func getToken() -> String? {
        // Return cached token if still valid (with 60s buffer)
        if let token = cachedToken, let expires = tokenExpiresAt, expires.timeIntervalSinceNow > 60 {
            return token
        }
        // Need to read fresh credentials
        cachedToken = nil
        tokenExpiresAt = nil

        // Try credentials file first
        if let data = FileManager.default.contents(atPath: credentialsPath),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let (token, expiry) = extractCredentials(from: json) {
                cachedToken = token
                tokenExpiresAt = expiry
                return token
            }
        }
        // Fall back to macOS Keychain (single read, then cached)
        return readFromKeychain()
    }

    private func readFromKeychain() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "Claude Code-credentials",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        if let (token, expiry) = extractCredentials(from: json) {
            cachedToken = token
            tokenExpiresAt = expiry
            return token
        }
        return nil
    }

    /// Returns (accessToken, expiresAt) from either top-level or nested claudeAiOauth
    private func extractCredentials(from json: [String: Any]) -> (String, Date?)? {
        // Try top-level
        if let token = json["accessToken"] as? String ?? json["access_token"] as? String {
            let expiry = parseExpiry(json["expiresAt"])
            return (token, expiry)
        }
        // Try nested claudeAiOauth
        if let oauth = json["claudeAiOauth"] as? [String: Any],
           let token = oauth["accessToken"] as? String ?? oauth["access_token"] as? String {
            let expiry = parseExpiry(oauth["expiresAt"])
            return (token, expiry)
        }
        return nil
    }

    private func parseExpiry(_ value: Any?) -> Date? {
        // expiresAt is milliseconds since epoch
        if let ms = value as? Double { return Date(timeIntervalSince1970: ms / 1000) }
        if let ms = value as? Int { return Date(timeIntervalSince1970: Double(ms) / 1000) }
        if let s = value as? String, let ms = Double(s) { return Date(timeIntervalSince1970: ms / 1000) }
        return nil
    }
}

// MARK: - Session Model

struct SessionInfo: Codable, Identifiable, Equatable {
    let session_id: String
    var agent: String
    var status: String
    var project: String
    var cwd: String
    var terminal: String
    var terminal_session_id: String
    var started_at: String
    var updated_at: String
    var last_prompt: String
    var thread_id: String
    let startedAtDate: Date?
    let updatedAtDate: Date?

    private static let iso8601Fractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let iso8601Plain: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    var id: String { session_id }

    enum CodingKeys: String, CodingKey {
        case session_id, agent, status, project, cwd, terminal, terminal_session_id, started_at, updated_at, last_prompt, thread_id
    }

    private static func normalizeAgent(_ value: String) -> String {
        value.lowercased() == "codex" ? "codex" : "claude"
    }

    private static func parseISO8601(_ value: String) -> Date? {
        iso8601Fractional.date(from: value) ?? iso8601Plain.date(from: value)
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        session_id = try c.decode(String.self, forKey: .session_id)
        agent = Self.normalizeAgent((try? c.decode(String.self, forKey: .agent)) ?? "claude")
        status = (try? c.decode(String.self, forKey: .status)) ?? "unknown"
        project = (try? c.decode(String.self, forKey: .project)) ?? "unknown"
        cwd = (try? c.decode(String.self, forKey: .cwd)) ?? ""
        terminal = (try? c.decode(String.self, forKey: .terminal)) ?? ""
        terminal_session_id = (try? c.decode(String.self, forKey: .terminal_session_id)) ?? ""
        started_at = (try? c.decode(String.self, forKey: .started_at)) ?? ""
        updated_at = (try? c.decode(String.self, forKey: .updated_at)) ?? ""
        last_prompt = (try? c.decode(String.self, forKey: .last_prompt)) ?? ""
        thread_id = (try? c.decode(String.self, forKey: .thread_id)) ?? ""
        startedAtDate = Self.parseISO8601(started_at)
        updatedAtDate = Self.parseISO8601(updated_at)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(session_id, forKey: .session_id)
        try c.encode(agent, forKey: .agent)
        try c.encode(status, forKey: .status)
        try c.encode(project, forKey: .project)
        try c.encode(cwd, forKey: .cwd)
        try c.encode(terminal, forKey: .terminal)
        try c.encode(terminal_session_id, forKey: .terminal_session_id)
        try c.encode(started_at, forKey: .started_at)
        try c.encode(updated_at, forKey: .updated_at)
        try c.encode(last_prompt, forKey: .last_prompt)
        try c.encode(thread_id, forKey: .thread_id)
    }

    func statusColor(for skin: MonitorSkin) -> Color {
        skin.colors.statusColor(for: status)
    }

    var statusIcon: String {
        switch status {
        case "starting":  return "circle.dotted"
        case "working":   return "circle.fill"
        case "done":      return "checkmark.circle.fill"
        case "attention": return "exclamationmark.triangle.fill"
        default:          return "circle"
        }
    }

    var displayAgent: String {
        agent == "codex" ? "Codex" : "Claude"
    }

    var elapsedString: String {
        guard let start = startedAtDate else { return "" }
        let elapsed = Date().timeIntervalSince(start)
        if elapsed < 60 { return "\(Int(elapsed))s" }
        if elapsed < 3600 { return "\(Int(elapsed / 60))m" }
        return "\(Int(elapsed / 3600))h \(Int((elapsed.truncatingRemainder(dividingBy: 3600)) / 60))m"
    }

    var isStale: Bool {
        guard let updated = updatedAtDate else { return false }
        return Date().timeIntervalSince(updated) > 600 // 10 minutes
    }
}

// MARK: - Permission Model

struct PermissionInfo: Codable, Equatable, Identifiable {
    let request_id: String
    let session_id: String
    let tool_name: String
    let display: String
    let tool_input: String
    let timestamp: String
    let pid: String?  // legacy, kept for decode compat

    var id: String { request_id }

    enum CodingKeys: String, CodingKey {
        case request_id, session_id, tool_name, display, tool_input, timestamp, pid
    }

    init(requestId: String, sessionId: String, toolName: String, display: String,
         toolInput: String, timestamp: String, pid: String?) {
        request_id = requestId
        session_id = sessionId
        tool_name = toolName
        self.display = display
        tool_input = toolInput
        self.timestamp = timestamp
        self.pid = pid
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        request_id = try c.decodeIfPresent(String.self, forKey: .request_id) ?? ""
        session_id = try c.decodeIfPresent(String.self, forKey: .session_id) ?? ""
        tool_name = try c.decodeIfPresent(String.self, forKey: .tool_name) ?? "Unknown"
        display = try c.decodeIfPresent(String.self, forKey: .display) ?? ""
        tool_input = try c.decodeIfPresent(String.self, forKey: .tool_input) ?? ""
        timestamp = try c.decodeIfPresent(String.self, forKey: .timestamp) ?? ""
        pid = try c.decodeIfPresent(String.self, forKey: .pid)
    }

    var toolIcon: String {
        switch tool_name {
        case "Bash":  return "terminal"
        case "Edit":  return "pencil"
        case "Write": return "doc.badge.plus"
        case "Read":  return "doc.text"
        case "Glob":  return "magnifyingglass"
        case "Grep":  return "text.magnifyingglass"
        default:      return "gearshape"
        }
    }
}

// MARK: - Permission Socket Server

class PermissionSocketServer {
    static let shared = PermissionSocketServer()
    private let socketPath = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/monitor/monitor.sock").path
    private var serverFd: Int32 = -1
    private var ownsSocketPath = false
    private let queue = DispatchQueue(label: "monitor.socket", qos: .userInteractive)
    private let cleanupQueue = DispatchQueue(label: "monitor.socket.cleanup", qos: .utility)
    private struct PendingClient {
        let fd: Int32
        let sessionId: String
        let deadline: Date
    }
    // Request IDs allow parallel permission prompts within one agent session.
    private var pendingClients: [String: PendingClient] = [:]
    private let lock = NSLock()
    private var cleanupTimer: DispatchSourceTimer?

    func start() {
        // Clean up stale socket
        unlink(socketPath)

        serverFd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard serverFd >= 0 else {
            NSLog("[AgentMonitor] Socket: failed to create socket")
            return
        }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        socketPath.withCString { cstr in
            withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
                let raw = UnsafeMutableRawPointer(ptr)
                raw.copyMemory(from: cstr, byteCount: min(strlen(cstr) + 1, 104))
            }
        }

        let bindResult = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                bind(serverFd, sockPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bindResult == 0 else {
            NSLog("[AgentMonitor] Socket: bind failed: %d", errno)
            Darwin.close(serverFd)
            serverFd = -1
            return
        }
        ownsSocketPath = true

        // Restrict socket to owner only
        chmod(socketPath, 0o600)

        guard listen(serverFd, 5) == 0 else {
            NSLog("[AgentMonitor] Socket: listen failed")
            Darwin.close(serverFd)
            serverFd = -1
            if ownsSocketPath {
                unlink(socketPath)
                ownsSocketPath = false
            }
            return
        }

        NSLog("[AgentMonitor] Socket: listening on %@", socketPath)

        // Accept connections in background
        queue.async { [weak self] in
            self?.acceptLoop()
        }
        // The accept loop blocks its serial queue, so expiration must run on a
        // separate queue or abandoned permission clients would remain open.
        let timer = DispatchSource.makeTimerSource(queue: cleanupQueue)
        timer.schedule(deadline: .now() + 30, repeating: 30)
        timer.setEventHandler { [weak self] in self?.expirePendingClients() }
        timer.resume()
        cleanupTimer = timer
    }

    private func acceptLoop() {
        while serverFd >= 0 {
            var clientAddr = sockaddr_un()
            var clientLen = socklen_t(MemoryLayout<sockaddr_un>.size)
            let clientFd = withUnsafeMutablePointer(to: &clientAddr) { ptr in
                ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                    accept(serverFd, sockPtr, &clientLen)
                }
            }
            guard clientFd >= 0 else { continue }

            var noSigPipe: Int32 = 1
            _ = setsockopt(
                clientFd, SOL_SOCKET, SO_NOSIGPIPE,
                &noSigPipe, socklen_t(MemoryLayout<Int32>.size)
            )
            do {
                // Bound clients before frame parsing. The pending-client deadline
                // below only begins after a complete request has been decoded.
                try IPCFrame.setReceiveTimeout(on: clientFd, seconds: 10)
            } catch {
                NSLog("[AgentMonitor] Socket: failed to set request timeout: %@", error.localizedDescription)
                Darwin.close(clientFd)
                continue
            }

            // Handle each client in its own dispatch
            DispatchQueue.global(qos: .userInteractive).async { [weak self] in
                self?.handleClient(fd: clientFd)
            }
        }
    }

    private func handleClient(fd: Int32) {
        let data: Data
        do {
            data = try IPCFrame.read(from: fd)
        } catch {
            NSLog("[AgentMonitor] Socket: invalid request frame: %@", error.localizedDescription)
            Darwin.close(fd)
            return
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String,
              type == "permission_request",
              (json["protocol_version"] as? Int) == 1,
              let requestId = json["request_id"] as? String,
              let sessionId = json["session_id"] as? String,
              !requestId.isEmpty else {
            Darwin.close(fd)
            return
        }

        NSLog("[AgentMonitor] Socket: permission request %@ from session %@", requestId, sessionId)

        // Store the client fd — keep the connection open until user responds
        lock.lock()
        if let old = pendingClients[requestId] {
            Darwin.close(old.fd)
        }
        let requestedTimeout = (json["timeout_seconds"] as? Double) ?? 300
        let timeout = min(max(requestedTimeout, 1), 600)
        pendingClients[requestId] = PendingClient(
            fd: fd,
            sessionId: sessionId,
            deadline: Date().addingTimeInterval(timeout + 5)
        )
        lock.unlock()
    }

    private func expirePendingClients() {
        let now = Date()
        lock.lock()
        let expired = pendingClients.filter { $0.value.deadline <= now }
        for (requestId, client) in expired {
            pendingClients.removeValue(forKey: requestId)
            Darwin.close(client.fd)
            NSLog("[AgentMonitor] Socket: expired permission request %@", requestId)
        }
        lock.unlock()
    }

    @discardableResult
    func respond(requestId: String, decision: String) -> Bool {
        lock.lock()
        guard let client = pendingClients.removeValue(forKey: requestId) else {
            lock.unlock()
            NSLog("[AgentMonitor] Socket: no pending client for request %@", requestId)
            return false
        }
        lock.unlock()

        do {
            let responseData = try JSONSerialization.data(withJSONObject: ["decision": decision])
            try IPCFrame.write(responseData, to: client.fd)
        } catch {
            NSLog("[AgentMonitor] Socket: response failed for %@: %@", requestId, error.localizedDescription)
            Darwin.close(client.fd)
            return false
        }
        Darwin.close(client.fd)
        NSLog("[AgentMonitor] Socket: sent %@ to request %@ (session %@)", decision, requestId, client.sessionId)
        return true
    }

    func stop() {
        cleanupTimer?.cancel()
        cleanupTimer = nil
        if serverFd >= 0 {
            Darwin.close(serverFd)
            serverFd = -1
        }
        // A process that lost the singleton race never bound this path and must
        // not unlink the active instance's socket during its termination callback.
        if ownsSocketPath {
            unlink(socketPath)
            ownsSocketPath = false
        }
        lock.lock()
        for (_, client) in pendingClients {
            Darwin.close(client.fd)
        }
        pendingClients.removeAll()
        lock.unlock()
    }
}

/// Find the current WezTerm Unix socket. The monitor process may have been
/// launched with one socket that is now stale (WezTerm restarted), so we
/// resolve the newest gui-sock-* file at call time.
func currentWezTermSocket() -> String? {
    let dir = FileManager.default.homeDirectoryForCurrentUser.path + "/.local/share/wezterm"
    guard let entries = try? FileManager.default.contentsOfDirectory(atPath: dir) else { return nil }
    var newest: (path: String, mtime: Date)?
    for entry in entries where entry.hasPrefix("gui-sock-") {
        let full = "\(dir)/\(entry)"
        if let attrs = try? FileManager.default.attributesOfItem(atPath: full),
           let mtime = attrs[.modificationDate] as? Date {
            if newest == nil || mtime > newest!.mtime { newest = (full, mtime) }
        }
    }
    return newest?.path
}

/// Environment used for `wezterm cli` with the current socket.
func wezTermEnvironment() -> [String: String] {
    var environment = ProcessInfo.processInfo.environment
    if let socket = currentWezTermSocket() {
        environment["WEZTERM_UNIX_SOCKET"] = socket
    }
    return environment
}

func runWezTermCLI(arguments: [String], timeout: TimeInterval = 3) -> ProcessResult? {
    try? ProcessRunner.run(
        executableURL: URL(fileURLWithPath: "/usr/bin/env"),
        arguments: ["wezterm", "cli"] + arguments,
        environment: wezTermEnvironment(),
        timeout: timeout,
        maximumOutputBytes: 512 * 1024
    )
}

// MARK: - Session Reader (polls directory)

class SessionReader: ObservableObject {
    @Published var sessions: [SessionInfo] = []
    @Published var permissions: [String: [PermissionInfo]] = [:]
    private var timer: Timer?
    private var livenessTimer: Timer?
    private var discoveryTimer: Timer?
    private var codexSyncTimer: Timer?
    private var isPruning = false
    private var isDiscovering = false
    private let discoveryLock = NSLock()
    private let scanQueue = DispatchQueue(label: "monitor.sessions.scan", qos: .utility)
    private var sessionsDirFD: CInt = -1
    private var sessionsWatcher: DispatchSourceFileSystemObject?
    private var codexLogPathsByThreadID: [String: String] = [:]
    /// Incremental-read state for codex rollout logs, keyed by absolute path.
    /// These files are append-only and can reach tens of MB; re-reading and
    /// re-parsing every one on every 5s tick was allocating hundreds of MB per
    /// minute to recover three fields that never change for finished sessions.
    /// `offset` is always a newline boundary so a partially-written trailing
    /// line is re-read whole on the next tick rather than lost.
    private struct CodexLogCursor {
        var offset: UInt64
        var mtime: Date
        /// Accumulated last-wins state. Kept even when `updatedAt` is still
        /// empty so a `lastPrompt` seen in an early chunk survives to the tick
        /// that finally reads a task_started/task_complete.
        var snapshot: CodexLogSnapshot?
        /// Matches the original contract: no timestamp yet means no usable read.
        var returnable: CodexLogSnapshot? {
            guard let snapshot, !snapshot.updatedAt.isEmpty else { return nil }
            return snapshot
        }
    }
    private var codexLogCursors: [String: CodexLogCursor] = [:]

    let sessionsDir: String = {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/.claude/monitor/sessions"
    }()

    let codexSessionsDir: String = {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/.codex/sessions"
    }()

    init() {
        ensureSessionsDirExists()
        readSessions()
        discoverSessions() // One-time startup pass to find sessions hooks missed
        syncCodexSessionsFromLogs()
        startWatchingSessionsDir()
        timer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: true) { [weak self] _ in
            self?.readSessions()
        }
        livenessTimer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { [weak self] _ in
            guard let self = self, !self.isPruning else { return }
            self.pruneDeadSessions()
        }
        // Re-discover sessions periodically to catch any that hooks missed
        discoveryTimer = Timer.scheduledTimer(withTimeInterval: 60.0, repeats: true) { [weak self] _ in
            self?.discoverSessions()
        }
        codexSyncTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            self?.syncCodexSessionsFromLogs()
        }
    }

    deinit {
        timer?.invalidate()
        livenessTimer?.invalidate()
        discoveryTimer?.invalidate()
        codexSyncTimer?.invalidate()
        sessionsWatcher?.cancel()
    }

    private func ensureSessionsDirExists() {
        let directory = URL(fileURLWithPath: sessionsDir, isDirectory: true)
        do {
            try SessionFileStore.repairPermissions(in: directory)
        } catch {
            NSLog("[AgentMonitor] Session store setup failed: %@", error.localizedDescription)
        }
    }

    private func startWatchingSessionsDir() {
        ensureSessionsDirExists()
        sessionsDirFD = open(sessionsDir, O_EVTONLY)
        guard sessionsDirFD >= 0 else { return }

        sessionsWatcher = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: sessionsDirFD,
            eventMask: [.write, .delete, .extend, .rename],
            queue: scanQueue
        )
        sessionsWatcher?.setEventHandler { [weak self] in
            self?.readSessions()
        }
        sessionsWatcher?.setCancelHandler { [fd = sessionsDirFD] in
            if fd >= 0 { Darwin.close(fd) }
        }
        sessionsWatcher?.resume()
    }

    @discardableResult
    func respondToPermission(sessionId: String, requestId: String, decision: String) -> Bool {
        // Send response through the socket server
        guard PermissionSocketServer.shared.respond(requestId: requestId, decision: decision) else {
            // The permission file can become visible just before its socket is
            // registered. Keep the card available so the decision is not lost.
            return false
        }

        // Remove the permission card (delay for "terminal" so Claude Code can show its dialog)
        let filename = requestId.isEmpty
            ? "\(sessionId).permission"
            : "\(sessionId).\(requestId).permission"
        let permFile = "\(sessionsDir)/\(filename)"
        if decision == "terminal" {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                try? FileManager.default.removeItem(atPath: permFile)
            }
        } else {
            try? FileManager.default.removeItem(atPath: permFile)
        }
        return true
    }

    private func removePermissionFiles(sessionId: String) {
        guard let files = try? FileManager.default.contentsOfDirectory(atPath: sessionsDir) else { return }
        let prefix = "\(sessionId)."
        for file in files where file == "\(sessionId).permission"
            || (file.hasPrefix(prefix) && file.hasSuffix(".permission")) {
            try? FileManager.default.removeItem(atPath: "\(sessionsDir)/\(file)")
        }
    }

    /// Remove session files whose TTY no longer has any processes (terminal tab closed)
    func pruneDeadSessions() {
        let currentSessions = sessions
        guard !currentSessions.isEmpty else { return }

        // Age-based prune for finished sessions the TTY/pane logic below can never
        // reclaim. Two kinds qualify. Codex writes one file per thread
        // (codex-<thread_id>), but many threads share a single terminal tab, so
        // liveness alone never frees them — the tab stays open for days. And
        // anything spawned from a GUI app rather than a terminal (Tugboat asking
        // `claude -p` for a port description) has no terminal_session_id at all, so
        // the maps below skip it entirely and one missed SessionEnd strands the
        // file forever. Both age out on the same clock.
        let staleMaxAge: TimeInterval = 24 * 60 * 60
        for session in currentSessions where session.status == "done"
            && (session.agent == "codex" || session.terminal_session_id.isEmpty) {
            guard let updated = session.updatedAtDate,
                  Date().timeIntervalSince(updated) > staleMaxAge else { continue }
            let path = "\(sessionsDir)/\(session.session_id).json"
            _ = try? SessionFileStore.remove(at: URL(fileURLWithPath: path))
            removePermissionFiles(sessionId: session.session_id)
            NSLog("[AgentMonitor] Pruned session %@ (%@) — done >24h ago, no terminal to reclaim it",
                  session.session_id, session.agent)
        }

        // Build map: ttyName -> [session_id]
        var ttyMap: [String: [String]] = [:]
        var wezPaneMap: [String: [String]] = [:]  // paneId -> [session_id]
        var itermMap: [String: [String]] = [:]    // iTerm2 unique id -> [session_id]
        for session in currentSessions {
            guard !session.terminal_session_id.isEmpty else { continue }
            if session.terminal == "terminal" {
                let ttyName = session.terminal_session_id.replacingOccurrences(of: "/dev/", with: "")
                // Sanitize: TTY names are alphanumeric (e.g., "ttys017")
                guard ttyName == ttyName.filter({ $0.isLetter || $0.isNumber }) else { continue }
                ttyMap[ttyName, default: []].append(session.session_id)
            } else if session.terminal == "wezterm" {
                // Sanitize: pane IDs are numeric
                guard session.terminal_session_id == session.terminal_session_id.filter({ $0.isNumber }) else { continue }
                wezPaneMap[session.terminal_session_id, default: []].append(session.session_id)
            } else if session.terminal == "iterm2" {
                let uniqueId: String
                if let suffix = session.terminal_session_id.split(separator: ":", maxSplits: 1).last,
                   session.terminal_session_id.contains(":") {
                    uniqueId = String(suffix)
                } else {
                    uniqueId = session.terminal_session_id
                }
                guard !uniqueId.isEmpty else { continue }
                // Sanitize: iTerm2 unique IDs are UUIDs (hex + dashes)
                guard uniqueId == uniqueId.filter({ $0.isHexDigit || $0 == "-" }) else { continue }
                itermMap[uniqueId, default: []].append(session.session_id)
            }
        }
        guard !ttyMap.isEmpty || !wezPaneMap.isEmpty || !itermMap.isEmpty else { return }

        isPruning = true
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self = self else { return }

            var deadTTYs = Set<String>()
            for tty in ttyMap.keys {
                guard let result = try? ProcessRunner.run(
                    executableURL: URL(fileURLWithPath: "/bin/ps"),
                    arguments: ["-t", tty, "-o", "pid="],
                    timeout: 2,
                    maximumOutputBytes: 64 * 1024
                ), !result.timedOut else { continue }
                let output = (String(data: result.standardOutput, encoding: .utf8) ?? "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if output.isEmpty { deadTTYs.insert(tty) }
            }

            for tty in deadTTYs {
                if let sids = ttyMap[tty] {
                    for sid in sids {
                        let path = "\(self.sessionsDir)/\(sid).json"
                        _ = try? SessionFileStore.remove(at: URL(fileURLWithPath: path))
                        self.removePermissionFiles(sessionId: sid)
                        NSLog("[AgentMonitor] Pruned session %@ — TTY %@ gone", sid, tty)
                    }
                }
            }

            // Prune dead WezTerm panes
            if !wezPaneMap.isEmpty {
                if let result = runWezTermCLI(arguments: ["list", "--format", "json"]),
                   result.succeeded {
                    var livePanes = Set<String>()
                    if let panes = try? JSONSerialization.jsonObject(with: result.standardOutput) as? [[String: Any]] {
                        for pane in panes {
                            if let paneId = pane["pane_id"] as? Int {
                                livePanes.insert(String(paneId))
                            }
                        }
                    }
                    for (paneId, sids) in wezPaneMap {
                        if !livePanes.contains(paneId) {
                            for sid in sids {
                                let path = "\(self.sessionsDir)/\(sid).json"
                                _ = try? SessionFileStore.remove(at: URL(fileURLWithPath: path))
                                self.removePermissionFiles(sessionId: sid)
                                NSLog("[AgentMonitor] Pruned session %@ — WezTerm pane %@ gone", sid, paneId)
                            }
                        }
                    }
                }
            }

            // Prune dead iTerm2 sessions
            if !itermMap.isEmpty {
                var liveItermIds = Set<String>()
                if NSRunningApplication.runningApplications(withBundleIdentifier: "com.googlecode.iterm2").first != nil {
                    let script = """
                    tell application "iTerm2"
                        set output to ""
                        repeat with w in windows
                            repeat with t in tabs of w
                                repeat with s in sessions of t
                                    set output to output & (unique id of s) & linefeed
                                end repeat
                            end repeat
                        end repeat
                        return output
                    end tell
                    """
                    if let appleScript = NSAppleScript(source: script) {
                        var error: NSDictionary?
                        let result = appleScript.executeAndReturnError(&error)
                        if let output = result.stringValue {
                            for line in output.split(separator: "\n") {
                                let uniqueId = String(line).trimmingCharacters(in: .whitespacesAndNewlines)
                                guard !uniqueId.isEmpty else { continue }
                                liveItermIds.insert(uniqueId)
                            }
                        }
                    }
                }

                for (uniqueId, sids) in itermMap {
                    if !liveItermIds.contains(uniqueId) {
                        for sid in sids {
                            let path = "\(self.sessionsDir)/\(sid).json"
                            _ = try? SessionFileStore.remove(at: URL(fileURLWithPath: path))
                            self.removePermissionFiles(sessionId: sid)
                            NSLog("[AgentMonitor] Pruned session %@ — iTerm2 session %@ gone", sid, uniqueId)
                        }
                    }
                }
            }

            DispatchQueue.main.async {
                self.isPruning = false
            }
        }
    }

    func readSessions() {
        scanQueue.async { [weak self] in
            self?.readSessionsOnScanQueue()
        }
    }

    private func readSessionsOnScanQueue() {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(atPath: sessionsDir) else {
            DispatchQueue.main.async {
                guard !self.sessions.isEmpty || !self.permissions.isEmpty else { return }
                self.sessions = []
                self.permissions = [:]
            }
            return
        }

        var loaded: [SessionInfo] = []
        var loadedPerms: [String: [PermissionInfo]] = [:]

        for file in files {
            if file.hasSuffix(".json") {
                let path = "\(sessionsDir)/\(file)"
                guard let data = fm.contents(atPath: path) else { continue }
                do {
                    let session = try JSONDecoder().decode(SessionInfo.self, from: data)
                    loaded.append(session)
                } catch {
                    NSLog("[AgentMonitor] Failed to decode %@: %@", file, error.localizedDescription)
                    _ = try? SessionFileStore.quarantine(at: URL(fileURLWithPath: path))
                }
            } else if file.hasSuffix(".permission") {
                let legacySessionId = String(file.dropLast(".permission".count)).split(separator: ".").first.map(String.init) ?? ""
                let path = "\(sessionsDir)/\(file)"
                guard let data = fm.contents(atPath: path) else { continue }
                if let decoded = try? JSONDecoder().decode(PermissionInfo.self, from: data) {
                    let sessionId = decoded.session_id.isEmpty ? legacySessionId : decoded.session_id
                    let requestId = decoded.request_id.isEmpty ? sessionId : decoded.request_id
                    let permission = PermissionInfo(
                        requestId: requestId,
                        sessionId: sessionId,
                        toolName: decoded.tool_name,
                        display: decoded.display,
                        toolInput: decoded.tool_input,
                        timestamp: decoded.timestamp,
                        pid: decoded.pid
                    )
                    loadedPerms[sessionId, default: []].append(permission)
                } else {
                    _ = try? SessionFileStore.quarantine(at: URL(fileURLWithPath: path))
                }
            }
        }

        // Sort: attention first, then working, then starting, then done
        let order: [String: Int] = ["attention": 0, "working": 1, "starting": 2, "done": 3]
        loaded.sort { (order[$0.status] ?? 9) < (order[$1.status] ?? 9) }

        for sessionId in loadedPerms.keys {
            loadedPerms[sessionId]?.sort { $0.timestamp < $1.timestamp }
        }

        DispatchQueue.main.async {
            guard loaded != self.sessions || loadedPerms != self.permissions else { return }
            self.sessions = loaded
            self.permissions = loadedPerms
        }
    }

    private struct CodexLogSnapshot {
        let status: String
        let updatedAt: String
        let lastPrompt: String
    }

    func syncCodexSessionsFromLogs() {
        scanQueue.async { [weak self] in
            self?.syncCodexSessionsFromLogsOnScanQueue()
        }
    }

    private func syncCodexSessionsFromLogsOnScanQueue() {
        let codexSessions = DispatchQueue.main.sync {
            self.sessions.filter { $0.agent == "codex" && !$0.thread_id.isEmpty }
        }
        guard !codexSessions.isEmpty else { return }

        var didUpdate = false
        for session in codexSessions {
            guard let logPath = codexLogPath(for: session.thread_id),
                  let snapshot = readCodexLogSnapshot(at: logPath) else { continue }

            let needsStatusUpdate = session.status != snapshot.status
            let needsPromptUpdate = !snapshot.lastPrompt.isEmpty && session.last_prompt != snapshot.lastPrompt
            let needsTimestampUpdate = !snapshot.updatedAt.isEmpty && session.updated_at != snapshot.updatedAt
            guard needsStatusUpdate || needsPromptUpdate || needsTimestampUpdate else { continue }

            let sessionPath = "\(sessionsDir)/\(session.session_id).json"
            let fileURL = URL(fileURLWithPath: sessionPath)
            do {
                let updated = try SessionFileStore.updateJSONObjectIfPresent(at: fileURL) { json in
                    json["status"] = snapshot.status
                    json["agent"] = "codex"
                    json["thread_id"] = session.thread_id
                    if !snapshot.updatedAt.isEmpty {
                        json["updated_at"] = snapshot.updatedAt
                    }
                    if !snapshot.lastPrompt.isEmpty {
                        json["last_prompt"] = snapshot.lastPrompt
                    }
                }
                didUpdate = didUpdate || updated
            } catch {
                NSLog("[AgentMonitor] Codex session update failed for %@: %@", session.session_id, error.localizedDescription)
            }
        }

        if didUpdate {
            readSessionsOnScanQueue()
        }
    }

    private func codexLogPath(for threadID: String) -> String? {
        if let cached = codexLogPathsByThreadID[threadID],
           FileManager.default.fileExists(atPath: cached) {
            return cached
        }

        let fm = FileManager.default
        guard let enumerator = fm.enumerator(atPath: codexSessionsDir) else { return nil }
        let suffix = "\(threadID).jsonl"
        while let relativePath = enumerator.nextObject() as? String {
            guard relativePath.hasSuffix(suffix) else { continue }
            let absolutePath = "\(codexSessionsDir)/\(relativePath)"
            codexLogPathsByThreadID[threadID] = absolutePath
            return absolutePath
        }

        return nil
    }

    /// Reads only the bytes appended since the last call. Every field below is
    /// last-wins, so folding new lines into the previous snapshot is exactly
    /// equivalent to re-parsing the whole file — just without the re-parse.
    /// Callers must stay on scanQueue; `codexLogCursors` is not synchronized.
    private func readCodexLogSnapshot(at path: String) -> CodexLogSnapshot? {
        let attrs = try? FileManager.default.attributesOfItem(atPath: path)
        let size = (attrs?[.size] as? NSNumber)?.uint64Value ?? 0
        let mtime = (attrs?[.modificationDate] as? Date) ?? Date.distantPast

        var cursor = codexLogCursors[path] ?? CodexLogCursor(offset: 0, mtime: .distantPast, snapshot: nil)

        // Truncated or rotated underneath us — start over rather than parse garbage.
        if size < cursor.offset {
            cursor = CodexLogCursor(offset: 0, mtime: .distantPast, snapshot: nil)
        }

        // Nothing appended: hand back what we already parsed, at zero cost.
        // This is the common case — most tracked sessions are already done.
        if cursor.offset > 0 && size == cursor.offset && mtime == cursor.mtime {
            return cursor.returnable
        }

        guard let handle = FileHandle(forReadingAtPath: path) else { return cursor.returnable }
        defer { try? handle.close() }
        if cursor.offset > 0 {
            do { try handle.seek(toOffset: cursor.offset) } catch { return cursor.returnable }
        }
        guard let data = try? handle.readToEnd(), !data.isEmpty else {
            cursor.mtime = mtime
            codexLogCursors[path] = cursor
            return cursor.returnable
        }

        // Only consume through the final newline; a half-written last line stays
        // unconsumed and is picked up complete on a later tick.
        guard let lastNewline = data.lastIndex(of: UInt8(ascii: "\n")) else {
            cursor.mtime = mtime
            codexLogCursors[path] = cursor
            return cursor.returnable
        }
        let consumable = data[data.startIndex...lastNewline]
        let consumedCount = UInt64(consumable.count)

        guard let content = String(data: consumable, encoding: .utf8) else {
            cursor.offset += consumedCount
            cursor.mtime = mtime
            codexLogCursors[path] = cursor
            return cursor.returnable
        }

        var status = cursor.snapshot?.status ?? "working"
        var updatedAt = cursor.snapshot?.updatedAt ?? ""
        var lastPrompt = cursor.snapshot?.lastPrompt ?? ""

        for line in content.split(separator: "\n") {
            guard let lineData = line.data(using: .utf8),
                  let root = (try? JSONSerialization.jsonObject(with: lineData)) as? [String: Any],
                  let payload = root["payload"] as? [String: Any],
                  let type = payload["type"] as? String else { continue }

            let timestamp = (root["timestamp"] as? String) ?? updatedAt
            switch type {
            case "user_message":
                if let message = payload["message"] as? String {
                    lastPrompt = String(message.prefix(200))
                }
            case "task_started":
                status = "working"
                updatedAt = timestamp
            case "task_complete":
                status = "done"
                updatedAt = timestamp
            default:
                continue
            }
        }

        cursor.offset += consumedCount
        cursor.mtime = mtime
        cursor.snapshot = CodexLogSnapshot(status: status, updatedAt: updatedAt, lastPrompt: lastPrompt)
        codexLogCursors[path] = cursor
        return cursor.returnable
    }

    private func unambiguousCodexLogPath(in paths: [String]) -> String? {
        let uniquePaths = Array(Set(paths)).sorted()
        guard uniquePaths.count == 1 else { return nil }
        return uniquePaths[0]
    }

    private func codexThreadID(fromLogPath path: String) -> String? {
        guard let chunk = FileManager.default.contents(atPath: path),
              let firstLine = String(data: chunk, encoding: .utf8)?.split(separator: "\n").first,
              let data = String(firstLine).data(using: .utf8),
              let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              root["type"] as? String == "session_meta",
              let payload = root["payload"] as? [String: Any],
              let threadID = payload["id"] as? String,
              !threadID.isEmpty else { return nil }
        return threadID
    }

    /// Discover running Claude and Codex sessions that hooks/wrappers missed.
    /// Builds a TTY→terminal map from WezTerm/iTerm2, finds supported agents via ps, resolves cwd via lsof,
    /// and creates session files for any that aren't already tracked. Skips cwd=/ (launcher process artifact).
    func discoverSessions() {
        discoveryLock.lock()
        guard !isDiscovering else {
            discoveryLock.unlock()
            return
        }
        isDiscovering = true
        discoveryLock.unlock()

        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self = self else { return }
            defer {
                self.discoveryLock.lock()
                self.isDiscovering = false
                self.discoveryLock.unlock()
            }
            let now = ISO8601DateFormatter().string(from: Date())

            // --- Step 1: Build TTY → terminal info map ---
            // Maps "/dev/ttysNNN" → (terminalType, terminalSessionId)
            var ttyTerminalMap: [String: (String, String)] = [:]

            // WezTerm: pane_id + tty_name
            if let result = runWezTermCLI(arguments: ["list", "--format", "json"]),
               result.succeeded {
                if let panes = try? JSONSerialization.jsonObject(with: result.standardOutput) as? [[String: Any]] {
                    for pane in panes {
                        if let paneId = pane["pane_id"] as? Int,
                           let ttyName = pane["tty_name"] as? String, !ttyName.isEmpty {
                            ttyTerminalMap[ttyName] = ("wezterm", String(paneId))
                        }
                    }
                }
            }

            // iTerm2: check for running app, get session IDs via AppleScript
            if NSRunningApplication.runningApplications(withBundleIdentifier: "com.googlecode.iterm2").first != nil {
                let script = """
                tell application "iTerm2"
                    set output to ""
                    repeat with w in windows
                        repeat with t in tabs of w
                            repeat with s in sessions of t
                                set output to output & (tty of s) & "|" & (unique id of s) & linefeed
                            end repeat
                        end repeat
                    end repeat
                    return output
                end tell
                """
                if let appleScript = NSAppleScript(source: script) {
                    var error: NSDictionary?
                    let result = appleScript.executeAndReturnError(&error)
                    if let output = result.stringValue {
                        for line in output.split(separator: "\n") {
                            let parts = line.split(separator: "|", maxSplits: 1)
                            if parts.count == 2 {
                                let tty = String(parts[0])
                                let sessionId = String(parts[1])
                                // Don't overwrite WezTerm entries (unlikely overlap, but just in case)
                                if ttyTerminalMap[tty] == nil {
                                    ttyTerminalMap[tty] = ("iterm2", sessionId)
                                }
                            }
                        }
                    }
                }
            }

            // --- Step 2: Collect already-tracked terminal session IDs ---
            var trackedTTYs = Set<String>()         // "/dev/ttysNNN" for Terminal.app
            var trackedWezPanes = Set<String>()      // pane IDs for WezTerm
            var trackedItermIds = Set<String>()       // "w0t0p0:GUID" for iTerm2
            let currentSessions = DispatchQueue.main.sync { self.sessions }
            for session in currentSessions {
                guard !session.terminal_session_id.isEmpty else { continue }
                switch session.terminal {
                case "wezterm":  trackedWezPanes.insert(session.terminal_session_id)
                case "iterm2":   trackedItermIds.insert(session.terminal_session_id)
                case "terminal": trackedTTYs.insert(session.terminal_session_id)
                default: break
                }
            }

            // --- Step 3: Find supported agent processes with TTYs ---
            // Use comm= so each row has a stable executable name/path without argv noise.
            guard let psResult = try? ProcessRunner.run(
                executableURL: URL(fileURLWithPath: "/bin/ps"),
                arguments: ["-eo", "pid=,tty=,comm="],
                timeout: 3,
                maximumOutputBytes: 512 * 1024
            ), psResult.succeeded else { return }
            let psOutput = String(data: psResult.standardOutput, encoding: .utf8) ?? ""

            struct CandidateProcess {
                let pid: String
                let tty: String // "/dev/ttysNNN"
                let agent: String
            }

            var candidates: [CandidateProcess] = []
            var seenTTYs = Set<String>() // only take one tracked agent process per TTY

            for line in psOutput.split(separator: "\n") {
                let parts = line.split(maxSplits: 2, whereSeparator: \.isWhitespace)
                guard parts.count == 3 else { continue }
                let pid = String(parts[0])
                let ttyShort = String(parts[1])
                let comm = URL(fileURLWithPath: String(parts[2])).lastPathComponent

                let agent: String
                if comm == "claude" {
                    agent = "claude"
                } else if comm == "codex" || comm.hasSuffix("/codex") {
                    agent = "codex"
                } else {
                    continue
                }
                guard ttyShort != "??" && !ttyShort.isEmpty else { continue }

                let ttyPath = "/dev/\(ttyShort)"
                guard !seenTTYs.contains(ttyPath) else { continue }
                seenTTYs.insert(ttyPath)
                candidates.append(CandidateProcess(pid: pid, tty: ttyPath, agent: agent))
            }

            guard !candidates.isEmpty else { return }

            // --- Step 4: Filter candidates by already-tracked status ---
            struct DiscoveryCandidate {
                let pid: String
                let tty: String
                let agent: String
                let terminalType: String
                let terminalSessionId: String
            }

            var filteredCandidates: [DiscoveryCandidate] = []
            for candidate in candidates {
                let terminalType: String
                let terminalSessionId: String
                if let (tType, tSid) = ttyTerminalMap[candidate.tty] {
                    terminalType = tType
                    terminalSessionId = tSid
                } else {
                    terminalType = "terminal"
                    terminalSessionId = candidate.tty
                }

                // Check if already tracked
                var isTracked = false
                switch terminalType {
                case "wezterm":
                    isTracked = trackedWezPanes.contains(terminalSessionId)
                case "iterm2":
                    let discoveredId = terminalSessionId
                    isTracked = trackedItermIds.contains(where: { $0.hasSuffix(discoveredId) || $0 == discoveredId })
                case "terminal":
                    isTracked = trackedTTYs.contains(terminalSessionId)
                default: break
                }
                if !isTracked {
                    filteredCandidates.append(DiscoveryCandidate(pid: candidate.pid, tty: candidate.tty, agent: candidate.agent, terminalType: terminalType, terminalSessionId: terminalSessionId))
                }
            }

            guard !filteredCandidates.isEmpty else { return }

            // --- Step 5: Batch-resolve cwds and Codex session logs via single lsof call ---
            let pidList = filteredCandidates.map { $0.pid }.joined(separator: ",")
            guard let lsofResult = try? ProcessRunner.run(
                executableURL: URL(fileURLWithPath: "/usr/sbin/lsof"),
                arguments: ["-p", pidList, "-Fnf"],
                timeout: 3,
                maximumOutputBytes: 512 * 1024
            ), !lsofResult.timedOut else { return }
            let lsofOutput = String(data: lsofResult.standardOutput, encoding: .utf8) ?? ""

            // Parse multi-process lsof output: "p<PID>\nf<fd>\nn<path>\np<PID>\n..."
            var pidToCwd: [String: String] = [:]
            var pidToCodexLogPaths: [String: [String]] = [:]
            var currentPid: String?
            var currentFD: String?
            for line in lsofOutput.split(separator: "\n") {
                if line.hasPrefix("p") {
                    currentPid = String(line.dropFirst())
                    currentFD = nil
                } else if line.hasPrefix("f") {
                    currentFD = String(line.dropFirst())
                } else if line.hasPrefix("n"), let pid = currentPid {
                    let path = String(line.dropFirst())
                    if currentFD == "cwd" {
                        pidToCwd[pid] = path
                    } else if path.contains("/.codex/sessions/"), path.hasSuffix(".jsonl") {
                        pidToCodexLogPaths[pid, default: []].append(path)
                    }
                }
            }

            // --- Step 6: Create session files for untracked sessions ---
            var created = 0
            for candidate in filteredCandidates {
                let cwd = pidToCwd[candidate.pid] ?? ""

                // Skip cwd=/ (launcher process artifact) and empty
                guard !cwd.isEmpty && cwd != "/" else { continue }

                let project = (cwd as NSString).lastPathComponent
                let sid = "discovered-\(candidate.agent)-\(candidate.pid)"
                let codexLogPath = candidate.agent == "codex" ? self.unambiguousCodexLogPath(in: pidToCodexLogPaths[candidate.pid] ?? []) : nil
                let threadID = codexLogPath.flatMap { self.codexThreadID(fromLogPath: $0) } ?? ""

                // Sanitize for file path safety
                let safeSid = sid.filter { $0.isLetter || $0.isNumber || $0 == "-" }
                guard safeSid == sid else { continue }

                // Create session file atomically
                let sessionData: [String: Any] = [
                    "session_id": sid,
                    "agent": candidate.agent,
                    "status": "working",
                    "project": project,
                    "cwd": cwd,
                    "terminal": candidate.terminalType,
                    "terminal_session_id": candidate.terminalSessionId,
                    "started_at": now,
                    "updated_at": now,
                    "last_prompt": "",
                    "thread_id": threadID
                ]

                guard let jsonData = try? JSONSerialization.data(withJSONObject: sessionData, options: [.prettyPrinted, .sortedKeys]) else { continue }
                let sessionFile = "\(self.sessionsDir)/\(safeSid).json"
                do {
                    let object = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any] ?? [:]
                    if try SessionFileStore.createJSONObjectIfAbsent(object, at: URL(fileURLWithPath: sessionFile)) {
                        created += 1
                        NSLog("[AgentMonitor] Discovered %@ session: %@ (%@) on %@ %@", candidate.agent, project, sid, candidate.terminalType, candidate.terminalSessionId)
                    }
                } catch {
                    NSLog("[AgentMonitor] Discovery persistence failed for %@: %@", sid, error.localizedDescription)
                }
            }

            if created > 0 {
                NSLog("[AgentMonitor] Discovery found %d new session(s)", created)
                DispatchQueue.main.async {
                    self.readSessions()
                }
            }
        }
    }
}

// MARK: - Terminal Switcher

struct TerminalTarget {
    let terminal: String
    let sessionId: String
}

func currentTerminalTargetsByTTY() -> [String: TerminalTarget] {
    var ttyTerminalMap: [String: TerminalTarget] = [:]

    if let result = runWezTermCLI(arguments: ["list", "--format", "json"]),
       result.succeeded {
        if let panes = try? JSONSerialization.jsonObject(with: result.standardOutput) as? [[String: Any]] {
            for pane in panes {
                if let paneId = pane["pane_id"] as? Int,
                   let ttyName = pane["tty_name"] as? String, !ttyName.isEmpty {
                    ttyTerminalMap[ttyName] = TerminalTarget(terminal: "wezterm", sessionId: String(paneId))
                }
            }
        }
    }

    if NSRunningApplication.runningApplications(withBundleIdentifier: "com.googlecode.iterm2").first != nil {
        let script = """
        tell application "iTerm2"
            set output to ""
            repeat with w in windows
                repeat with t in tabs of w
                    repeat with s in sessions of t
                        set output to output & (tty of s) & "|" & (unique id of s) & linefeed
                    end repeat
                end repeat
            end repeat
            return output
        end tell
        """
        if let appleScript = NSAppleScript(source: script) {
            var error: NSDictionary?
            let result = appleScript.executeAndReturnError(&error)
            if let output = result.stringValue {
                for line in output.split(separator: "\n") {
                    let parts = line.split(separator: "|", maxSplits: 1)
                    if parts.count == 2 {
                        let tty = String(parts[0])
                        let sessionId = String(parts[1])
                        if ttyTerminalMap[tty] == nil {
                            ttyTerminalMap[tty] = TerminalTarget(terminal: "iterm2", sessionId: sessionId)
                        }
                    }
                }
            }
        }
    }

    return ttyTerminalMap
}

func codexLogPath(for threadID: String) -> String? {
    let home = FileManager.default.homeDirectoryForCurrentUser.path
    let codexSessionsDir = "\(home)/.codex/sessions"
    guard let enumerator = FileManager.default.enumerator(atPath: codexSessionsDir) else { return nil }
    let suffix = "\(threadID).jsonl"
    while let relativePath = enumerator.nextObject() as? String {
        guard relativePath.hasSuffix(suffix) else { continue }
        return "\(codexSessionsDir)/\(relativePath)"
    }
    return nil
}

func resolveTTYPath(forPid pid: String) -> String? {
    guard !pid.isEmpty, pid.allSatisfy(\.isNumber),
          let result = try? ProcessRunner.run(
            executableURL: URL(fileURLWithPath: "/bin/ps"),
            arguments: ["-o", "tty=", "-p", pid],
            timeout: 2,
            maximumOutputBytes: 4096
          ), result.succeeded else { return nil }
    let ttyShort = (String(data: result.standardOutput, encoding: .utf8) ?? "")
        .trimmingCharacters(in: .whitespacesAndNewlines)
    guard !ttyShort.isEmpty, ttyShort != "??" else { return nil }
    let sanitized = ttyShort.filter { $0.isLetter || $0.isNumber }
    guard sanitized == ttyShort else { return nil }
    return "/dev/\(ttyShort)"
}

func resolveLiveCodexTarget(threadID: String) -> TerminalTarget? {
    guard let logPath = codexLogPath(for: threadID) else { return nil }

    guard let lsofResult = try? ProcessRunner.run(
        executableURL: URL(fileURLWithPath: "/usr/sbin/lsof"),
        arguments: ["-t", logPath],
        timeout: 3,
        maximumOutputBytes: 64 * 1024
    ), !lsofResult.timedOut else { return nil }

    let pids = Set((String(data: lsofResult.standardOutput, encoding: .utf8) ?? "")
        .split(separator: "\n")
        .map { String($0).trimmingCharacters(in: .whitespaces) }
        .filter { !$0.isEmpty })
    guard pids.count == 1, let pid = pids.first,
          let ttyPath = resolveTTYPath(forPid: pid) else { return nil }

    let ttyTargets = currentTerminalTargetsByTTY()
    if let target = ttyTargets[ttyPath] {
        return target
    }
    return TerminalTarget(terminal: "terminal", sessionId: ttyPath)
}

func resolveLiveTarget(agent: String, cwd: String) -> TerminalTarget? {
    guard !cwd.isEmpty else { return nil }

    guard let psResult = try? ProcessRunner.run(
        executableURL: URL(fileURLWithPath: "/bin/ps"),
        arguments: ["-eo", "pid=,tty=,comm="],
        timeout: 3,
        maximumOutputBytes: 512 * 1024
    ), psResult.succeeded else { return nil }
    let psOutput = String(data: psResult.standardOutput, encoding: .utf8) ?? ""

    struct CandidateTTY {
        let pid: String
        let ttyPath: String
    }

    var candidates: [CandidateTTY] = []
    for line in psOutput.split(separator: "\n") {
        let parts = line.split(maxSplits: 2, whereSeparator: \.isWhitespace)
        guard parts.count == 3 else { continue }
        let pid = String(parts[0])
        let ttyShort = String(parts[1])
        let command = String(parts[2])
        let commandName = URL(fileURLWithPath: command).lastPathComponent
        guard (agent == "codex" && commandName == "codex")
            || (agent != "codex" && commandName == "claude") else { continue }
        guard !ttyShort.isEmpty, ttyShort != "??" else { continue }
        let sanitized = ttyShort.filter { $0.isLetter || $0.isNumber }
        guard sanitized == ttyShort else { continue }
        candidates.append(CandidateTTY(pid: pid, ttyPath: "/dev/\(ttyShort)"))
    }

    guard !candidates.isEmpty else { return nil }

    let pidList = candidates.map(\.pid).joined(separator: ",")
    guard let lsofResult = try? ProcessRunner.run(
        executableURL: URL(fileURLWithPath: "/usr/sbin/lsof"),
        arguments: ["-p", pidList, "-Fnf"],
        timeout: 3,
        maximumOutputBytes: 512 * 1024
    ), !lsofResult.timedOut else { return nil }
    let lsofOutput = String(data: lsofResult.standardOutput, encoding: .utf8) ?? ""

    var pidToCwd: [String: String] = [:]
    var currentPid: String?
    var currentFD: String?
    for line in lsofOutput.split(separator: "\n") {
        if line.hasPrefix("p") {
            currentPid = String(line.dropFirst())
            currentFD = nil
        } else if line.hasPrefix("f") {
            currentFD = String(line.dropFirst())
        } else if line.hasPrefix("n"), let pid = currentPid, currentFD == "cwd" {
            pidToCwd[pid] = String(line.dropFirst())
        }
    }

    let matchingTTYs = Set(candidates.filter { pidToCwd[$0.pid] == cwd }.map(\.ttyPath))
    guard matchingTTYs.count == 1, let ttyPath = matchingTTYs.first else { return nil }

    let ttyTargets = currentTerminalTargetsByTTY()
    if let target = ttyTargets[ttyPath] {
        return target
    }
    return TerminalTarget(terminal: "terminal", sessionId: ttyPath)
}

func persistTerminalTarget(sessionId: String, terminal: String, terminalSessionId: String) {
    let home = FileManager.default.homeDirectoryForCurrentUser.path
    let sessionFile = "\(home)/.claude/monitor/sessions/\(sessionId).json"
    let fileURL = URL(fileURLWithPath: sessionFile)
    do {
        _ = try SessionFileStore.updateJSONObjectIfPresent(at: fileURL) { json in
            json["terminal"] = terminal
            json["terminal_session_id"] = terminalSessionId
        }
    } catch {
        NSLog("[AgentMonitor] Failed to persist terminal target for %@: %@", sessionId, error.localizedDescription)
    }
}

func switchToResolvedTarget(_ target: TerminalTarget, cwd: String) {
    switch target.terminal {
    case "iterm2":
        switchToITerm2(sessionId: target.sessionId)
    case "wezterm":
        switchToWezTerm(paneId: target.sessionId)
    case "terminal":
        switchToTerminal(ttyPath: target.sessionId)
    default:
        switchByTerminalCwd(cwd: cwd)
    }
}

func switchToSession(_ session: SessionInfo) {
    NSLog("[AgentMonitor] switchToSession: terminal=\(session.terminal) tty=\(session.terminal_session_id) project=\(session.project)")
    DispatchQueue.global(qos: .userInitiated).async {
        let resolved: TerminalTarget?
        if session.agent == "codex", !session.thread_id.isEmpty,
           let liveTarget = resolveLiveCodexTarget(threadID: session.thread_id) {
            resolved = liveTarget
        } else {
            resolved = resolveLiveTarget(agent: session.agent, cwd: session.cwd)
        }

        if let resolved {
            persistTerminalTarget(
                sessionId: session.session_id,
                terminal: resolved.terminal,
                terminalSessionId: resolved.sessionId
            )
        }

        DispatchQueue.main.async {
            if let resolved {
                switchToResolvedTarget(resolved, cwd: session.cwd)
            } else if !session.terminal_session_id.isEmpty {
                switchToResolvedTarget(
                    TerminalTarget(terminal: session.terminal, sessionId: session.terminal_session_id),
                    cwd: session.cwd
                )
            } else {
                NSLog("[AgentMonitor] falling back to cwd switch (no terminal info)")
                switchByTerminalCwd(cwd: session.cwd)
            }
        }
    }
}

func switchToITerm2(sessionId: String) {
    // Session IDs can come from hooks ("w0t0p0:GUID") or startup discovery ("GUID").
    let uniqueId: String
    if let suffix = sessionId.split(separator: ":", maxSplits: 1).last, sessionId.contains(":") {
        uniqueId = String(suffix)
    } else {
        uniqueId = sessionId
    }

    // Sanitize: iTerm2 unique IDs are UUIDs (hex + dashes)
    let sanitized = uniqueId.filter { $0.isHexDigit || $0 == "-" }
    guard sanitized == uniqueId else {
        NSLog("[AgentMonitor] switchToITerm2: rejecting suspicious uniqueId: %@", uniqueId)
        return
    }

    let script = """
    tell application "iTerm2"
        activate
        repeat with w in windows
            repeat with t in tabs of w
                repeat with s in sessions of t
                    if unique id of s is "\(sanitized)" then
                        select t
                        return
                    end if
                end repeat
            end repeat
        end repeat
    end tell
    """

    if let appleScript = NSAppleScript(source: script) {
        var error: NSDictionary?
        appleScript.executeAndReturnError(&error)
    }
}

func switchToWezTerm(paneId: String) {
    // Bring WezTerm to front
    if let app = NSRunningApplication.runningApplications(withBundleIdentifier: "com.github.wez.wezterm").first {
        app.activate()
    }
    // Focus the specific pane via wezterm CLI
    DispatchQueue.global(qos: .userInitiated).async {
        _ = runWezTermCLI(arguments: ["activate-pane", "--pane-id", paneId])
    }
}

func switchToTerminal(ttyPath: String) {
    // Sanitize: TTY paths are /dev/ttysNNN
    let sanitized = ttyPath.filter { $0.isLetter || $0.isNumber || $0 == "/" }
    guard sanitized == ttyPath else {
        NSLog("[AgentMonitor] switchToTerminal: rejecting suspicious ttyPath: %@", ttyPath)
        return
    }

    // Match Terminal.app tab by its tty device path
    let script = """
    tell application "Terminal"
        activate
        repeat with w in windows
            repeat with t in tabs of w
                if tty of t is "\(sanitized)" then
                    set selected tab of w to t
                    set index of w to 1
                    return
                end if
            end repeat
        end repeat
    end tell
    """

    if let appleScript = NSAppleScript(source: script) {
        var error: NSDictionary?
        appleScript.executeAndReturnError(&error)
    }
}

func switchByTerminalCwd(cwd: String) {
    // Fallback: just activate the terminal app
    if let appleScript = NSAppleScript(source: "tell application \"Terminal\" to activate") {
        var error: NSDictionary?
        appleScript.executeAndReturnError(&error)
    }
}

// MARK: - Session Controls

enum SessionTargetResolution {
    case ready([SessionProcessTarget])
    case notRunning
    case failed(String)
}

private func resolveTTYName(for target: TerminalTarget) -> String? {
    var ttyName: String?

    if target.terminal == "terminal" && !target.sessionId.isEmpty {
        ttyName = target.sessionId.replacingOccurrences(of: "/dev/", with: "")
    } else if target.terminal == "wezterm" && !target.sessionId.isEmpty {
        // Get TTY from wezterm CLI for this pane
        if let result = runWezTermCLI(arguments: ["list", "--format", "json"]),
           result.succeeded,
           let panes = try? JSONSerialization.jsonObject(with: result.standardOutput) as? [[String: Any]] {
            for pane in panes {
                if let paneId = pane["pane_id"] as? Int, String(paneId) == target.sessionId {
                    if let tty = pane["tty_name"] as? String {
                        ttyName = tty.replacingOccurrences(of: "/dev/", with: "")
                    }
                    break
                }
            }
        }
    } else if target.terminal == "iterm2" && !target.sessionId.isEmpty {
        let uniqueId: String
        if let suffix = target.sessionId.split(separator: ":", maxSplits: 1).last,
           target.sessionId.contains(":") {
            uniqueId = String(suffix)
        } else {
            uniqueId = target.sessionId
        }

        // Sanitize: iTerm2 unique IDs are UUIDs (hex + dashes)
        let sanitizedId = uniqueId.filter { $0.isHexDigit || $0 == "-" }
        guard sanitizedId == uniqueId else { return nil }
        let script = """
        tell application "iTerm2"
            repeat with w in windows
                repeat with t in tabs of w
                    repeat with s in sessions of t
                        if unique id of s is "\(sanitizedId)" then
                            return tty of s
                        end if
                    end repeat
                end repeat
            end repeat
        end tell
        """
        if let appleScript = NSAppleScript(source: script) {
            var error: NSDictionary?
            let result = appleScript.executeAndReturnError(&error)
            if let tty = result.stringValue {
                ttyName = tty.replacingOccurrences(of: "/dev/", with: "")
            }
        }
    }

    guard let tty = ttyName else { return nil }
    let sanitized = tty.filter { $0.isLetter || $0.isNumber }
    guard sanitized == tty else {
        NSLog("[AgentMonitor] session controls: rejecting suspicious tty: %@", tty)
        return nil
    }
    return sanitized
}

private func resolveTTYName(for session: SessionInfo) -> String? {
    let storedTarget = TerminalTarget(
        terminal: session.terminal,
        sessionId: session.terminal_session_id
    )
    if let tty = resolveTTYName(for: storedTarget) {
        return tty
    }

    let liveTarget: TerminalTarget?
    if session.agent == "codex", !session.thread_id.isEmpty {
        liveTarget = resolveLiveCodexTarget(threadID: session.thread_id)
            ?? resolveLiveTarget(agent: session.agent, cwd: session.cwd)
    } else {
        liveTarget = resolveLiveTarget(agent: session.agent, cwd: session.cwd)
    }
    return liveTarget.flatMap(resolveTTYName(for:))
}

func resolveSessionStopTargets(
    _ session: SessionInfo,
    completion: @escaping (SessionTargetResolution) -> Void
) {
    DispatchQueue.global(qos: .userInitiated).async {
        let resolution: SessionTargetResolution
        guard let ttyName = resolveTTYName(for: session) else {
            resolution = .failed("Could not resolve this session to a live terminal.")
            DispatchQueue.main.async { completion(resolution) }
            return
        }

        do {
            let targets = try SessionProcessController.resolveTargets(
                ttyName: ttyName,
                agent: session.agent
            )
            resolution = targets.isEmpty ? .notRunning : .ready(targets)
        } catch {
            resolution = .failed(error.localizedDescription)
        }
        DispatchQueue.main.async { completion(resolution) }
    }
}

func stopSession(
    _ session: SessionInfo,
    targets: [SessionProcessTarget],
    force: Bool,
    completion: @escaping (SessionStopResult) -> Void
) {
    DispatchQueue.global(qos: .userInitiated).async {
        guard let ttyName = targets.first?.ttyName else {
            DispatchQueue.main.async { completion(.notRunning) }
            return
        }

        let currentTargets: [SessionProcessTarget]
        do {
            currentTargets = try SessionProcessController.resolveTargets(
                ttyName: ttyName,
                agent: session.agent
            )
        } catch {
            DispatchQueue.main.async { completion(.failed(error.localizedDescription)) }
            return
        }
        let confirmedPIDs = Set(targets.map(\.pid))
        let currentPIDs = Set(currentTargets.map(\.pid))
        guard currentPIDs == confirmedPIDs else {
            DispatchQueue.main.async {
                completion(.failed("The target process changed before it could be stopped. Choose Stop Agent again to review the current PID."))
            }
            return
        }

        var result = SessionProcessController.stop(
            targets: targets,
            agent: session.agent,
            force: force,
            gracePeriod: force ? 1 : 2
        )
        if case .stopped = result {
            do {
                let remaining = try SessionProcessController.resolveTargets(
                    ttyName: ttyName,
                    agent: session.agent
                )
                if !remaining.isEmpty {
                    result = .failed("A new matching process appeared while stopping the confirmed PID. The monitor entry was kept; choose Stop Agent again to review it.")
                }
            } catch {
                result = .failed("The confirmed process exited, but final verification failed: \(error.localizedDescription)")
            }
        }
        DispatchQueue.main.async { completion(result) }
    }
}

func dismissSession(_ session: SessionInfo, completion: @escaping (String?) -> Void) {
    DispatchQueue.global(qos: .utility).async {
        let safeId = session.session_id.filter { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }
        guard !safeId.isEmpty, safeId == session.session_id else {
            DispatchQueue.main.async { completion("The session identifier is invalid.") }
            return
        }

        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let sessionsDirectory = URL(fileURLWithPath: "\(home)/.claude/monitor/sessions", isDirectory: true)
        let sessionFile = sessionsDirectory.appendingPathComponent("\(safeId).json")
        do {
            _ = try SessionFileStore.remove(at: sessionFile)
            let files = try FileManager.default.contentsOfDirectory(atPath: sessionsDirectory.path)
            let permissionPrefix = "\(safeId)."
            for file in files where file == "\(safeId).permission"
                || (file.hasPrefix(permissionPrefix) && file.hasSuffix(".permission")) {
                try? FileManager.default.removeItem(at: sessionsDirectory.appendingPathComponent(file))
            }
            DispatchQueue.main.async { completion(nil) }
        } catch {
            DispatchQueue.main.async { completion(error.localizedDescription) }
        }
    }
}

// MARK: - Pulsing Dot View

struct PulsingDot: View {
    let color: Color
    let isPulsing: Bool
    var size: CGFloat = 8

    @Environment(\.skin) private var skin
    @State private var scale: CGFloat = 1.0

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
            .scaleEffect(scale)
            .shadow(color: color.opacity(0.6), radius: (isPulsing && skin.id != "terminal") ? 4 : 0)
            .onAppear {
                if isPulsing {
                    withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
                        scale = 1.15
                    }
                }
            }
            .onChange(of: isPulsing) { _, newValue in
                if newValue {
                    withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
                        scale = 1.15
                    }
                } else {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        scale = 1.0
                    }
                }
            }
    }
}

// MARK: - Session Row View

struct SessionRowView: View {
    let session: SessionInfo
    let onOpen: () -> Void
    @Environment(\.skin) private var skin
    @State private var isHovered = false
    @State private var isResolving = false
    @State private var isStopping = false
    @State private var stopTargets: [SessionProcessTarget] = []
    @State private var showStopConfirmation = false
    @State private var showFailure = false
    @State private var failureMessage = ""
    @State private var canForceStop = false
    @State private var canDismissAfterFailure = false

    var body: some View {
        let sc = session.statusColor(for: skin)
        HStack(alignment: .center, spacing: 8) {
            PulsingDot(
                color: sc,
                isPulsing: session.status == "working",
                size: skin.dotSize
            )
            .contentShape(Rectangle())
            .onTapGesture(perform: onOpen)

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 5) {
                    Text(session.project)
                        .font(.system(size: 12, weight: .semibold, design: skin.fontDesign))
                        .foregroundColor(session.isStale ? skin.colors.sessionTitleStale : skin.colors.sessionTitle)
                        .lineLimit(1)
                        .layoutPriority(1)

                    Text(session.displayAgent.uppercased())
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundColor(skin.colors.statusBadgeText)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(skin.colors.divider, lineWidth: 0.75)
                        )
                        .fixedSize()

                    Spacer(minLength: 0)

                    Text(session.elapsedString)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(skin.colors.timestamp)
                        .fixedSize()
                }

                if !session.last_prompt.isEmpty {
                    Text(session.last_prompt)
                        .font(.system(size: 10, design: skin.fontDesign))
                        .foregroundColor(skin.colors.sessionSubtext)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture(perform: onOpen)

            ZStack {
                if isResolving || isStopping {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Menu {
                        Button("Stop Agent…", role: .destructive) {
                            prepareStop()
                        }
                        Button("Dismiss from Monitor") {
                            dismiss()
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(skin.colors.killButton)
                            .contentShape(Rectangle())
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .help("Session actions")
                    .opacity(isHovered ? 1 : 0.35)
                }
            }
            .frame(width: 28, height: 28)
        }
        .padding(.leading, 15)
        .padding(.vertical, 6)
        .onHover { isHovered = $0 }
        .alert("Stop \(session.displayAgent)?", isPresented: $showStopConfirmation) {
            Button("Stop", role: .destructive) {
                performStop(force: false)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Send a graceful stop signal to \(targetDescription)? The row will be removed only after exit is verified.")
        }
        .alert("Session Action Failed", isPresented: $showFailure) {
            if canForceStop {
                Button("Force Stop", role: .destructive) {
                    performStop(force: true)
                }
            }
            if canDismissAfterFailure {
                Button("Dismiss Only") {
                    dismiss()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(failureMessage)
        }
    }

    private var targetDescription: String {
        let pids = stopTargets.map { String($0.pid) }.joined(separator: ", ")
        return "PID\(stopTargets.count == 1 ? "" : "s") \(pids)"
    }

    private func prepareStop() {
        isResolving = true
        resolveSessionStopTargets(session) { resolution in
            isResolving = false
            switch resolution {
            case .ready(let targets):
                stopTargets = targets
                showStopConfirmation = true
            case .notRunning:
                presentFailure(
                    "No matching \(session.displayAgent) process is running. The monitor entry can be dismissed without stopping anything.",
                    canDismiss: true
                )
            case .failed(let message):
                presentFailure(message, canDismiss: true)
            }
        }
    }

    private func performStop(force: Bool) {
        isStopping = true
        stopSession(session, targets: stopTargets, force: force) { result in
            isStopping = false
            switch result {
            case .stopped, .notRunning:
                dismiss()
            case .stillRunning(let pids):
                stopTargets = stopTargets.filter { pids.contains($0.pid) }
                let list = pids.map(String.init).joined(separator: ", ")
                presentFailure(
                    "PID\(pids.count == 1 ? "" : "s") \(list) did not exit after \(force ? "a force stop" : "the graceful stop").",
                    canForce: !force,
                    canDismiss: true
                )
            case .failed(let message):
                presentFailure(message, canDismiss: true)
            }
        }
    }

    private func dismiss() {
        dismissSession(session) { error in
            if let error {
                presentFailure("The monitor entry could not be dismissed: \(error)")
            }
        }
    }

    private func presentFailure(
        _ message: String,
        canForce: Bool = false,
        canDismiss: Bool = false
    ) {
        failureMessage = message
        canForceStop = canForce
        canDismissAfterFailure = canDismiss
        showFailure = true
    }
}

// MARK: - Permission Action View

struct PermissionActionView: View {
    let permission: PermissionInfo
    let sessionId: String
    let reader: SessionReader
    let onTerminal: () -> Void
    @Environment(\.skin) private var skin
    @State private var responding: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Tool name header with icon
            HStack(spacing: 5) {
                Image(systemName: permission.toolIcon)
                    .font(.system(size: 10))
                    .foregroundColor(skin.colors.attention)
                Text(permission.tool_name)
                    .font(.system(size: 11, weight: .semibold, design: skin.fontDesign))
                    .foregroundColor(skin.colors.attention)
            }

            // Command/detail text
            Text(permission.display)
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(skin.colors.sessionSubtext.opacity(0.95))
                .lineLimit(1)
                .truncationMode(.tail)
                .help(permission.display)

            if let action = responding {
                // Processing indicator
                HStack(spacing: 6) {
                    PulsingDot(color: action == "allow" ? skin.colors.done : action == "deny" ? .red : skin.colors.starting, isPulsing: true, size: skin.dotSize)
                    Text(action == "allow" ? "Allowing..." : action == "deny" ? "Denying..." : "Switching...")
                        .font(.system(size: 10, design: skin.fontDesign))
                        .foregroundColor(skin.colors.sessionSubtext)
                }
            } else {
            // Action buttons
            HStack(spacing: 8) {
                Button {
                    if reader.respondToPermission(sessionId: sessionId, requestId: permission.request_id, decision: "allow") {
                        responding = "allow"
                    }
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 9, weight: .bold))
                        Text("Allow")
                            .font(.system(size: 10, weight: .medium, design: skin.fontDesign))
                    }
                    .foregroundColor(skin.colors.buttonTextColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(skin.colors.done.opacity(0.4))
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Button {
                    if reader.respondToPermission(sessionId: sessionId, requestId: permission.request_id, decision: "deny") {
                        responding = "deny"
                    }
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "xmark")
                            .font(.system(size: 9, weight: .bold))
                        Text("Deny")
                            .font(.system(size: 10, weight: .medium, design: skin.fontDesign))
                    }
                    .foregroundColor(skin.colors.buttonTextColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.red.opacity(0.4))
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Button {
                    if reader.respondToPermission(sessionId: sessionId, requestId: permission.request_id, decision: "terminal") {
                        responding = "terminal"
                        onTerminal()
                    }
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "arrow.right.square")
                            .font(.system(size: 9))
                        Text("Terminal")
                            .font(.system(size: 10, weight: .medium, design: skin.fontDesign))
                    }
                    .foregroundColor(skin.colors.buttonTextColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(skin.colors.divider.opacity(0.9))
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Spacer()
            }
            } // else
        }
        .padding(.leading, 28)
        .padding(.trailing, 12)
        .padding(.vertical, 6)
        .background(skin.colors.permissionBackground)
    }
}

// MARK: - Header Bar

// MARK: - Settings Popover

struct SettingsPopover: View {
    @ObservedObject var configManager: ConfigManager
    @ObservedObject var voiceFetcher: VoiceFetcher
    @ObservedObject var usageFetcher: UsageFetcher
    var sessionReader: SessionReader?
    @Environment(\.skin) private var skin
    @State private var pastedVoiceId: String? = nil
    @State private var refreshed = false

    private let voiceModes: [(id: String, title: String, subtitle: String)] = [
        ("say", "Vanilla say", "Built-in macOS speech"),
        ("elevenlabs", "Live 11 Labs TTS", "Fresh API call on every announcement"),
        ("cache", "Cached 11 Labs TTS", "Generate once, then replay instantly from cache")
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Skin picker section
            Text("Skin")
                .font(.system(size: 9, weight: .medium, design: skin.headerFontDesign))
                .foregroundColor(skin.colors.sessionSubtext)
                .textCase(.uppercase)

            VStack(alignment: .leading, spacing: 2) {
                ForEach(MonitorSkin.allSkins) { s in
                    let isSelected = configManager.skinId == s.id
                    Button {
                        configManager.setSkin(s.id)
                    } label: {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(isSelected ? skin.colors.settingsAccent : skin.colors.divider)
                                .frame(width: 6, height: 6)
                            Text(s.name)
                                .font(.system(size: 11, design: skin.fontDesign))
                                .foregroundColor(isSelected ? skin.colors.sessionTitle : skin.colors.sessionSubtext)
                                .lineLimit(1)
                            Spacer()
                        }
                        .padding(.vertical, 2)
                    }
                    .buttonStyle(.plain)
                }
            }

            Divider().background(skin.colors.divider)

            // Refresh sessions
            Button {
                sessionReader?.readSessions() // Immediate refresh of known sessions
                sessionReader?.discoverSessions() // Async — finds new sessions, calls readSessions on completion
                refreshed = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) { refreshed = false }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: refreshed ? "checkmark" : "arrow.clockwise")
                        .font(.system(size: 10))
                        .foregroundColor(refreshed ? skin.colors.done : skin.colors.sessionSubtext)
                    Text(refreshed ? "Refreshed" : "Refresh sessions")
                        .font(.system(size: 11, design: skin.fontDesign))
                        .foregroundColor(refreshed ? skin.colors.done.opacity(0.8) : skin.colors.sessionSubtext.opacity(0.95))
                    Spacer()
                }
            }
            .buttonStyle(.plain)

            Divider().background(skin.colors.divider)

            // Usage tracking toggle
            Button {
                configManager.toggleUsage()
                usageFetcher.setEnabled(configManager.usageEnabled)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: configManager.usageEnabled ? "chart.bar.fill" : "chart.bar")
                        .font(.system(size: 10))
                        .foregroundColor(configManager.usageEnabled ? skin.colors.settingsAccent : skin.colors.timestamp)
                    Text(configManager.usageEnabled ? "Usage tracking on" : "Usage tracking off")
                        .font(.system(size: 11, design: skin.fontDesign))
                        .foregroundColor(configManager.usageEnabled ? skin.colors.sessionTitle : skin.colors.sessionSubtext)
                    Spacer()
                }
            }
            .buttonStyle(.plain)

            Divider().background(skin.colors.divider)

            // Master toggle
            Button {
                configManager.toggleVoice()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: configManager.voiceEnabled ? "speaker.wave.2.fill" : "speaker.slash.fill")
                        .font(.system(size: 10))
                        .foregroundColor(configManager.voiceEnabled ? skin.colors.settingsAccent : skin.colors.timestamp)
                    Text(configManager.voiceEnabled ? "Voice on" : "Voice off")
                        .font(.system(size: 11, design: skin.fontDesign))
                        .foregroundColor(configManager.voiceEnabled ? skin.colors.sessionTitle : skin.colors.sessionSubtext)
                    Spacer()
                }
            }
            .buttonStyle(.plain)

            if configManager.voiceEnabled {
                Divider().background(skin.colors.divider)

                Text("Voice")
                    .font(.system(size: 9, weight: .medium, design: skin.headerFontDesign))
                    .foregroundColor(skin.colors.sessionSubtext)
                    .textCase(.uppercase)

                VStack(alignment: .leading, spacing: 2) {
                    ForEach(voiceModes, id: \.id) { mode in
                        let isSelected = configManager.ttsProvider == mode.id
                        Button {
                            configManager.setTTSProvider(mode.id)
                        } label: {
                            HStack(alignment: .top, spacing: 6) {
                                Circle()
                                    .fill(isSelected ? skin.colors.settingsAccent : skin.colors.divider)
                                    .frame(width: 6, height: 6)
                                    .padding(.top, 4)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(mode.title)
                                        .font(.system(size: 11, design: skin.fontDesign))
                                        .foregroundColor(isSelected ? skin.colors.sessionTitle : skin.colors.sessionSubtext)
                                    Text(mode.subtitle)
                                        .font(.system(size: 9, design: skin.fontDesign))
                                        .foregroundColor(skin.colors.timestamp)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                Spacer()
                            }
                            .padding(.vertical, 2)
                        }
                        .buttonStyle(.plain)
                    }
                }

                if configManager.ttsProvider == "say" {
                    HStack(spacing: 4) {
                        Text(configManager.config?.say.voice ?? "System voice")
                            .font(.system(size: 11, weight: .medium, design: skin.fontDesign))
                            .foregroundColor(skin.colors.settingsAccent)
                        Spacer()
                        Text("macOS")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundColor(skin.colors.divider.opacity(1.0))
                    }
                } else {
                    Divider().background(skin.colors.divider)

                    if let name = configManager.voiceName(for: configManager.currentVoiceId) {
                        HStack(spacing: 4) {
                            Text(name)
                                .font(.system(size: 11, weight: .medium, design: skin.fontDesign))
                                .foregroundColor(skin.colors.settingsAccent)
                            Spacer()
                            Text(String(configManager.currentVoiceId.prefix(8)))
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundColor(skin.colors.divider.opacity(1.0))
                        }
                    }

                    Divider().background(skin.colors.divider)

                    Button {
                        if let pasted = NSPasteboard.general.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines),
                           !pasted.isEmpty {
                            configManager.setVoice(pasted)
                            pastedVoiceId = String(pasted.prefix(20))
                            let voiceId = pasted
                            if let existing = configManager.voiceName(for: voiceId) {
                                configManager.addVoice(id: voiceId, name: existing)
                            } else {
                                voiceFetcher.resolveVoiceName(id: voiceId) { name in
                                    DispatchQueue.main.async {
                                        configManager.addVoice(id: voiceId, name: name ?? "Voice \(String(voiceId.prefix(8)))")
                                    }
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "doc.on.clipboard")
                                .font(.system(size: 9))
                                .foregroundColor(skin.colors.sessionSubtext)
                            Text("Paste voice ID")
                                .font(.system(size: 10, design: skin.fontDesign))
                                .foregroundColor(skin.colors.sessionSubtext)
                            Spacer()
                        }
                    }
                    .buttonStyle(.plain)

                    if let pasted = pastedVoiceId {
                        Text("Set to \(pasted)...")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundColor(skin.colors.done.opacity(0.6))
                    }
                }
            }
        }
        .padding(10)
        .frame(width: 200)
        .modifier(PopoverContentBackground(skin: skin, glassConfig: configManager.glassConfig))
    }
}

// MARK: - Usage Popover

struct UsageBarView: View {
    let label: String
    let window: UsageWindow
    let compact: Bool
    @Environment(\.skin) private var skin

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(label)
                    .font(.system(size: 10, weight: .medium, design: skin.fontDesign))
                    .foregroundColor(skin.colors.sessionSubtext.opacity(0.95))
                Spacer()
                Text("\(Int(window.utilizationPercent))%")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundColor(window.barColor)
            }

            // Bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(skin.colors.divider)
                        .frame(height: 4)
                    RoundedRectangle(cornerRadius: 2)
                        .fill(window.barColor)
                        .frame(width: max(geo.size.width * window.utilizationPercent / 100, 2), height: 4)
                }
            }
            .frame(height: 4)

            if !compact {
                Text("resets \(window.resetCountdown)")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(skin.colors.sessionSubtext)
            }
        }
    }
}

struct UsagePopover: View {
    @ObservedObject var fetcher: UsageFetcher
    @ObservedObject var configManager: ConfigManager
    @Environment(\.skin) private var skin

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Usage")
                    .font(.system(size: 11, weight: .semibold, design: skin.headerFontDesign))
                    .foregroundColor(skin.colors.headerText)
                Spacer()
                Button {
                    fetcher.fetch()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 9))
                        .foregroundColor(skin.colors.sessionSubtext)
                }
                .buttonStyle(.plain)
            }

            if let error = fetcher.error {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 9))
                        .foregroundColor(skin.colors.attention)
                    Text(error)
                        .font(.system(size: 10, design: skin.fontDesign))
                        .foregroundColor(skin.colors.attention.opacity(0.8))
                }
                // Offer to disable when credentials are the problem
                if error == "No credentials" || error == "Auth expired" {
                    Button {
                        configManager.toggleUsage()
                        fetcher.setEnabled(false)
                    } label: {
                        Text("Disable usage tracking")
                            .font(.system(size: 9, design: skin.fontDesign))
                            .foregroundColor(skin.colors.sessionSubtext)
                            .underline()
                    }
                    .buttonStyle(.plain)
                }
            } else if let usage = fetcher.usage {
                if let fiveHour = usage.five_hour {
                    UsageBarView(label: "Session (5h)", window: fiveHour, compact: false)
                }

                if let sevenDay = usage.seven_day {
                    UsageBarView(label: "Weekly (7d)", window: sevenDay, compact: false)
                }

                // Per-model breakdown if present and non-zero
                if let opus = usage.seven_day_opus, opus.utilization > 0 {
                    UsageBarView(label: "Opus", window: opus, compact: true)
                }
                if let sonnet = usage.seven_day_sonnet, sonnet.utilization > 0 {
                    UsageBarView(label: "Sonnet", window: sonnet, compact: true)
                }

                // Extra usage credits
                if let extra = usage.extra_usage, extra.is_enabled == true {
                    Divider().background(skin.colors.divider)
                    HStack {
                        Text("Credits")
                            .font(.system(size: 10, weight: .medium, design: skin.fontDesign))
                            .foregroundColor(skin.colors.sessionSubtext.opacity(0.95))
                        Spacer()
                        Text(String(format: "$%.2f / $%.0f", extra.usedDollars, extra.limitDollars))
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(skin.colors.sessionSubtext)
                    }
                }

                if let lastFetched = fetcher.lastFetched {
                    let ago = Int(Date().timeIntervalSince(lastFetched))
                    Text(ago < 5 ? "just now" : "\(ago)s ago")
                        .font(.system(size: 8, design: .monospaced))
                        .foregroundColor(skin.colors.divider)
                }
            } else {
                HStack(spacing: 4) {
                    ProgressView()
                        .scaleEffect(0.5)
                        .frame(width: 10, height: 10)
                    Text("Loading...")
                        .font(.system(size: 10, design: skin.fontDesign))
                        .foregroundColor(skin.colors.sessionSubtext)
                }
            }
        }
        .padding(10)
        .frame(width: 200)
        .modifier(PopoverContentBackground(skin: skin, glassConfig: configManager.glassConfig))
        .onAppear {
            fetcher.fetchIfStale()
        }
    }
}

private enum MonitorPopoverKind {
    case usage
    case settings
}

private final class MonitorPopoverPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 120),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isMovableByWindowBackground = false
        hidesOnDeactivate = true
    }
}

private struct MonitorPopoverAnchorReader: NSViewRepresentable {
    let kind: MonitorPopoverKind

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.postsFrameChangedNotifications = true
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            MonitorPopoverManager.shared.register(anchorView: nsView, for: kind)
        }
    }
}

private struct MonitorPopoverSurface<Content: View>: View {
    @ObservedObject var configManager: ConfigManager
    let content: Content

    init(configManager: ConfigManager, @ViewBuilder content: () -> Content) {
        _configManager = ObservedObject(wrappedValue: configManager)
        self.content = content()
    }

    private var skin: MonitorSkin { configManager.currentSkin }
    private var panelShadow: MonitorPanelShadowStyle { shadowStyle(for: skin) }
    private var surfaceShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: skin.cornerRadius, style: .continuous)
    }

    var body: some View {
        content
            .background(
                Group {
                    if skin.id == "glass" {
                        SkinAwareBackground(skin: skin, glassConfig: configManager.glassConfig)
                    }
                }
            )
            .clipShape(surfaceShape)
            .overlay(
                Group {
                    if skin.id == "obsidian" {
                        surfaceShape
                            .strokeBorder(
                                LinearGradient(
                                    stops: [
                                        .init(color: Color(white: 1.0, opacity: 0.08), location: 0.0),
                                        .init(color: Color(white: 1.0, opacity: 0.03), location: 0.15),
                                        .init(color: .clear, location: 0.4),
                                        .init(color: .clear, location: 1.0),
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 2.0
                        )
                    } else if skin.borderWidth > 0 {
                        surfaceShape
                            .strokeBorder(skin.colors.border, lineWidth: skin.borderWidth + 1)
                    }
                }
                .allowsHitTesting(false)
            )
            .shadow(color: panelShadow.color, radius: panelShadow.radius, y: panelShadow.y)
            .environment(\.skin, skin)
    }
}

private final class MonitorPopoverManager {
    static let shared = MonitorPopoverManager()

    private final class WeakAnchorView {
        weak var view: NSView?
        init(_ view: NSView) { self.view = view }
    }

    private var anchors: [MonitorPopoverKind: WeakAnchorView] = [:]
    private weak var parentWindow: NSWindow?
    private weak var anchorView: NSView?
    private var panel: MonitorPopoverPanel?
    private var currentKind: MonitorPopoverKind?
    private var localMonitor: Any?
    private var globalMonitor: Any?
    private var resignActiveObserver: Any?
    private var parentWindowCloseObserver: Any?
    private var sizeObserver: AnyCancellable?
    private var skinObserver: AnyCancellable?

    func register(anchorView: NSView, for kind: MonitorPopoverKind) {
        anchors[kind] = WeakAnchorView(anchorView)
    }

    func toggle(
        kind: MonitorPopoverKind,
        configManager: ConfigManager,
        usageFetcher: UsageFetcher,
        sessionReader: SessionReader?
    ) {
        if currentKind == kind {
            close()
            return
        }

        show(
            kind: kind,
            configManager: configManager,
            usageFetcher: usageFetcher,
            sessionReader: sessionReader
        )
    }

    func close() {
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
            self.localMonitor = nil
        }
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
            self.globalMonitor = nil
        }
        if let resignActiveObserver {
            NotificationCenter.default.removeObserver(resignActiveObserver)
            self.resignActiveObserver = nil
        }
        if let parentWindowCloseObserver {
            NotificationCenter.default.removeObserver(parentWindowCloseObserver)
            self.parentWindowCloseObserver = nil
        }
        sizeObserver?.cancel()
        sizeObserver = nil
        skinObserver?.cancel()
        skinObserver = nil
        if let panel, let parentWindow {
            parentWindow.removeChildWindow(panel)
            panel.orderOut(nil)
        } else {
            panel?.orderOut(nil)
        }
        anchorView = nil
        panel = nil
        parentWindow = nil
        currentKind = nil
    }

    private func show(
        kind: MonitorPopoverKind,
        configManager: ConfigManager,
        usageFetcher: UsageFetcher,
        sessionReader: SessionReader?
    ) {
        close()

        guard let anchorView = anchors[kind]?.view,
              let anchorWindow = anchorView.window else { return }

        let rootView = buildRootView(
            kind: kind,
            configManager: configManager,
            usageFetcher: usageFetcher,
            sessionReader: sessionReader
        )
        let hostingView = ClickHostingView(rootView: rootView)
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = .clear
        hostingView.layer?.cornerRadius = configManager.currentSkin.cornerRadius
        hostingView.layer?.cornerCurve = .continuous
        hostingView.layer?.masksToBounds = true

        let fittingSize = hostingView.fittingSize
        hostingView.frame = NSRect(origin: .zero, size: fittingSize)

        let panel = MonitorPopoverPanel()
        panel.contentView = hostingView
        panel.setContentSize(fittingSize)

        position(panel: panel, relativeTo: anchorView)
        anchorWindow.addChildWindow(panel, ordered: .above)
        panel.orderFrontRegardless()

        self.parentWindow = anchorWindow
        self.anchorView = anchorView
        self.panel = panel
        self.currentKind = kind
        installSizeObserver(hostingView: hostingView)
        installSkinObserver(hostingView: hostingView, configManager: configManager)
        installCloseMonitors()
    }

    private func buildRootView(
        kind: MonitorPopoverKind,
        configManager: ConfigManager,
        usageFetcher: UsageFetcher,
        sessionReader: SessionReader?
    ) -> AnyView {
        AnyView(
            MonitorPopoverSurface(configManager: configManager) {
                switch kind {
                case .usage:
                    UsagePopover(fetcher: usageFetcher, configManager: configManager)
                case .settings:
                    SettingsPopover(
                        configManager: configManager,
                        voiceFetcher: configManager.voiceFetcher,
                        usageFetcher: usageFetcher,
                        sessionReader: sessionReader
                    )
                }
            }
        )
    }

    private func position(panel: NSPanel, relativeTo anchorView: NSView) {
        guard let anchorWindow = anchorView.window else { return }

        let anchorRectInWindow = anchorView.convert(anchorView.bounds, to: nil)
        let anchorRectOnScreen = anchorWindow.convertToScreen(anchorRectInWindow)
        let size = panel.contentView?.fittingSize ?? panel.frame.size
        let screenFrame = anchorWindow.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
        let padding: CGFloat = 8
        let gap: CGFloat = 6

        var x = anchorRectOnScreen.midX - (size.width / 2)
        x = min(max(x, screenFrame.minX + padding), screenFrame.maxX - size.width - padding)

        var y = anchorRectOnScreen.minY - size.height - gap
        if y < screenFrame.minY + padding {
            y = anchorRectOnScreen.maxY + gap
        }

        panel.setFrame(NSRect(x: x, y: y, width: size.width, height: size.height), display: true)
    }

    private func installCloseMonitors() {
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown, .keyDown]) { [weak self] event in
            self?.handleLocalEvent(event)
            return event
        }

        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] _ in
            self?.close()
        }

        resignActiveObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.close()
        }

        if let parentWindow {
            parentWindowCloseObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.willCloseNotification,
                object: parentWindow,
                queue: .main
            ) { [weak self] _ in
                self?.close()
            }
        }
    }

    private func handleLocalEvent(_ event: NSEvent) {
        if event.type == .keyDown, event.keyCode == 53 {
            close()
            return
        }

        guard let panel else { return }
        if event.window === panel { return }
        if isEventInsideAnyAnchor(event) { return }
        close()
    }

    private func installSizeObserver(hostingView: NSHostingView<AnyView>) {
        sizeObserver?.cancel()
        sizeObserver = hostingView.publisher(for: \.fittingSize)
            .debounce(for: .milliseconds(20), scheduler: RunLoop.main)
            .sink { [weak self, weak hostingView] newSize in
                guard let self, let panel = self.panel, let anchorView = self.anchorView else { return }
                hostingView?.frame = NSRect(origin: .zero, size: newSize)
                panel.setContentSize(newSize)
                self.position(panel: panel, relativeTo: anchorView)
            }
    }

    private func installSkinObserver(hostingView: NSHostingView<AnyView>, configManager: ConfigManager) {
        skinObserver?.cancel()
        skinObserver = configManager.$currentSkin
            .sink { [weak hostingView] skin in
                hostingView?.layer?.cornerRadius = skin.cornerRadius
                hostingView?.layer?.cornerCurve = .continuous
                hostingView?.layer?.masksToBounds = true
            }
    }

    private func isEventInsideAnyAnchor(_ event: NSEvent) -> Bool {
        for anchor in anchors.values {
            guard let view = anchor.view,
                  let window = view.window,
                  event.window === window else { continue }
            let point = view.convert(event.locationInWindow, from: nil)
            if view.bounds.contains(point) {
                return true
            }
        }
        return false
    }
}

// MARK: - Header Bar

struct HeaderBar: View {
    let sessions: [SessionInfo]
    @ObservedObject var configManager: ConfigManager
    @ObservedObject var usageFetcher: UsageFetcher
    var sessionReader: SessionReader?
    @Binding var isExpanded: Bool
    @Environment(\.skin) private var skin

    var attentionCount: Int { sessions.filter { $0.status == "attention" }.count }
    var workingCount: Int { sessions.filter { $0.status == "working" }.count }
    var doneCount: Int { sessions.filter { $0.status == "done" }.count }

    var body: some View {
        HStack(spacing: 10) {
            // Chevron + title
            Button {
                isExpanded.toggle()
                UserDefaults.standard.set(isExpanded, forKey: "monitorExpanded")
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundColor(skin.colors.chevron)
                        .frame(width: 10)
                    Text("Agent Monitor")
                        .font(.system(size: 11, weight: .semibold, design: skin.headerFontDesign))
                        .foregroundColor(skin.colors.headerText)
                        .opacity(0.65)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .layoutPriority(0)

            Spacer(minLength: 8)

            HStack(spacing: 8) {
                if attentionCount > 0 {
                    HStack(spacing: 3) {
                        Circle().fill(skin.colors.attention).frame(width: skin.dotSize - 2, height: skin.dotSize - 2)
                        Text("\(attentionCount)")
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundColor(skin.colors.attention)
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                    }
                    .fixedSize(horizontal: true, vertical: false)
                }
                if workingCount > 0 {
                    HStack(spacing: 3) {
                        Circle().fill(skin.colors.working).frame(width: skin.dotSize - 2, height: skin.dotSize - 2)
                        Text("\(workingCount)")
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundColor(skin.colors.working)
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                    }
                    .fixedSize(horizontal: true, vertical: false)
                }
                if doneCount > 0 {
                    HStack(spacing: 3) {
                        Circle().fill(skin.colors.done).frame(width: skin.dotSize - 2, height: skin.dotSize - 2)
                        Text("\(doneCount)")
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundColor(skin.colors.done)
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                    }
                    .fixedSize(horizontal: true, vertical: false)
                }

                Text("\(sessions.count)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(skin.colors.timestamp)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)

                if configManager.usageEnabled {
                    Button {
                        MonitorPopoverManager.shared.toggle(
                            kind: .usage,
                            configManager: configManager,
                            usageFetcher: usageFetcher,
                            sessionReader: sessionReader
                        )
                    } label: {
                        Image(systemName: "chart.bar.fill")
                            .font(.system(size: 8))
                            .foregroundColor(usageIconColor)
                    }
                    .buttonStyle(.plain)
                    .background(MonitorPopoverAnchorReader(kind: .usage))
                }

                Button {
                    MonitorPopoverManager.shared.toggle(
                        kind: .settings,
                        configManager: configManager,
                        usageFetcher: usageFetcher,
                        sessionReader: sessionReader
                    )
                } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 8))
                        .foregroundColor(skin.colors.chevron)
                }
                .buttonStyle(.plain)
                .background(MonitorPopoverAnchorReader(kind: .settings))
            }
            .layoutPriority(1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var usageIconColor: Color {
        guard let usage = usageFetcher.usage else { return skin.colors.chevron }
        // Reflect the worst quota status
        let maxUtil = max(usage.five_hour?.utilizationPercent ?? 0, usage.seven_day?.utilizationPercent ?? 0)
        if maxUtil > 80 { return .red.opacity(0.7) }
        if maxUtil > 50 { return .yellow.opacity(0.6) }
        return skin.colors.chevron
    }
}

// MARK: - Skin-Aware Background

private struct TeletypeGrainOverlay: View {
    @State private var normalizedDots: [CGPoint] = []

    var body: some View {
        GeometryReader { geometry in
            Canvas { context, size in
                let grainColor = Color(red: 0.922, green: 0.878, blue: 0.784).opacity(0.4)
                for dot in normalizedDots {
                    let rect = CGRect(
                        x: dot.x * size.width,
                        y: dot.y * size.height,
                        width: 1,
                        height: 1
                    )
                    context.fill(Path(ellipseIn: rect), with: .color(grainColor))
                }
            }
            .onAppear {
                if normalizedDots.isEmpty {
                    normalizedDots = Self.makeDots(count: 400)
                }
            }
            .onChange(of: geometry.size) { _, _ in
                if normalizedDots.isEmpty {
                    normalizedDots = Self.makeDots(count: 400)
                }
            }
        }
        .allowsHitTesting(false)
    }

    private static func makeDots(count: Int) -> [CGPoint] {
        var generator = SeededGenerator(seed: 0x54454C45)
        return (0..<count).map { _ in
            CGPoint(x: Double.random(in: 0...1, using: &generator), y: Double.random(in: 0...1, using: &generator))
        }
    }
}

private struct TeletypePlatenRulesOverlay: View {
    var body: some View {
        Canvas { context, size in
            var path = Path()
            for y in stride(from: 24.0, through: size.height, by: 24.0) {
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
            }
            context.stroke(
                path,
                with: .color(Color(red: 0.847, green: 0.792, blue: 0.659).opacity(0.5)),
                lineWidth: 0.5
            )
        }
        .allowsHitTesting(false)
    }
}

private struct TeletypeBackground: View {
    var body: some View {
        ZStack {
            Color(red: 0.957, green: 0.918, blue: 0.835)
            TeletypeGrainOverlay()
            TeletypePlatenRulesOverlay()
        }
    }
}

private struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state = state &* 6364136223846793005 &+ 1
        return state
    }
}

private struct MonitorPanelShadowStyle {
    let color: Color
    let radius: CGFloat
    let y: CGFloat
}

private func shadowStyle(for skin: MonitorSkin) -> MonitorPanelShadowStyle {
    switch skin.id {
    case "obsidian":
        return MonitorPanelShadowStyle(color: .black.opacity(0.7), radius: 16, y: 8)
    case "terminal":
        return MonitorPanelShadowStyle(color: .black.opacity(0.45), radius: 8, y: 3)
    case "teletype":
        return MonitorPanelShadowStyle(
            color: Color(red: 0.102, green: 0.078, blue: 0.063).opacity(0.18),
            radius: 18,
            y: 4
        )
    default:
        return MonitorPanelShadowStyle(color: skin.colors.shadow, radius: 12, y: 4)
    }
}

struct SkinAwareBackground: View {
    let skin: MonitorSkin
    var glassConfig: MonitorConfig.GlassConfig = ConfigManager.defaultGlass

    var body: some View {
        if skin.id == "obsidian" {
            // Dark neumorphic: subtle top-to-bottom gradient
            ZStack {
                LinearGradient(
                    colors: [
                        Color(red: 0.13, green: 0.13, blue: 0.14),  // slightly lighter top
                        Color(red: 0.09, green: 0.09, blue: 0.10),  // darker bottom
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
        } else if skin.id == "teletype" {
            TeletypeBackground()
        } else if skin.usesVibrancy {
            VisualEffectView(
                material: skin.material,
                blendingMode: .behindWindow,
                cornerRadius: skin.cornerRadius,
                blurAlpha: CGFloat(glassConfig.blur),
                fillOpacity: CGFloat(glassConfig.opacity),
                tintColor: NSColor(
                    red: CGFloat(glassConfig.tintR),
                    green: CGFloat(glassConfig.tintG),
                    blue: CGFloat(glassConfig.tintB),
                    alpha: CGFloat(glassConfig.tintStrength)
                )
            )
        } else {
            skin.colors.panelBackground
        }
    }
}

private struct PopoverContentBackground: ViewModifier {
    let skin: MonitorSkin
    let glassConfig: MonitorConfig.GlassConfig

    @ViewBuilder
    func body(content: Content) -> some View {
        if skin.id == "glass" {
            content
        } else {
            content.background(
                SkinAwareBackground(skin: skin, glassConfig: glassConfig)
            )
        }
    }
}

// MARK: - Main Content View

struct MonitorContentView: View {
    @ObservedObject var reader: SessionReader
    @ObservedObject var configManager: ConfigManager
    @ObservedObject var usageFetcher: UsageFetcher
    @State private var isExpanded: Bool = UserDefaults.standard.object(forKey: "monitorExpanded") as? Bool ?? true

    var skin: MonitorSkin { configManager.currentSkin }
    private var panelShadow: MonitorPanelShadowStyle { shadowStyle(for: skin) }
    private var surfaceShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: skin.cornerRadius, style: .continuous)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header — always visible, drag to move
            HeaderBar(sessions: reader.sessions, configManager: configManager, usageFetcher: usageFetcher, sessionReader: reader, isExpanded: $isExpanded)

            if isExpanded && (!reader.sessions.isEmpty || !reader.permissions.isEmpty) {
                Divider()
                    .background(skin.colors.divider)

                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(reader.sessions) { session in
                            SessionRowView(
                                session: session,
                                onOpen: { switchToSession(session) }
                            )

                            ForEach(reader.permissions[session.id] ?? []) { perm in
                                PermissionActionView(
                                    permission: perm,
                                    sessionId: session.id,
                                    reader: reader,
                                    onTerminal: { switchToSession(session) }
                                )
                            }

                            if session.id != reader.sessions.last?.id {
                                Divider()
                                    .background(skin.colors.divider.opacity(0.5))
                                    .padding(.leading, 15)
                            }
                        }

                        let knownSessionIds = Set(reader.sessions.map(\.id))
                        ForEach(reader.permissions.keys.filter { !knownSessionIds.contains($0) }.sorted(), id: \.self) { sessionId in
                            ForEach(reader.permissions[sessionId] ?? []) { perm in
                                PermissionActionView(
                                    permission: perm,
                                    sessionId: sessionId,
                                    reader: reader,
                                    onTerminal: {}
                                )
                            }
                        }
                    }
                    .background(ScrollbarStyler())
                }
                .frame(maxHeight: 300)
            }
        }
        .frame(width: 280)
        .fixedSize(horizontal: false, vertical: true)
        .background(
            SkinAwareBackground(skin: skin, glassConfig: configManager.glassConfig)
        )
        .clipShape(surfaceShape)
        .overlay(
            Group {
                if skin.id == "obsidian" {
                    // Obsidian: top-edge highlight only
                    surfaceShape
                        .strokeBorder(
                            LinearGradient(
                                stops: [
                                    .init(color: Color(white: 1.0, opacity: 0.08), location: 0.0),
                                    .init(color: Color(white: 1.0, opacity: 0.03), location: 0.15),
                                    .init(color: .clear, location: 0.4),
                                    .init(color: .clear, location: 1.0),
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 2.0
                        )
                } else if skin.borderWidth > 0 {
                    surfaceShape
                        .strokeBorder(skin.colors.border, lineWidth: skin.borderWidth + 1)
                }
            }
            .allowsHitTesting(false)
        )
        .shadow(color: panelShadow.color, radius: panelShadow.radius, y: panelShadow.y)
        .environment(\.skin, skin)
    }
}

// MARK: - Custom Thin Scrollbar

class ThinScroller: NSScroller {
    override class func scrollerWidth(for controlSize: ControlSize, scrollerStyle: Style) -> CGFloat {
        return 4
    }

    override func drawKnob() {
        var knobRect = rect(for: .knob)
        knobRect = NSRect(
            x: bounds.width - 3,
            y: knobRect.origin.y + 2,
            width: 2,
            height: max(knobRect.height - 4, 8)
        )
        let path = NSBezierPath(roundedRect: knobRect, xRadius: 1, yRadius: 1)
        NSColor.white.withAlphaComponent(0.2).setFill()
        path.fill()
    }

    override func drawKnobSlot(in slotRect: NSRect, highlight flag: Bool) {
        // Transparent track — no background
    }
}

struct ScrollbarStyler: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.setFrameSize(.zero)
        DispatchQueue.main.async {
            var superview = view.superview
            while let sv = superview {
                if let scrollView = sv as? NSScrollView {
                    scrollView.scrollerStyle = .overlay
                    scrollView.hasVerticalScroller = true
                    scrollView.autohidesScrollers = true
                    scrollView.drawsBackground = false
                    scrollView.backgroundColor = .clear
                    scrollView.borderType = .noBorder
                    scrollView.contentView.drawsBackground = false
                    let scroller = ThinScroller()
                    scroller.controlSize = .mini
                    scroller.scrollerStyle = .overlay
                    scrollView.verticalScroller = scroller
                    break
                }
                superview = sv.superview
            }
        }
        return view
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

// MARK: - NSVisualEffectView wrapper

final class RoundedVisualEffectNSView: NSVisualEffectView {
    var cornerRadius: CGFloat = 0 {
        didSet { updateCornerMask() }
    }

    override func layout() {
        super.layout()
        updateCornerMask()
    }

    private func updateCornerMask() {
        wantsLayer = true
        layer?.backgroundColor = .clear
        layer?.cornerRadius = cornerRadius
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = true
    }
}

struct VisualEffectView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode
    let cornerRadius: CGFloat
    var blurAlpha: CGFloat = 1.0
    var fillOpacity: CGFloat = 0.5
    var tintColor: NSColor? = nil

    func makeNSView(context: Context) -> RoundedVisualEffectNSView {
        let view = RoundedVisualEffectNSView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        view.appearance = NSAppearance(named: .darkAqua)
        view.cornerRadius = cornerRadius
        // Defer so internal sublayers are created
        DispatchQueue.main.async { self.configureLayers(view) }
        return view
    }

    func updateNSView(_ nsView: RoundedVisualEffectNSView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
        nsView.cornerRadius = cornerRadius
        configureLayers(nsView)
    }

    private func configureLayers(_ view: RoundedVisualEffectNSView) {
        guard let layer = view.layer else { return }

        // Adjust the internal "fill" layer opacity — this controls
        // how opaque the dark material is, independent of blur
        func findLayer(_ name: String, in root: CALayer) -> CALayer? {
            if root.name == name { return root }
            for sub in root.sublayers ?? [] {
                if let found = findLayer(name, in: sub) { return found }
            }
            return nil
        }

        if let backdrop = findLayer("backdrop", in: layer) {
            backdrop.opacity = Float(blurAlpha)
        }
        if let fill = findLayer("fill", in: layer) {
            fill.opacity = Float(fillOpacity)
        }
        if let tone = findLayer("tone", in: layer) {
            tone.opacity = Float(fillOpacity)
        }

        // Apply custom tint
        layer.sublayers?.filter { $0.name == "customTint" }.forEach { $0.removeFromSuperlayer() }
        if let tint = tintColor {
            let tintLayer = CALayer()
            tintLayer.name = "customTint"
            tintLayer.frame = view.bounds
            tintLayer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
            tintLayer.backgroundColor = tint.cgColor
            tintLayer.compositingFilter = "softLight"
            layer.addSublayer(tintLayer)
        }

        view.layer?.backgroundColor = .clear
        view.layer?.cornerRadius = cornerRadius
        view.layer?.cornerCurve = .continuous
        view.layer?.masksToBounds = true
    }
}

// MARK: - Floating Panel

class FloatingPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 280, height: 40),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        self.level = .floating
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = false
        self.isMovableByWindowBackground = true
        self.ignoresMouseEvents = false
    }

    func restorePosition() {
        if let x = UserDefaults.standard.object(forKey: "monitorX") as? Double,
           let y = UserDefaults.standard.object(forKey: "monitorY") as? Double {
            self.setFrameOrigin(NSPoint(x: x, y: y))
        } else if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            // Top-right, below menu bar
            let x = screenFrame.maxX - 296
            let y = screenFrame.maxY - 60
            self.setFrameOrigin(NSPoint(x: x, y: y))
        }
    }

    func savePosition() {
        UserDefaults.standard.set(self.frame.origin.x, forKey: "monitorX")
        UserDefaults.standard.set(self.frame.origin.y, forKey: "monitorY")
    }
}

// MARK: - Click-through Hosting View

class ClickHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var isOpaque: Bool { false }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        // Ensure no default background peeks through rounded corners.
        // Corner radius is set externally via updateCornerRadius() to match the active skin.
        wantsLayer = true
        layer?.backgroundColor = .clear
        superview?.wantsLayer = true
        superview?.layer?.backgroundColor = .clear
        window?.isOpaque = false
        window?.backgroundColor = .clear
        window?.contentView?.wantsLayer = true
        window?.contentView?.layer?.backgroundColor = .clear
    }
}

// MARK: - Window Drag Handle (NSViewRepresentable)

struct WindowDragHandle: NSViewRepresentable {
    func makeNSView(context: Context) -> DragHandleNSView { DragHandleNSView() }
    func updateNSView(_ nsView: DragHandleNSView, context: Context) {}

    class DragHandleNSView: NSView {
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        override func mouseDown(with event: NSEvent) {
            window?.performDrag(with: event)
        }
    }
}

// MARK: - App Delegate

class AppDelegate: NSObject, NSApplicationDelegate {
    var panel: FloatingPanel!
    let reader = SessionReader()
    let configManager = ConfigManager()
    let instanceLock = AppInstanceLock()
    var usageFetcher: UsageFetcher!
    var sizeObserver: AnyCancellable?
    var skinObserver: AnyCancellable?

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard instanceLock.acquire() else {
            NSLog("[AgentMonitor] Singleton: another instance is already running")
            NSApp.terminate(nil)
            return
        }

        NSApp.setActivationPolicy(.accessory)

        usageFetcher = UsageFetcher(enabled: configManager.usageEnabled)

        // Start the Unix socket server for permission responses
        PermissionSocketServer.shared.start()

        panel = FloatingPanel()

        let hostingView = ClickHostingView(
            rootView: MonitorContentView(reader: reader, configManager: configManager, usageFetcher: usageFetcher)
        )
        hostingView.frame = NSRect(origin: .zero, size: NSSize(width: 280, height: 40))
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = .clear

        panel.contentView = hostingView

        // Update corner radius + panel appearance when skin changes
        updateCornerRadius()
        updatePanelAppearance()
        skinObserver = configManager.$currentSkin
            .sink { [weak self] _ in
                self?.updateCornerRadius()
                self?.updatePanelAppearance()
            }

        panel.restorePosition()
        panel.orderFrontRegardless()

        // Auto-resize panel to fit content
        sizeObserver = hostingView.publisher(for: \.fittingSize)
            .debounce(for: .milliseconds(50), scheduler: RunLoop.main)
            .sink { [weak self] newSize in
                guard let self = self, let panel = self.panel else { return }
                let origin = panel.frame.origin
                // Grow downward from top edge, width always fixed at 280
                let topY = origin.y + panel.frame.height
                let newOrigin = NSPoint(x: origin.x, y: topY - newSize.height)
                panel.setFrame(
                    NSRect(origin: newOrigin, size: NSSize(width: 280, height: newSize.height)),
                    display: true,
                    animate: false
                )
            }

        // Save position on drag
        NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification,
            object: panel,
            queue: .main
        ) { [weak self] _ in
            self?.panel.savePosition()
        }

        // Re-show panel after screen wake, space change, or display reconfiguration
        let workspace = NSWorkspace.shared.notificationCenter
        workspace.addObserver(forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.panel.orderFrontRegardless()
        }
        workspace.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.panel.orderFrontRegardless()
        }
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self = self, let panel = self.panel else { return }
            // Ensure panel is still on a visible screen
            if let screen = NSScreen.main {
                let screenFrame = screen.visibleFrame
                let panelOrigin = panel.frame.origin
                if !screenFrame.contains(panelOrigin) {
                    panel.restorePosition()
                }
            }
            panel.orderFrontRegardless()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        PermissionSocketServer.shared.stop()
        instanceLock.release()
    }

    private func updateCornerRadius() {
        guard let hostingView = panel?.contentView else { return }
        hostingView.layer?.cornerRadius = configManager.currentSkin.cornerRadius
        hostingView.layer?.cornerCurve = .continuous
        hostingView.layer?.masksToBounds = true
    }

    private func updatePanelAppearance() {
        guard let panel = panel else { return }
        // Glass: lock to dark so the .hudWindow material always renders as a
        // dark frosted pane (matches Dock / Control Center) regardless of
        // wallpaper brightness, keeping the hardcoded white text legible.
        // Other skins: clear so they follow system appearance.
        if configManager.currentSkin.id == "glass" {
            panel.appearance = NSAppearance(named: .darkAqua)
        } else {
            panel.appearance = nil
        }
    }
}

// MARK: - Main Entry Point

@main
struct AgentMonitorApp {
    static func migrateUserDefaultsFromClaudeMonitor() {
        let defaults = UserDefaults.standard
        if defaults.bool(forKey: "__migratedFromClaudeMonitor") { return }

        let oldPlistPath = NSHomeDirectory() + "/Library/Preferences/claude_monitor.plist"
        guard FileManager.default.fileExists(atPath: oldPlistPath),
              let oldDict = NSDictionary(contentsOfFile: oldPlistPath) as? [String: Any] else {
            defaults.set(true, forKey: "__migratedFromClaudeMonitor")
            return
        }

        var migratedCount = 0
        for (key, value) in oldDict where defaults.object(forKey: key) == nil {
            defaults.set(value, forKey: key)
            migratedCount += 1
        }

        if migratedCount > 0 {
            NSLog("[AgentMonitor] Migrated %d key(s) from claude_monitor.plist", migratedCount)
        }
        defaults.set(true, forKey: "__migratedFromClaudeMonitor")
        try? FileManager.default.removeItem(atPath: oldPlistPath)
    }

    static func main() {
        migrateUserDefaultsFromClaudeMonitor()
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }
}
