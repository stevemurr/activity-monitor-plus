/// Fixed-capacity buffer that discards the oldest elements once full.
struct RingBuffer<Element> {
    private var storage: [Element] = []
    private var head = 0
    let capacity: Int

    init(capacity: Int) {
        precondition(capacity > 0)
        self.capacity = capacity
    }

    var count: Int { storage.count }
    var isEmpty: Bool { storage.isEmpty }

    mutating func append(_ element: Element) {
        if storage.count < capacity {
            storage.append(element)
        } else {
            storage[head] = element
            head = (head + 1) % capacity
        }
    }

    mutating func append(contentsOf newElements: some Sequence<Element>) {
        for element in newElements { append(element) }
    }

    mutating func removeAll() {
        storage.removeAll()
        head = 0
    }

    /// Oldest-first.
    var elements: [Element] {
        guard storage.count == capacity, head > 0 else { return storage }
        return Array(storage[head...]) + Array(storage[..<head])
    }
}

extension RingBuffer: Sendable where Element: Sendable {}
