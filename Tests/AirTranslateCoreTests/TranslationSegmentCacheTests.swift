import Testing
@testable import AirTranslate

@Suite
struct TranslationSegmentCacheTests {
    @Test
    func cacheHitRefreshesLeastRecentlyUsedOrder() {
        var cache = TranslationSegmentCache(capacity: 2)
        cache.insert("first", forKey: "a")
        cache.insert("second", forKey: "b")

        #expect(cache.value(forKey: "a") == "first")
        cache.insert("third", forKey: "c")

        #expect(cache.value(forKey: "b") == nil)
        #expect(cache.value(forKey: "a") == "first")
        #expect(cache.value(forKey: "c") == "third")
    }

    @Test
    func repeatedHitsDoNotIncreaseCount() {
        var cache = TranslationSegmentCache(capacity: 2)
        cache.insert("value", forKey: "key")

        for _ in 0..<100 {
            #expect(cache.value(forKey: "key") == "value")
        }

        #expect(cache.count == 1)
    }

    @Test
    func overwriteRefreshesValueAndRecency() {
        var cache = TranslationSegmentCache(capacity: 2)
        cache.insert("old", forKey: "a")
        cache.insert("second", forKey: "b")
        cache.insert("new", forKey: "a")
        cache.insert("third", forKey: "c")

        #expect(cache.value(forKey: "a") == "new")
        #expect(cache.value(forKey: "b") == nil)
        #expect(cache.value(forKey: "c") == "third")
        #expect(cache.count == 2)
    }

    @Test
    func removeAllClearsEntries() {
        var cache = TranslationSegmentCache(capacity: 2)
        cache.insert("first", forKey: "a")
        cache.insert("second", forKey: "b")

        cache.removeAll()

        #expect(cache.count == 0)
        #expect(cache.value(forKey: "a") == nil)
        #expect(cache.value(forKey: "b") == nil)
    }

    @Test
    func capacityOneEvictsPreviousEntryOnInsert() {
        var cache = TranslationSegmentCache(capacity: 1)
        cache.insert("first", forKey: "a")
        #expect(cache.value(forKey: "a") == "first")
        cache.insert("second", forKey: "b")
        #expect(cache.count == 1)
        #expect(cache.value(forKey: "a") == nil)
        #expect(cache.value(forKey: "b") == "second")
    }

    @Test
    func lruEvictionRemainsAccurateAtCapacity() {
        var cache = TranslationSegmentCache(capacity: 64)
        for index in 0..<64 {
            cache.insert("v\(index)", forKey: "k\(index)")
        }
        // Refresh the oldest entry so k1 becomes the LRU victim.
        #expect(cache.value(forKey: "k0") == "v0")
        cache.insert("v64", forKey: "k64")

        #expect(cache.count == 64)
        #expect(cache.value(forKey: "k1") == nil)
        #expect(cache.value(forKey: "k0") == "v0")
        #expect(cache.value(forKey: "k64") == "v64")
    }
}
