import Foundation

extension KeyedDecodingContainer {
    /// The value for `key`, or `fallback` when it is missing or of another type: an old or hand-edited file
    /// loses one field, never the whole file (`docs/04-data.md` §1).
    public func value<T: Decodable>(_ key: Key, default fallback: T) -> T {
        (try? decodeIfPresent(T.self, forKey: key)) ?? fallback
    }
}
