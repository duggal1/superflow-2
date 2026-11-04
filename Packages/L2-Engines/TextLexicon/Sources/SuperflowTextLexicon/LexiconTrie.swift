import Foundation

/// Character trie over normalized dictionary triggers. Matching walks the
/// normalized character stream and only accepts terminals that land on a token
/// boundary, so a trigger can never end in the middle of a word.
struct LexiconTrie: Sendable {
    struct Node: Sendable {
        var children: [Character: Int] = [:]
        var terminals: [Int] = []
    }

    private(set) var nodes: [Node] = [Node()]

    mutating func insert(_ characters: [Character], entry: Int) {
        guard !characters.isEmpty else { return }
        var node = 0
        for character in characters {
            if let next = nodes[node].children[character] {
                node = next
            } else {
                let created = nodes.count
                nodes.append(Node())
                nodes[node].children[character] = created
                node = created
            }
        }
        nodes[node].terminals.append(entry)
    }

    /// Longest terminal reachable from `start` that ends on a token boundary.
    func longestMatch(in stream: LexiconStream, from start: Int,
                      accepting: (Int) -> Bool = { _ in true }) -> (entry: Int, end: Int)? {
        guard start < stream.characters.count else { return nil }
        var node = 0
        var best: (entry: Int, end: Int)?
        var index = start
        while index < stream.characters.count {
            guard let next = nodes[node].children[stream.characters[index]] else { break }
            node = next
            index += 1
            if stream.isTokenEnd[index - 1],
               let terminal = nodes[node].terminals.first(where: accepting) {
                best = (terminal, index)
            }
        }
        return best
    }
}
