import Foundation

/// A "use this engine right now" recommendation computed across every coding
/// provider's exact usage. This is the payoff of being multi-provider: pick the
/// engine with the most headroom at its binding constraint, or — when all are
/// tight — point at whichever frees up soonest.
public struct FuelRecommendation: Equatable, Sendable {
    public let provider: Provider
    public let title: String            // e.g. "Codex · 5h"
    public let remainingPercent: Int    // headroom at the chosen engine's binding lane
    public let isConstrained: Bool      // true when even the best engine is low
    public let state: UsageState        // for colouring the row
    public let detail: String           // e.g. "88% free · resets in 4h"
    public let launchCommand: String?   // one-click copy, when the engine has a CLI

    public init(provider: Provider, title: String, remainingPercent: Int, isConstrained: Bool,
                state: UsageState, detail: String, launchCommand: String?) {
        self.provider = provider
        self.title = title
        self.remainingPercent = remainingPercent
        self.isConstrained = isConstrained
        self.state = state
        self.detail = detail
        self.launchCommand = launchCommand
    }
}

public enum FuelRouter {
    /// Providers that represent an interactive coding engine you'd actually
    /// "switch to" — excludes pure API-spend lanes (OpenAI/OpenRouter $).
    static let codingProviders: Set<Provider> = [.claudeCode, .claude, .codex, .cursor, .gemini, .copilot, .openCode]

    /// Returns a recommendation only when 2+ comparable engines exist (routing
    /// is meaningless with a single engine).
    public static func recommend(snapshots: [UsageSnapshot], now: Date) -> FuelRecommendation? {
        let candidates = snapshots.filter {
            codingProviders.contains($0.provider) && $0.usagePercent != nil && !$0.isSubscriptionOnly
        }
        let byProvider = Dictionary(grouping: candidates, by: \.provider)
        guard byProvider.count >= 2 else { return nil }

        // Per provider, the binding constraint is its tightest lane (highest used).
        struct Fuel { let provider: Provider; let remaining: Double; let title: UsageSnapshot; let binding: UsageSnapshot }
        let fuels: [Fuel] = byProvider.compactMap { provider, lanes in
            guard let binding = lanes.max(by: { ($0.usagePercent ?? 0) < ($1.usagePercent ?? 0) }) else { return nil }
            let remaining = max(0, 1 - (binding.usagePercent ?? 1))
            let titleLane = lanes.first(where: isSessionWindow) ?? binding
            return Fuel(provider: provider, remaining: remaining, title: titleLane, binding: binding)
        }
        guard let best = fuels.max(by: { $0.remaining < $1.remaining }) else { return nil }
        let bestPercent = Int((best.remaining * 100).rounded())

        if bestPercent >= 15 {
            var detail = "\(bestPercent)% free"
            if let reset = best.binding.reset?.compactTitle { detail += " · resets in \(reset)" }
            return FuelRecommendation(
                provider: best.provider,
                title: laneTitle(best.title),
                remainingPercent: bestPercent,
                isConstrained: false,
                state: state(forRemaining: best.remaining),
                detail: detail,
                launchCommand: launchCommand(best.provider)
            )
        }

        // Everything is tight → point at whatever resets soonest.
        let soonest = candidates
            .compactMap { snapshot -> (UsageSnapshot, TimeInterval)? in
                guard let seconds = snapshot.reset?.secondsRemaining, seconds > 0 else { return nil }
                return (snapshot, seconds)
            }
            .min(by: { $0.1 < $1.1 })?.0

        if let soonest {
            return FuelRecommendation(
                provider: soonest.provider,
                title: laneTitle(soonest),
                remainingPercent: bestPercent,
                isConstrained: true,
                state: .critical,
                detail: "All engines tight · \(soonest.provider.displayName) resets in \(soonest.reset?.compactTitle ?? "soon")",
                launchCommand: nil
            )
        }
        return FuelRecommendation(
            provider: best.provider,
            title: laneTitle(best.title),
            remainingPercent: bestPercent,
            isConstrained: true,
            state: .critical,
            detail: "All engines tight",
            launchCommand: nil
        )
    }

    static func isSessionWindow(_ snapshot: UsageSnapshot) -> Bool {
        let label = snapshot.label.lowercased()
        return label.contains("5h") || label.contains("session")
    }

    static func laneTitle(_ snapshot: UsageSnapshot) -> String {
        "\(snapshot.provider.displayName) · \(snapshot.label)"
    }

    static func state(forRemaining remaining: Double) -> UsageState {
        if remaining >= 0.4 { return .safe }
        if remaining >= 0.15 { return .caution }
        return .critical
    }

    static func launchCommand(_ provider: Provider) -> String? {
        switch provider {
        case .claudeCode, .claude: return "claude"
        case .codex: return "codex"
        case .gemini: return "gemini"
        case .cursor: return "cursor"
        case .openCode: return "opencode"
        case .copilot, .openAI, .openRouter, .anthropic: return nil
        }
    }
}
