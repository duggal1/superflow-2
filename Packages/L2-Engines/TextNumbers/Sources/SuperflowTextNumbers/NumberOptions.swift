import SuperflowKernel

public struct NumberOptions: Sendable {
    public enum Small: Sendable { case digits, words }
    public enum Grouping: Sendable { case western, indian }
    public var small = Small.digits
    public var grouping = Grouping.western
    public var largeNumberStyle = LargeNumberStyle.full
    public init() {}
}
