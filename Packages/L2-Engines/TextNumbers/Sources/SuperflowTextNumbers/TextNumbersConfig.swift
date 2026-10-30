public struct TextNumbersConfig: Sendable {
    public enum CurrencyStyle: Sendable { case abbreviated, full }
    public enum Grouping: Sendable { case auto, western, indian }

    public var smallNumberThreshold = 10
    public var currencyStyle: CurrencyStyle = .abbreviated
    public var grouping: Grouping = .auto
    public var minDigitRun = 4
    public init() {}
}
