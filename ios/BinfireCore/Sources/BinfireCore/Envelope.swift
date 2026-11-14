import Foundation

/// HashBin document envelopes (`spec/state.md` "Envelopes").
public enum Envelope {
    /// Classifies a document's bytes: `"source"` for a JSON string,
    /// `"<format>:<type>"` or `"<format>"` for an envelope object, else nil.
    public static func documentType(_ bytes: Data) -> String? {
        guard let text = decodeUTF8Strict(bytes),
              let value = try? JSONValue.parse(Data(text.utf8)) else { return nil }
        switch value {
        case .string: return "source"
        case .object(let o):
            guard case .string(let format)? = o["format"] else { return nil }
            if case .string(let type)? = o["type"] { return "\(format):\(type)" }
            return format
        default: return nil
        }
    }

    /// Every registry app that lists `key`, in file order.
    public static func appsForDocumentType(_ key: String, in registry: Registry) -> [RegistryApp] {
        registry.appsForDocumentType(key)
    }
}
