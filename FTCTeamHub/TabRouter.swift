//
//  TabRouter.swift
//  FTCTeamHub
//
//  Maps module-level destinations onto the smaller set of primary tabs.
//

import Foundation
import Observation

enum AppTab: String, CaseIterable {
    case dashboard, calendar
    case workHome, roster, testing, tasks, notebook, ideas
    case pitOps, inventory, chat, liveData, teamHome, team

    var rootTab: RootTab {
        switch self {
        case .dashboard: return .dashboard
        case .workHome, .calendar, .roster, .testing, .tasks, .notebook, .ideas: return .work
        case .pitOps, .inventory: return .pitOps
        case .liveData: return .scouting
        case .chat, .teamHome, .team: return .team
        }
    }
}

enum RootTab: Hashable, CaseIterable, Identifiable {
    case dashboard, work, pitOps, scouting, team

    var id: Self { self }

    var title: String {
        switch self {
        case .dashboard: return "Home"
        case .work: return "Build"
        case .pitOps: return "Pit"
        case .scouting: return "Scout"
        case .team: return "Team"
        }
    }

    var systemImage: String {
        switch self {
        case .dashboard: return "square.grid.2x2"
        case .work: return "hammer"
        case .pitOps: return "wrench.and.screwdriver"
        case .scouting: return "scope"
        case .team: return "person.2"
        }
    }
}

@MainActor
@Observable
final class TabRouter {
    var selection: AppTab = .dashboard

    var rootSelection: RootTab {
        selection.rootTab
    }

    func selectRoot(_ tab: RootTab) {
        switch tab {
        case .dashboard: selection = .dashboard
        case .work: selection = .workHome
        case .pitOps: selection = .pitOps
        case .scouting: selection = .liveData
        case .team: selection = .teamHome
        }
    }
}
