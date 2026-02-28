import Foundation
import CloudKit
import Combine

// MARK: - Couple Walk Manager
// NOTE: Requires the CloudKit capability to be enabled in Xcode project settings.
// Add via: Project → Target → Signing & Capabilities → + Capability → CloudKit

class CoupleWalkManager: ObservableObject {
    static let shared = CoupleWalkManager()

    // MARK: - Published State

    @Published var partnerProfile: PartnerProfile?
    @Published var sharedWalkSlots: [SharedWalkSlot] = []
    @Published var pendingInviteCode: String?
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var isLinked = false

    // MARK: - CloudKit Configuration

    private let container = CKContainer(identifier: "iCloud.com.activslot.healthapp")
    private var database: CKDatabase { container.publicCloudDatabase }

    // Record types
    private let inviteRecordType = "WalkBuddyInvite"
    private let profileRecordType = "WalkBuddyProfile"

    // MARK: - Dependencies

    private let calendarManager: CalendarManager
    private let userPreferences: UserPreferences

    private init(
        calendarManager: CalendarManager = .shared,
        userPreferences: UserPreferences = .shared
    ) {
        self.calendarManager = calendarManager
        self.userPreferences = userPreferences
        loadSavedPartner()
    }

    // MARK: - Persistence

    private var savedPartnerKey = "savedPartnerProfile"

    private func loadSavedPartner() {
        guard let data = UserDefaults.standard.data(forKey: savedPartnerKey),
              let profile = try? JSONDecoder().decode(PartnerProfile.self, from: data)
        else { return }
        partnerProfile = profile
        isLinked = true
    }

    private func savePartner(_ profile: PartnerProfile) {
        if let data = try? JSONEncoder().encode(profile) {
            UserDefaults.standard.set(data, forKey: savedPartnerKey)
        }
        partnerProfile = profile
        isLinked = true
    }

    func unlinkPartner() {
        UserDefaults.standard.removeObject(forKey: savedPartnerKey)
        partnerProfile = nil
        sharedWalkSlots = []
        isLinked = false
        pendingInviteCode = nil
    }

    // MARK: - Mock / Debug Setup

    #if DEBUG
    /// Links a mock partner for simulator testing (bypasses CloudKit).
    /// - Parameters:
    ///   - name: Display name for the partner.
    ///   - schedule: Array of (startHour, durationMinutes) tuples. Defaults to Alex's staggered schedule.
    @MainActor
    func linkMockPartner(name: String = "Alex (demo)", schedule: [(Int, Int)]? = nil) async {
        let today = Calendar.current.startOfDay(for: Date())
        func makeBlock(hour: Int, durationMin: Int) -> BusyBlock {
            let start = Calendar.current.date(bySettingHour: hour, minute: 0, second: 0, of: today)!
            let end = Calendar.current.date(byAdding: .minute, value: durationMin, to: start)!
            return BusyBlock(start: start, end: end)
        }
        let defaultSchedule = [(8,30),(10,60),(13,45),(15,60),(17,30)]
        let mockBusy = (schedule ?? defaultSchedule).map { makeBlock(hour: $0.0, durationMin: $0.1) }

        let profile = PartnerProfile(
            partnerName: name,
            cloudKitRecordID: "mock-\(name.lowercased().replacingOccurrences(of: " ", with: "-"))-ck-id",
            freeBusyBlocks: mockBusy,
            preferredWalkStartHour: 7,
            preferredWalkEndHour: 19,
            linkedAt: Date()
        )
        savePartner(profile)
        await refreshSharedSlots()
    }
    #endif

    // MARK: - Invite Code Generation

    /// Generates a 6-character invite code and uploads the user's free/busy blocks to CloudKit.
    /// The partner enters this code to link their account.
    @MainActor
    func generateInviteCode() async throws -> String {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        // Generate a unique 6-character alphanumeric code
        let code = generateRandomCode(length: 6)

        // Compute today's busy blocks from the calendar
        let today = Date()
        let busyBlocks = await computeBusyBlocks(for: today)

        // Build the invite record
        let record = CKRecord(recordType: inviteRecordType, recordID: CKRecord.ID(recordName: code))
        record["code"] = code
        record["senderName"] = displayName()
        record["createdAt"] = today
        record["preferredWalkStartHour"] = walkTimeWindow().start
        record["preferredWalkEndHour"] = walkTimeWindow().end

        // Encode busy blocks as JSON
        let blocksData = try JSONEncoder().encode(busyBlocks)
        record["freeBusyBlocks"] = String(data: blocksData, encoding: .utf8)

        // Also store sender's CloudKit user record ID
        let userRecordID = try await container.userRecordID()
        record["senderCloudKitID"] = userRecordID.recordName

        try await database.save(record)

        pendingInviteCode = code
        return code
    }

    // MARK: - Accept Invite

    /// Accepts a partner's invite code and links the two accounts.
    @MainActor
    func acceptInvite(code: String) async throws {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        let recordID = CKRecord.ID(recordName: code.uppercased())
        let record = try await database.record(for: recordID)

        // Parse invite fields
        guard
            let partnerName = record["senderName"] as? String,
            let partnerCloudKitID = record["senderCloudKitID"] as? String,
            let createdAt = record["createdAt"] as? Date,
            !Date().timeIntervalSince(createdAt).isGreater(than: 72 * 3600)
        else {
            throw CoupleWalkError.invalidOrExpiredCode
        }

        // Decode partner's busy blocks
        var busyBlocks: [BusyBlock] = []
        if let blocksString = record["freeBusyBlocks"] as? String,
           let blocksData = blocksString.data(using: .utf8) {
            busyBlocks = (try? JSONDecoder().decode([BusyBlock].self, from: blocksData)) ?? []
        }

        let startHour = (record["preferredWalkStartHour"] as? Int) ?? 7
        let endHour = (record["preferredWalkEndHour"] as? Int) ?? 19

        let profile = PartnerProfile(
            partnerName: partnerName,
            cloudKitRecordID: partnerCloudKitID,
            freeBusyBlocks: busyBlocks,
            preferredWalkStartHour: startHour,
            preferredWalkEndHour: endHour,
            linkedAt: Date()
        )

        savePartner(profile)

        // Upload own busy blocks so partner can also see shared slots
        try await uploadOwnProfile()

        // Find shared walk slots right away
        await refreshSharedSlots()
    }

    // MARK: - Refresh Shared Slots

    /// Fetches partner's latest availability and finds shared walk slots.
    @MainActor
    func refreshSharedSlots(for date: Date = Date()) async {
        guard var partner = partnerProfile else { return }
        isLoading = true
        defer { isLoading = false }

        // Try to fetch partner's latest free/busy from CloudKit
        if let freshBlocks = try? await fetchPartnerBusyBlocks(recordID: partner.cloudKitRecordID) {
            partner.freeBusyBlocks = freshBlocks
            savePartner(partner)
        }

        sharedWalkSlots = await findSharedWalkSlots(date: date)
    }

    // MARK: - Shared Slot Algorithm

    /// Finds walk slots where both partners are free.
    /// Steps:
    ///  1. Get own free slots from CalendarManager
    ///  2. Get partner's busy blocks
    ///  3. Intersect: keep slots where partner is also free
    ///  4. Filter: both within preferred walk time window
    ///  5. Rank: by overlap with historical peak activity hours
    ///  6. Return top 3
    func findSharedWalkSlots(date: Date) async -> [SharedWalkSlot] {
        guard let partner = partnerProfile else { return [] }

        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        guard let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) else { return [] }

        // 1. Get own free slots from the movement plan
        let ownBusyBlocks = await computeBusyBlocks(for: date)

        // 2. Compute own free slots (gaps between busy blocks within active hours)
        let myPrefs = userPreferences
        let ownFreeSlots = computeFreeSlots(
            busyBlocks: ownBusyBlocks,
            dayStart: startOfDay,
            dayEnd: endOfDay,
            walkStartHour: walkTimeWindow().start,
            walkEndHour: walkTimeWindow().end
        )

        // 3. Partner's busy blocks for this date
        let partnerBusyToday = partner.freeBusyBlocks.filter { block in
            let blockDate = calendar.startOfDay(for: block.start)
            return calendar.isDate(blockDate, inSameDayAs: date)
        }

        // 4. Find slots where partner is also free
        let minDuration: TimeInterval = 20 * 60 // 20 minutes minimum

        var sharedSlots: [SharedWalkSlot] = []

        for ownSlot in ownFreeSlots {
            // Check that this slot doesn't overlap with any partner busy block
            let partnerIsFree = !partnerBusyToday.contains { busy in
                ownSlot.start < busy.end && ownSlot.end > busy.start
            }
            guard partnerIsFree else { continue }

            // Check slot falls within BOTH partners' preferred walk windows
            let slotHour = calendar.component(.hour, from: ownSlot.start)
            let inOwnWindow = slotHour >= myPrefs.wakeTime.hour + 1 && slotHour < myPrefs.sleepTime.hour - 1
            let inPartnerWindow = slotHour >= partner.preferredWalkStartHour && slotHour < partner.preferredWalkEndHour
            guard inOwnWindow && inPartnerWindow else { continue }

            // Ensure minimum duration
            guard ownSlot.duration >= minDuration else { continue }

            // Cap slot at 60 minutes for suggestions
            let suggestedDuration = min(Int(ownSlot.duration / 60), 60)

            // Confidence: higher if slot is in both partners' ideal windows
            let idealStart = max(walkTimeWindow().start, partner.preferredWalkStartHour)
            let idealEnd = min(walkTimeWindow().end, partner.preferredWalkEndHour)
            let inIdeal = slotHour >= idealStart && slotHour < idealEnd
            let confidence = inIdeal ? 0.9 : 0.6

            sharedSlots.append(SharedWalkSlot(
                startTime: ownSlot.start,
                duration: suggestedDuration,
                confidenceScore: confidence
            ))
        }

        // 5. Sort by confidence, then by time
        return Array(
            sharedSlots
                .sorted { $0.confidenceScore > $1.confidenceScore || ($0.confidenceScore == $1.confidenceScore && $0.startTime < $1.startTime) }
                .prefix(3)
        )
    }

    // MARK: - Private Helpers

    private func computeBusyBlocks(for date: Date) async -> [BusyBlock] {
        let events = (try? await calendarManager.fetchEvents(for: date)) ?? []
        return events
            .filter { !$0.isAllDay }
            .map { BusyBlock(start: $0.startDate, end: $0.endDate) }
    }

    private func computeFreeSlots(
        busyBlocks: [BusyBlock],
        dayStart: Date,
        dayEnd: Date,
        walkStartHour: Int,
        walkEndHour: Int
    ) -> [DateInterval] {
        let calendar = Calendar.current
        var components = calendar.dateComponents([.year, .month, .day], from: dayStart)
        components.hour = walkStartHour
        let windowStart = calendar.date(from: components) ?? dayStart
        components.hour = walkEndHour
        let windowEnd = calendar.date(from: components) ?? dayEnd

        // Sort busy blocks within the window
        let sorted = busyBlocks
            .filter { $0.start < windowEnd && $0.end > windowStart }
            .sorted { $0.start < $1.start }

        var freeSlots: [DateInterval] = []
        var cursor = windowStart

        for busy in sorted {
            let busyStart = max(busy.start, windowStart)
            if cursor < busyStart {
                freeSlots.append(DateInterval(start: cursor, end: busyStart))
            }
            cursor = max(cursor, busy.end)
        }

        if cursor < windowEnd {
            freeSlots.append(DateInterval(start: cursor, end: windowEnd))
        }

        return freeSlots
    }

    private func walkTimeWindow() -> (start: Int, end: Int) {
        switch userPreferences.preferredWalkTime {
        case .morning: return (start: 7, end: 12)
        case .afternoon: return (start: 12, end: 17)
        case .evening: return (start: 17, end: 20)
        case .noPreference: return (start: 7, end: 20)
        }
    }

    private func displayName() -> String {
        // Use first part of user email if available, else a generic name
        if let email = OutlookManager.shared.userEmail {
            return email.components(separatedBy: "@").first?.capitalized ?? "Your Partner"
        }
        return "Your Partner"
    }

    private func generateRandomCode(length: Int) -> String {
        let chars = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"  // No O, 0, I, 1 to avoid confusion
        return String((0..<length).compactMap { _ in chars.randomElement() })
    }

    // MARK: - CloudKit Upload

    private func uploadOwnProfile() async throws {
        let userRecordID = try await container.userRecordID()
        let busyBlocks = await computeBusyBlocks(for: Date())

        let record = CKRecord(recordType: profileRecordType, recordID: CKRecord.ID(recordName: userRecordID.recordName))
        record["displayName"] = displayName()
        record["preferredWalkStartHour"] = walkTimeWindow().start
        record["preferredWalkEndHour"] = walkTimeWindow().end

        let blocksData = try JSONEncoder().encode(busyBlocks)
        record["freeBusyBlocks"] = String(data: blocksData, encoding: .utf8)
        record["updatedAt"] = Date()

        _ = try await database.save(record)
    }

    private func fetchPartnerBusyBlocks(recordID: String) async throws -> [BusyBlock] {
        let record = try await database.record(for: CKRecord.ID(recordName: recordID))
        guard let blocksString = record["freeBusyBlocks"] as? String,
              let blocksData = blocksString.data(using: .utf8)
        else { return [] }
        return try JSONDecoder().decode([BusyBlock].self, from: blocksData)
    }
}

// MARK: - Errors

enum CoupleWalkError: LocalizedError {
    case invalidOrExpiredCode
    case partnerNotFound
    case cloudKitUnavailable
    case noCalendarAccess

    var errorDescription: String? {
        switch self {
        case .invalidOrExpiredCode:
            return "The invite code is invalid or has expired (codes expire after 72 hours)."
        case .partnerNotFound:
            return "Couldn't find your partner's profile. Ask them to generate a new code."
        case .cloudKitUnavailable:
            return "iCloud is unavailable. Please sign in to iCloud in Settings."
        case .noCalendarAccess:
            return "Calendar access is required to share availability with your partner."
        }
    }
}

// MARK: - TimeInterval helper

private extension TimeInterval {
    func isGreater(than value: TimeInterval) -> Bool {
        self > value
    }
}
