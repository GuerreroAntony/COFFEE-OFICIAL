import Foundation

// MARK: - CacheManager
// Thread-safe in-memory cache with TTL for stale-while-revalidate pattern.
// Usage: Show cached data instantly, fetch fresh in background, update UI when ready.

final class CacheManager: @unchecked Sendable {

    static let shared = CacheManager()

    // MARK: - TTL Defaults (seconds)

    /// 5 minutes for list data (disciplines, recordings, events)
    static let listTTL: TimeInterval = 300
    /// 2 minutes for profile/detail data
    static let detailTTL: TimeInterval = 120

    // MARK: - Internal

    private struct CacheEntry {
        let data: Any
        let timestamp: Date
        let ttl: TimeInterval
    }

    private var store: [String: CacheEntry] = [:]
    private let queue = DispatchQueue(label: "com.coffee.cache", attributes: .concurrent)

    private init() {}

    // MARK: - Public API

    /// Get cached data if it exists (regardless of TTL — for stale-while-revalidate).
    func get<T>(_ key: String) -> T? {
        queue.sync {
            store[key]?.data as? T
        }
    }

    /// Get cached data only if within TTL.
    func getFresh<T>(_ key: String) -> T? {
        queue.sync {
            guard let entry = store[key],
                  Date().timeIntervalSince(entry.timestamp) < entry.ttl else {
                return nil
            }
            return entry.data as? T
        }
    }

    /// Check if cache entry exists and is still fresh (within TTL).
    func isFresh(_ key: String) -> Bool {
        queue.sync {
            guard let entry = store[key] else { return false }
            return Date().timeIntervalSince(entry.timestamp) < entry.ttl
        }
    }

    /// Save data to cache with specified TTL.
    func set(_ key: String, data: Any, ttl: TimeInterval = CacheManager.listTTL) {
        queue.async(flags: .barrier) {
            self.store[key] = CacheEntry(data: data, timestamp: Date(), ttl: ttl)
        }
    }

    /// Remove a specific cache entry.
    func invalidate(_ key: String) {
        queue.async(flags: .barrier) {
            self.store.removeValue(forKey: key)
        }
    }

    /// Remove all entries whose key starts with the given prefix.
    func invalidatePrefix(_ prefix: String) {
        queue.async(flags: .barrier) {
            self.store = self.store.filter { !$0.key.hasPrefix(prefix) }
        }
    }

    /// Clear all cached data (e.g., on logout).
    func invalidateAll() {
        queue.async(flags: .barrier) {
            self.store.removeAll()
        }
    }
}
