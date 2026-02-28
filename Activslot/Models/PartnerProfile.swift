import Foundation

// MARK: - Partner Profile

/// Represents a connected walk buddy partner.
/// Only free/busy blocks are stored — never meeting titles or attendee details.
struct PartnerProfile: Codable, Equatable {
    let partnerName: String
    let cloudKitRecordID: String
    /// Anonymized busy blocks from partner's calendar (start/end times only)
    var freeBusyBlocks: [BusyBlock]
    /// Preferred walk time window (hour of day, e.g. 7...9 = 7am–9am)
    var preferredWalkStartHour: Int
    var preferredWalkEndHour: Int
    var linkedAt: Date

    var preferredWalkTimeRange: ClosedRange<Int> {
        preferredWalkStartHour...preferredWalkEndHour
    }
}

// MARK: - Busy Block

/// An anonymized time block where the partner is unavailable.
/// Contains only start/end times — no meeting titles or attendees.
struct BusyBlock: Codable, Equatable {
    let start: Date
    let end: Date

    var duration: TimeInterval {
        end.timeIntervalSince(start)
    }

    var dateInterval: DateInterval {
        DateInterval(start: start, end: end)
    }
}

// MARK: - Shared Walk Slot

/// A walk slot where both partners are free, ranked by suitability.
struct SharedWalkSlot: Identifiable {
    let id = UUID()
    let startTime: Date
    let duration: Int                  // minutes
    let confidenceScore: Double        // 0.0–1.0 (higher = better overlap with both partners' patterns)

    var endTime: Date {
        startTime.addingTimeInterval(TimeInterval(duration * 60))
    }

    var formattedTime: String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: startTime)
    }

    var formattedDuration: String {
        duration >= 60 ? "\(duration / 60)h \(duration % 60)min" : "\(duration)min"
    }
}

// MARK: - Invite Code

struct WalkBuddyInvite: Codable {
    let code: String              // 6-character alphanumeric
    let senderRecordID: String
    let senderName: String
    let createdAt: Date
    var freeBusyBlocks: [BusyBlock]
    var preferredWalkStartHour: Int
    var preferredWalkEndHour: Int

    var isExpired: Bool {
        Date().timeIntervalSince(createdAt) > 72 * 3600 // 72-hour expiry
    }
}
