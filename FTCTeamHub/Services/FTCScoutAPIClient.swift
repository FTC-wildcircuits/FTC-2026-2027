//
//  FTCScoutAPIClient.swift
//  FTCTeamHub
//
//  Dependency-injectable GraphQL client for the real, public FTCScout API
//  (https://api.ftcscout.org/graphql — confirmed live, no authentication
//  required). Hand-rolled query strings + Codable decoding keep this lean
//  without pulling in Apollo/codegen tooling.
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

struct FTCEventSummary: Codable, Identifiable, Hashable {
    let code: String
    let name: String
    let start: String
    let end: String
    var id: String { code }
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
    func fetchEvents(season: Int) async throws -> [FTCEventSummary]
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
}
