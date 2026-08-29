// ios/PetHomepage/DesignSystem/DailyShuffle.swift
import Foundation

/// Picks one element from a list per calendar day, deterministically.
///
/// The pick is a pure function of (day, salt, count), which buys three things: it is stable
/// for a whole day so a photo never swaps under the user's finger, two activities on the same
/// day pick independently because each passes its own salt, and tests assert real values
/// without mocking randomness.
enum DailyShuffle {
    /// Picks the element for `date`'s calendar day. Returns nil only for an empty list.
    static func pick<T>(_ items: [T], on date: Date, salt: UUID,
                        calendar: Calendar = .current) -> T? {
        guard !items.isEmpty else { return nil }
        let day = calendar.startOfDay(for: date)
        let dayNumber = Int((day.timeIntervalSince1970 / 86_400).rounded(.down))
        return items[index(count: items.count, dayNumber: dayNumber, salt: salt)]
    }

    /// Exposed for tests: the index this (day, salt) resolves to for a list of `count`.
    static func index(count: Int, dayNumber: Int, salt: UUID) -> Int {
        precondition(count > 0)
        return Int(mix(dayNumber, salt) % UInt64(count))
    }

    /// FNV-1a over the day number and the salt's 16 bytes.
    ///
    /// Swift's `Hasher` deliberately CANNOT be used here: it is seeded randomly per process,
    /// so the same day and salt would hash differently on every launch and the pick would
    /// change each time the app cold-starts. That failure is invisible to a single-process
    /// test run, which is why `testMixIsDeterministicAcrossProcesses` pins literal values.
    private static func mix(_ dayNumber: Int, _ salt: UUID) -> UInt64 {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        let prime: UInt64 = 0x0000_0100_0000_01b3
        func feed(_ byte: UInt8) {
            hash ^= UInt64(byte)
            hash = hash &* prime
        }
        withUnsafeBytes(of: Int64(dayNumber).littleEndian) { $0.forEach(feed) }
        withUnsafeBytes(of: salt.uuid) { $0.forEach(feed) }
        return hash
    }
}
