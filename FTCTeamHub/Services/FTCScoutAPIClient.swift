//
//  FTCScoutAPIClient.swift
//  FTCTeamHub
//
//  A dependency-injectable GraphQL client for the real, public FTCScout API
//  (https://api.ftcscout.org/graphql — no authentication required, confirmed
//  live endpoint as of 2026). No third-party GraphQL SDK is used: FTCScout's
//  schema is small enough that hand-rolled query strings + Codable decoding
//  keep the binary lean and avoid Apollo/Codegen build-time complexity.
//
//  Architecture: `FTCScoutAPIServicing` is the protocol every ViewModel
//  depends on. `LiveFTCScoutAPIClient` talks to the network; a
//  `PreviewFTCScoutAPIClient` (see MockBackendService.swift) satisfies the
//  same protocol for SwiftUI previews and unit tests — classic dependency
//  inversion (the "D" in SOLID).
//

import Foundation

// MARK: - DTOs (mirror FTCScout GraphQL schema)

struct FTCTeamOPR: Codable, Identifiable, Hashable {
    var id: Int { number }
    let number: Int
    let name: String
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

struct FTCMatchSchedule: Codable, Identifiable, Hashable {
    let matchNumber: Int
    let scheduledStartTime: String?
    let redTeams: [Int]
    let blueTeams: [Int]
    var id: Int { matchNumber }
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

// MARK: - Service protocol (what ViewModels actually depend on)

protocol FTCScoutAPIServicing {
    func fetchTeamOPR(teamNumber: Int, season: Int) async throws -> FTCTeamOPR
    func fetchEvents(season: Int, regionCode: String?) async throws -> [FTCEventSummary]
    func fetchMatchSchedule(eventCode: String, season: Int) async throws -> [FTCMatchSchedule]
}

// MARK: - Live GraphQL implementation

final class LiveFTCScoutAPIClient: FTCScoutAPIServicing {

    private let endpoint = URL(string: "https://api.ftcscout.org/graphql")!
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    /// Generic GraphQL POST helper. Keeps every call site free of boilerplate
    /// request-building — a single source of truth for headers/encoding.
    private func execute<T: Decodable>(query: String,
                                        variables: [String: Any],
                                        dataKeyPath: [String]) async throws -> T {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = ["query": query, "variables": variables]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
            throw FTCScoutAPIError.invalidResponse
        }

        guard var json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
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
        // FTCScout nests OPR under quickStats.{auto,dc,eg}.value; we flatten
        // it into our own DTO shape at the decode boundary below.
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

    func fetchEvents(season: Int, regionCode: String? = nil) async throws -> [FTCEventSummary] {
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

    func fetchMatchSchedule(eventCode: String, season: Int) async throws -> [FTCMatchSchedule] {
        let query = """
        query Matches($season: Int!, $eventCode: String!) {
          eventByCode(season: $season, code: $eventCode) {
            matches {
              matchNum
              scheduledStartTime
              teams {
                alliance
                teamNumber
              }
            }
          }
        }
        """
        struct RawEvent: Decodable {
            struct RawTeamSlot: Decodable { let alliance: String; let teamNumber: Int }
            struct RawMatch: Decodable {
                let matchNum: Int
                let scheduledStartTime: String?
                let teams: [RawTeamSlot]
            }
            let matches: [RawMatch]
        }

        let raw: RawEvent = try await execute(
            query: query,
            variables: ["season": season, "eventCode": eventCode],
            dataKeyPath: ["eventByCode"]
        )

        return raw.matches.map { m in
            FTCMatchSchedule(
                matchNumber: m.matchNum,
                scheduledStartTime: m.scheduledStartTime,
                redTeams: m.teams.filter { $0.alliance == "Red" }.map(\.teamNumber),
                blueTeams: m.teams.filter { $0.alliance == "Blue" }.map(\.teamNumber)
            )
        }
    }
}
