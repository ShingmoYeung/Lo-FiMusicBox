import Foundation

@MainActor
final class FocusTimeService: ObservableObject {
    @Published private(set) var todayFocusMinutes: Int = 0
    @Published private(set) var focusHistory: [String: Int] = [:]

    private let userDefaults: UserDefaults
    private let calendar: Calendar
    private var currentDateString: String
    private var focusTimer: Timer?
    private var isPlaybackActive = false

    init(userDefaults: UserDefaults = .standard, calendar: Calendar = .current) {
        self.userDefaults = userDefaults
        self.calendar = calendar
        currentDateString = Self.makeDateString(from: Date(), calendar: calendar)
        loadStoredFocusData()
        resetTodayIfNeeded()
    }

    func updatePlaybackState(isPlaying: Bool) {
        isPlaybackActive = isPlaying
        isPlaying ? startTimerIfNeeded() : stopTimer()
    }

    func resetTodayFocus() {
        todayFocusMinutes = 0
        currentDateString = Self.makeDateString(from: Date(), calendar: calendar)
        saveCurrentFocusData()
    }

    private func startTimerIfNeeded() {
        guard focusTimer == nil else { return }
        focusTimer = Timer.scheduledTimer(
            withTimeInterval: AppConstants.FocusTimer.tickIntervalSeconds,
            repeats: true
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handleTimerTick()
            }
        }
    }

    private func stopTimer() {
        focusTimer?.invalidate()
        focusTimer = nil
    }

    private func handleTimerTick() {
        resetTodayIfNeeded()
        guard isPlaybackActive else { return }
        todayFocusMinutes += 1
        saveCurrentFocusData()
    }

    private func loadStoredFocusData() {
        if let currentData = userDefaults.dictionary(
            forKey: AppConstants.FocusTimer.currentFocusStorageKey
        ) {
            todayFocusMinutes = currentData["minutes"] as? Int ?? 0
            currentDateString = currentData["date"] as? String ?? currentDateString
        }

        focusHistory = userDefaults.dictionary(
            forKey: AppConstants.FocusTimer.focusHistoryStorageKey
        ) as? [String: Int] ?? [:]
    }

    private func resetTodayIfNeeded() {
        let todayString = Self.makeDateString(from: Date(), calendar: calendar)
        guard currentDateString != todayString else { return }

        archiveCurrentDate()
        todayFocusMinutes = 0
        currentDateString = todayString
        saveCurrentFocusData()
    }

    private func archiveCurrentDate() {
        guard todayFocusMinutes > 0 else { return }
        focusHistory[currentDateString] = todayFocusMinutes
        removeExpiredHistory()
        userDefaults.set(focusHistory, forKey: AppConstants.FocusTimer.focusHistoryStorageKey)
    }

    private func removeExpiredHistory() {
        guard let cutoffDate = calendar.date(
            byAdding: .day,
            value: -AppConstants.FocusTimer.retainedHistoryDays,
            to: Date()
        ) else {
            return
        }

        let cutoffDateString = Self.makeDateString(from: cutoffDate, calendar: calendar)
        focusHistory = focusHistory.filter { dateString, _ in
            dateString >= cutoffDateString
        }
    }

    private func saveCurrentFocusData() {
        archiveCurrentDate()
        userDefaults.set(
            [
                "date": currentDateString,
                "minutes": todayFocusMinutes
            ],
            forKey: AppConstants.FocusTimer.currentFocusStorageKey
        )
    }

    private static func makeDateString(from date: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        let year = components.year ?? 0
        let month = components.month ?? 1
        let day = components.day ?? 1
        return String(format: "%04d-%02d-%02d", year, month, day)
    }
}
