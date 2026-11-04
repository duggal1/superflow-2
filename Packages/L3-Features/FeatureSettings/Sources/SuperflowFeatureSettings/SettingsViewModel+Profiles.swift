import SuperflowDesignSystem
import SuperflowKernel
import SuperflowUIComponents

extension SettingsViewModel {
    public var profile: ModelProfile { ModelProfile.byID(settings.asrProfile) }
    /// Streaming only, default first. Dictation has no batch path.
    public var profileOptions: [String] {
        let compatible = settings.asrRuntime == .sherpaOnnx
            ? [ModelProfile.default]
            : ModelProfile.streamingProfiles
        return compatible
            .sorted { lhs, rhs in
                if lhs.id == ModelProfile.default.id { return true }
                if rhs.id == ModelProfile.default.id { return false }
                return lhs.displayName < rhs.displayName
            }
            .map(\.id)
    }

    public func profileName(_ id: String) -> String { ModelProfile.byID(id).displayName }

    public func profileStatusLabel(_ id: String) -> String {
        let profile = ModelProfile.byID(id)
        if !profile.streaming { return "Not for dictation" }
        switch profile.status {
        case .verified: return "Verified"
        case .unverified: return "Experimental"
        case .unavailable: return "Unavailable"
        }
    }

    public func profileStatusVariant(_ id: String) -> BadgeVariant {
        let profile = ModelProfile.byID(id)
        if !profile.streaming { return .neutral }
        switch profile.status {
        case .verified: return .green
        case .unverified: return .orange
        case .unavailable: return .neutral
        }
    }

}
