import Foundation
import ZhongmiaoCore

struct MujianDashboard: Codable, Hashable, Sendable {
    var totalRecords: Int?
    var totalCost: Double?
    var avgRating: Double?
    var totalCities: Int?

    enum CodingKeys: String, CodingKey {
        case totalRecords = "total_records"
        case totalCost = "total_cost"
        case avgRating = "avg_rating"
        case totalCities = "total_cities"
    }
}

struct MujianSnapshot: Codable, Sendable {
    var dashboard: MujianDashboard?
    var upcoming: [Show]
}
