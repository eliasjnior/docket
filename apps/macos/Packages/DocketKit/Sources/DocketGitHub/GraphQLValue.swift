import Foundation

/// A GraphQL variable value.
enum GraphQLValue: Encodable, Sendable {
    case string(String)
    case strings([String])
    case bool(Bool)
    case null

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .strings(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }
}

struct GraphQLRequest: Encodable, Sendable {
    var query: String
    var variables: [String: GraphQLValue]
}
