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

    /// Storage index of the `offset`-th newest element (0 == newest).
    private func storageIndex(newestOffset offset: Int) -> Int {
        guard storage.count == capacity else {
            // Not yet wrapped: `head` is still 0 and storage is oldest-first.
            return storage.count - 1 - offset
        }
        // Wrapped: `head` is the oldest slot, so the newest sits just behind it.
        return (head + capacity - 1 - offset) % capacity
    }

    /// The most recent elements, newest-first. This lets live views render a
    /// bounded window without reducing the buffer retained for other callers.
    /// Walks only as far back as `limit`, so a large buffer costs nothing extra.
    func newestFirst(limit: Int) -> [Element] {
        let wanted = min(limit, storage.count)
        guard wanted > 0 else { return [] }
        var result: [Element] = []
        result.reserveCapacity(wanted)
        for offset in 0..<wanted {
            result.append(storage[storageIndex(newestOffset: offset)])
        }
        return result
    }

    /// The most recent elements matching `predicate`, newest-first, stopping as
    /// soon as `limit` is reached. Avoids materializing the whole buffer just to
    /// pull a handful of matches out of the newest end.
    func newestFirst(limit: Int, where predicate: (Element) -> Bool) -> [Element] {
        guard limit > 0 else { return [] }
        var result: [Element] = []
        result.reserveCapacity(limit)
        for offset in 0..<storage.count {
            let element = storage[storageIndex(newestOffset: offset)]
            if predicate(element) {
                result.append(element)
                if result.count == limit { break }
            }
        }
        return result
    }
}

extension RingBuffer: Sendable where Element: Sendable {}
