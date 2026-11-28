import Foundation

struct TranslationSegmentCache {
    private static let emptyIndex = -1

    private struct Node {
        var key: String
        var value: String
        var prev: Int
        var next: Int
    }

    private let capacity: Int
    private var nodes: [Node] = []
    private var indexByKey: [String: Int] = [:]
    private var head = emptyIndex
    private var tail = emptyIndex

    init(capacity: Int) {
        precondition(capacity > 0)
        self.capacity = capacity
        nodes.reserveCapacity(capacity)
        indexByKey.reserveCapacity(capacity)
    }

    var count: Int {
        indexByKey.count
    }

    mutating func value(forKey key: String) -> String? {
        guard let index = indexByKey[key] else { return nil }
        moveToHead(index)
        return nodes[index].value
    }

    mutating func insert(_ value: String, forKey key: String) {
        if let index = indexByKey[key] {
            nodes[index].value = value
            moveToHead(index)
            return
        }

        if indexByKey.count >= capacity, tail != Self.emptyIndex {
            let evictedIndex = tail
            indexByKey.removeValue(forKey: nodes[evictedIndex].key)
            unlink(evictedIndex)
            nodes[evictedIndex] = Node(
                key: key,
                value: value,
                prev: Self.emptyIndex,
                next: Self.emptyIndex
            )
            indexByKey[key] = evictedIndex
            linkAtHead(evictedIndex)
            return
        }

        let index = nodes.count
        nodes.append(
            Node(
                key: key,
                value: value,
                prev: Self.emptyIndex,
                next: Self.emptyIndex
            )
        )
        indexByKey[key] = index
        linkAtHead(index)
    }

    mutating func removeAll() {
        indexByKey.removeAll(keepingCapacity: true)
        nodes.removeAll(keepingCapacity: true)
        head = Self.emptyIndex
        tail = Self.emptyIndex
    }

    private mutating func moveToHead(_ index: Int) {
        guard index != head else { return }
        unlink(index)
        linkAtHead(index)
    }

    private mutating func linkAtHead(_ index: Int) {
        nodes[index].prev = Self.emptyIndex
        nodes[index].next = head
        if head != Self.emptyIndex {
            nodes[head].prev = index
        }
        head = index
        if tail == Self.emptyIndex {
            tail = index
        }
    }

    private mutating func unlink(_ index: Int) {
        let prev = nodes[index].prev
        let next = nodes[index].next
        if prev != Self.emptyIndex {
            nodes[prev].next = next
        } else {
            head = next
        }
        if next != Self.emptyIndex {
            nodes[next].prev = prev
        } else {
            tail = prev
        }
        nodes[index].prev = Self.emptyIndex
        nodes[index].next = Self.emptyIndex
    }
}
