//
//  TabRouter.swift
//  FTCTeamHub
//
//  Lets the Dashboard's quick-action buttons jump directly to another tab
//  (e.g. tapping "3 tasks due" takes you straight to the Tasks tab).
//

import Foundation
import Observation

enum AppTab: String, CaseIterable {
    case dashboard, roster, testing, tasks, notebook, ideas, pitOps, chat, liveData, team
}

@MainActor
@Observable
final class TabRouter {
    var selection: AppTab = .dashboard
}
