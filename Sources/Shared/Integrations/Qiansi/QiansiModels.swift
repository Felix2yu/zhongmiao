import Foundation

struct QiansiPerson: Codable, Hashable, Sendable, Identifiable {
    var id: String
    var name: String
    var familyName: String?
    var givenName: String?
    var nickname: String?
    var gender: String?
    var birthday: String?
    var birthdayIsLunar: Bool?
    var phone: String?
    var wechat: String?
    var location: String?
    var notes: String?
    var grade: Int?
    var archived: Bool?
    var intimacy: Int?
    var birthdayAnniversaryID: String?
    var stats: QiansiPersonStats?

    enum CodingKeys: String, CodingKey {
        case id, name, nickname, gender, birthday, phone, wechat, location, notes, grade, archived, intimacy, stats
        case familyName = "family_name"
        case givenName = "given_name"
        case birthdayIsLunar = "birthday_is_lunar"
        case birthdayAnniversaryID = "birthday_anniversary_id"
    }
}

struct QiansiPersonStats: Codable, Hashable, Sendable {
    var lastContact: String?
    var meetingCount: Int?
    var avgMeetingGapDays: Int?
    var netFen: Int?

    enum CodingKeys: String, CodingKey {
        case lastContact = "last_contact"
        case meetingCount = "meeting_count"
        case avgMeetingGapDays = "avg_meeting_gap_days"
        case netFen = "net_fen"
    }
}

struct QiansiAnniversary: Codable, Hashable, Sendable, Identifiable {
    var id: String
    var personId: String?
    var title: String
    var date: String
    var isLunar: Bool?
    var repeatYearly: Bool?
    var remindDays: String?
    var createdAt: String?
    var personName: String?
    var nextDate: String?
    var daysUntil: Int?

    enum CodingKeys: String, CodingKey {
        case id, title, date
        case personId = "person_id"
        case isLunar = "is_lunar"
        case repeatYearly = "repeat_yearly"
        case remindDays = "remind_days"
        case createdAt = "created_at"
        case personName = "person_name"
        case nextDate = "next_date"
        case daysUntil = "days_until"
    }

    var remindDayOffsets: [Int] {
        (remindDays ?? "7,3,1,0")
            .split(separator: ",")
            .compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
    }
}

struct QiansiReminder: Codable, Hashable, Sendable, Identifiable {
    var id: String
    var personId: String?
    var refType: String?
    var refId: String?
    var title: String
    var dueAt: String
    var status: String?
    var createdAt: String?
    var completedAt: String?
    var personName: String?

    enum CodingKeys: String, CodingKey {
        case id, title, status
        case personId = "person_id"
        case refType = "ref_type"
        case refId = "ref_id"
        case dueAt = "due_at"
        case createdAt = "created_at"
        case completedAt = "completed_at"
        case personName = "person_name"
    }
}

struct QiansiEvent: Codable, Hashable, Sendable, Identifiable {
    var id: String
    var title: String
    var eventDate: String
    var location: String?
    var summary: String?
    var participants: [QiansiPerson]?
    var typeName: String?
    var typeColor: String?
    var hasGift: Bool?
    var giftAmountFen: Int?
    var billCount: Int?

    enum CodingKeys: String, CodingKey {
        case id, title, location, summary, participants
        case eventDate = "event_date"
        case typeName = "type_name"
        case typeColor = "type_color"
        case hasGift = "has_gift"
        case giftAmountFen = "gift_amount_fen"
        case billCount = "bill_count"
    }
}

struct QiansiStats: Codable, Hashable, Sendable {
    var totalPeople: Int?
    var totalEvents: Int?
    var upcomingDays7: Int?
    var dueToday: Int?
    var lendFen: Int?
    var borrowFen: Int?
    var pendingPromises: Int?

    enum CodingKeys: String, CodingKey {
        case totalPeople = "total_people"
        case totalEvents = "total_events"
        case upcomingDays7 = "upcoming_days7"
        case dueToday = "due_today"
        case lendFen = "lend_fen"
        case borrowFen = "borrow_fen"
        case pendingPromises = "pending_promises"
    }
}

struct QiansiSnapshot: Codable, Sendable {
    var people: [QiansiPerson]
    var anniversaries: [QiansiAnniversary]
    var reminders: [QiansiReminder]
    var events: [QiansiEvent]
    var stats: QiansiStats?
}

struct QiansiAgendaItem: Identifiable, Hashable, Sendable {

    enum Kind: String, Sendable {
        case anniversary
        case event
        case reminder

        var title: String {
            switch self {
            case .anniversary: "生日/纪念日"
            case .event: "约会"
            case .reminder: "提醒"
            }
        }

        var symbol: String {
            switch self {
            case .anniversary: "birthday.cake"
            case .event: "calendar"
            case .reminder: "bell"
            }
        }
    }

    var id: String
    var date: Date
    var title: String
    var subtitle: String
    var kind: Kind
    var reminderID: String?
    var personID: String?
    var daysUntil: Int?
}
