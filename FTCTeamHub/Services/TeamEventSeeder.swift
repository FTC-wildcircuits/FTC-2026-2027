import Foundation
import SwiftData

enum TeamEventSeeder {
    private struct ProvidedEvent {
        let id: String
        let title: String
        let category: String
        let year: Int
        let month: Int
        let day: Int
        let time: String
        let venue: String
        let address: String
        let details: String
    }

    private static let providedSchedule = [
        ProvidedEvent(
            id: "practice-2026-10-10",
            title: "Practice Event",
            category: "Practice",
            year: 2026,
            month: 10,
            day: 10,
            time: "8:30 AM – 3:00 PM",
            venue: "Rowan University",
            address: "",
            details: "This practice event does not affect league standings."
        ),
        ProvidedEvent(
            id: "league-2026-10-24",
            title: "1st League Meet",
            category: "League meet",
            year: 2026,
            month: 10,
            day: 24,
            time: "8:30 AM – 4:30 PM",
            venue: "Holmdel High School",
            address: "36 Crawfords Corner Rd, Holmdel, NJ 07733",
            details: ""
        ),
        ProvidedEvent(
            id: "league-2026-11-15",
            title: "2nd League Meet",
            category: "League meet",
            year: 2026,
            month: 11,
            day: 15,
            time: "8:30 AM – 4:30 PM",
            venue: "Williamstown Middle School",
            address: "561 Clayton Rd, Williamstown, NJ",
            details: ""
        ),
        ProvidedEvent(
            id: "league-2027-01-23",
            title: "3rd League Meet",
            category: "League meet",
            year: 2027,
            month: 1,
            day: 23,
            time: "8:30 AM – 4:30 PM",
            venue: "Howell High School",
            address: "405 Squankum Yellowbrook Rd, Farmingdale, NJ",
            details: ""
        ),
        ProvidedEvent(
            id: "tournament-2027-02-27",
            title: "League Tournament",
            category: "Tournament",
            year: 2027,
            month: 2,
            day: 27,
            time: "8:30 AM – 4:30 PM",
            venue: "North Burlington County Middle School",
            address: "160 Mansfield Rd East, Columbus, NJ 08022",
            details: ""
        )
    ]

    @MainActor
    static func seedProvidedScheduleIfNeeded(in context: ModelContext) throws {
        let descriptor = FetchDescriptor<TeamEventRecord>()
        guard try context.fetch(descriptor).isEmpty else { return }

        let calendar = Calendar(identifier: .gregorian)
        let records = try providedSchedule.map { event -> TeamEventRecord in
            guard let date = calendar.date(from: DateComponents(
                year: event.year,
                month: event.month,
                day: event.day
            )) else {
                throw ScheduleError.invalidDate(event.title)
            }
            return TeamEventRecord(
                id: event.id,
                title: event.title,
                category: event.category,
                startsAt: date,
                timeDescription: event.time,
                venue: event.venue,
                address: event.address,
                details: event.details
            )
        }

        records.forEach(context.insert)
        try context.save()
    }

    private enum ScheduleError: LocalizedError {
        case invalidDate(String)

        var errorDescription: String? {
            switch self {
            case .invalidDate(let title):
                return "The saved event date for \(title) is invalid."
            }
        }
    }
}
