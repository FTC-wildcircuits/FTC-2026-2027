//
//  FTCScoutAPIClient.swift
//  FTCTeamHub
//
//  Expanded GraphQL client for api.ftcscout.org/graphql. Adds multi-season
//  OPR history, events-attended history, and alliance-partner frequency —
//  built on top of the `quickStats(season:)` query pattern already proven
//  to work earlier in this project.
//
//  ⚠️ SCHEMA NOTE: `fetchTeamOPR`/`fetchSeasonHistory` use the exact field
//  names already confirmed working (`teamByNumber`, `quickStats`). The
//  newer `fetchEventsAttended` and `fetchAlliancePartners` queries below
//  use FTCScout's established naming conventions but were NOT verified
//  against live schema introspection in this session (the sandbox this
//  code was written in couldn't reach the GraphQL introspection endpoint).
//  If either call surfaces a GraphQL error in the app, open
//  https://api.ftcscout.org/graphql in a browser, use the Playground's
//  schema docs panel (top right) to find the exact field name, and adjust
//  the query string here. Nothing will crash — errors surface as plain
//  text in the UI via `FTCScoutAPIError`.
//

import Foundation

// MARK: - DTOs

struct FTCTeamOPR: Codable, Identifiable, Hashable {
    var id: Int { number }
    let number: Int
    let name: String
    let autoOPR: Double
    let teleOpOPR: Double
    let endgameOPR: Double
    var totalOPR: Double { autoOPR + teleOpOPR + endgameOPR }
}

struct FTCSeasonStat: Identifiable, Hashable {
    var id: Int { season }
    let season: Int
    let autoOPR: Double
    let teleOpOPR: Double
    let endgameOPR: Double
    var totalOPR: Double { autoOPR + teleOpOPR + endgameOPR }
}

struct FTCEventSummary: Codable, Identifiable, Hashable {
    let code: String
    let name: String
    let start: String
    let end: String
    var id: String { code }
}

struct FTCEventAttended: Identifiable, Hashable {
    var id: String { event.code }
    let event: FTCEventSummary
}

/// A team that has shared an alliance with the searched team at least once,
/// aggregated across every match returned for a given event. Win/loss isn't
/// tracked here (that requires the exact score-field names to be verified
/// against the live schema first) — this focuses on the reliably-derivable
/// signal: how often you've actually played alongside this team.
struct FTCAlliancePartner: Identifiable, Hashable {
    var id: Int { teamNumber }
    let teamNumber: Int
    var matchesTogether: Int
}

enum FTCScoutAPIError: LocalizedError {
    case invalidResponse
    case graphQLErrors([String])
    case transport(Error)

    var errorDescription: String? {
        switch self {
        case .invalidResponse: return "The server returned an unreadable response."
        case .graphQLErrors(let messages): return messages.joined(separator: "\n")
        case .transport(let err): return err.localizedDescription
        }
    }
}

// MARK: - Service protocol

protocol FTCScoutAPIServicing {
    func fetchTeamOPR(teamNumber: Int, season: Int) async throws -> FTCTeamOPR
    func fetchSeasonHistory(teamNumber: Int, seasons: [Int]) async throws -> [FTCSeasonStat]
    func fetchEvents(season: Int) async throws -> [FTCEventSummary]
    func fetchEventsAttended(teamNumber: Int, season: Int) async throws -> [FTCEventAttended]
    func fetchAlliancePartners(teamNumber: Int, eventCode: String, season: Int) async throws -> [FTCAlliancePartner]
}

// MARK: - Live GraphQL implementation

final class LiveFTCScoutAPIClient: FTCScoutAPIServicing {

    private let endpoint = URL(string: "https://api.ftcscout.org/graphql")!
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    private func execute<T: Decodable>(query: String,
                                        variables: [String: Any],
                                        dataKeyPath: [String]) async throws -> T {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["query": query, "variables": variables])

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw FTCScoutAPIError.transport(error)
        }

        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
            throw FTCScoutAPIError.invalidResponse
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw FTCScoutAPIError.invalidResponse
        }

        if let errors = json["errors"] as? [[String: Any]] {
            let messages = errors.compactMap { $0["message"] as? String }
            throw FTCScoutAPIError.graphQLErrors(messages)
        }

        guard var cursor: Any = json["data"] else { throw FTCScoutAPIError.invalidResponse }
        for key in dataKeyPath {
            guard let dict = cursor as? [String: Any], let next = dict[key] else {
                throw FTCScoutAPIError.invalidResponse
            }
            cursor = next
        }

        let cursorData = try JSONSerialization.data(withJSONObject: cursor)
        return try JSONDecoder().decode(T.self, from: cursorData)
    }

    // MARK: Single-season OPR (proven-working pattern)

    func fetchTeamOPR(teamNumber: Int, season: Int) async throws -> FTCTeamOPR {
        let query = """
        query TeamOPR($number: Int!, $season: Int!) {
          teamByNumber(number: $number) {
            number
            name
            quickStats(season: $season) {
              auto { value }
              dc { value }
              eg { value }
            }
          }
        }
        """

        struct RawTeam: Decodable {
            struct Stat: Decodable { let value: Double? }
            struct QuickStats: Decodable { let auto: Stat?; let dc: Stat?; let eg: Stat? }
            let number: Int
            let name: String?
            let quickStats: QuickStats?
        }

        let raw: RawTeam = try await execute(
            query: query,
            variables: ["number": teamNumber, "season": season],
            dataKeyPath: ["teamByNumber"]
        )

        return FTCTeamOPR(
            number: raw.number,
            name: raw.name ?? "Team \(raw.number)",
            autoOPR: raw.quickStats?.auto?.value ?? 0,
            teleOpOPR: raw.quickStats?.dc?.value ?? 0,
            endgameOPR: raw.quickStats?.eg?.value ?? 0
        )
    }

    // MARK: Multi-season history — reuses the proven single-season call in parallel

    func fetchSeasonHistory(teamNumber: Int, seasons: [Int]) async throws -> [FTCSeasonStat] {
        try await withThrowingTaskGroup(of: FTCSeasonStat?.self) { group in
            for season in seasons {
                group.addTask {
                    // A season with no data throws a GraphQL error (team didn't
                    // compete that year) — swallow that single season rather
                    // than failing the whole multi-season fetch.
                    guard let opr = try? await self.fetchTeamOPR(teamNumber: teamNumber, season: season) else {
                        return nil
                    }
                    return FTCSeasonStat(season: season, autoOPR: opr.autoOPR,
                                          teleOpOPR: opr.teleOpOPR, endgameOPR: opr.endgameOPR)
                }
            }
            var results: [FTCSeasonStat] = []
            for try await result in group {
                if let result { results.append(result) }
            }
            return results.sorted { $0.season < $1.season }
        }
    }

    func fetchEvents(season: Int) async throws -> [FTCEventSummary] {
        let query = """
        query Events($season: Int!) {
          eventsSearch(season: $season, limit: 50) {
            code
            name
            start
            end
          }
        }
        """
        return try await execute(
            query: query,
            variables: ["season": season],
            dataKeyPath: ["eventsSearch"]
        )
    }

    // MARK: Events attended (best-effort schema — see file header note)

    func fetchEventsAttended(teamNumber: Int, season: Int) async throws -> [FTCEventAttended] {
        let query = """
        query TeamEvents($number: Int!, $season: Int!) {
          teamByNumber(number: $number) {
            events(season: $season) {
              event {
                code
                name
                start
                end
              }
            }
          }
        }
        """
        struct RawEventWrapper: Decodable { let event: FTCEventSummary }
        struct RawTeamEvents: Decodable { let events: [RawEventWrapper] }

        let raw: RawTeamEvents = try await execute(
            query: query,
            variables: ["number": teamNumber, "season": season],
            dataKeyPath: ["teamByNumber"]
        )
        return raw.events.map { FTCEventAttended(event: $0.event) }
    }

    // MARK: Alliance partner frequency (best-effort schema — see file header note)

    func fetchAlliancePartners(teamNumber: Int, eventCode: String, season: Int) async throws -> [FTCAlliancePartner] {
        let query = """
        query EventMatches($season: Int!, $eventCode: String!) {
          eventByCode(season: $season, code: $eventCode) {
            matches {
              teams {
                alliance
                teamNumber
              }
            }
          }
        }
        """
        struct RawTeamSlot: Decodable { let alliance: String; let teamNumber: Int }
        struct RawMatch: Decodable { let teams: [RawTeamSlot] }
        struct RawEvent: Decodable { let matches: [RawMatch] }

        let raw: RawEvent = try await execute(
            query: query,
            variables: ["season": season, "eventCode": eventCode],
            dataKeyPath: ["eventByCode"]
        )

        var counts: [Int: Int] = [:]
        for match in raw.matches {
            guard let mine = match.teams.first(where: { $0.teamNumber == teamNumber }) else { continue }
            let partners = match.teams.filter { $0.alliance == mine.alliance && $0.teamNumber != teamNumber }
            for partner in partners {
                counts[partner.teamNumber, default: 0] += 1
            }
        }
        return counts.map { FTCAlliancePartner(teamNumber: $0.key, matchesTogether: $0.value) }
            .sorted { $0.matchesTogether > $1.matchesTogether }
    }
}
