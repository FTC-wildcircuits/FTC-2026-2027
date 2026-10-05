import Foundation
import SwiftData

@Model
final class TeamEventRecord {
    @Attribute(.unique) var id: String
    var title: String
    var category: String
    var startsAt: Date
    var timeDescription: String
    var venue: String
    var address: String
    var details: String

    init(
        id: String = UUID().uuidString,
        title: String = "",
        category: String = "Event",
        startsAt: Date = .now,
        timeDescription: String = "",
        venue: String = "",
        address: String = "",
        details: String = ""
    ) {
        self.id = id
        self.title = title
        self.category = category
        self.startsAt = startsAt
        self.timeDescription = timeDescription
        self.venue = venue
        self.address = address
        self.details = details
    }
}
