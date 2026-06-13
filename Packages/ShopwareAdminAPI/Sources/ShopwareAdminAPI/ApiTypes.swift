import Foundation

// Value types produced by the API facades (InstanceApi.languages, StateMachineApi).

public struct LanguageOption: Sendable, Equatable, Identifiable {
    public let id: String
    public let name: String
    public let localeCode: String?

    public init(id: String, name: String, localeCode: String?) {
        self.id = id
        self.name = name
        self.localeCode = localeCode
    }
}

public struct StateTransition: Sendable, Equatable {
    public let actionName: String
    public let toStateName: String
    /// localized target-state name from the transition response
    public let displayName: String
    /// /_action/state-machine/{entity}/{id}/state/{action}
    public let url: String

    public init(actionName: String, toStateName: String, displayName: String, url: String) {
        self.actionName = actionName
        self.toStateName = toStateName
        self.displayName = displayName
        self.url = url
    }
}
