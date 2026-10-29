import Foundation

public extension AppSettings {
    var implicitLists: Bool {
        get { ["lists", "list", "bullets"].contains(cleanupStructure.lowercased()) }
        set { cleanupStructure = newValue ? "lists" : "prose" }
    }
}
