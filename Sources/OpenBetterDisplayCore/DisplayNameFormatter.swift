import Foundation

public enum DisplayNameFormatter {
    private static let genericBuiltInNames: Set<String> = [
        "",
        "Color LCD",
        "Built-in Retina Display",
        "Built-in Liquid Retina Display",
        "Built-in Liquid Retina XDR Display",
        "Liquid Retina XDR Display",
        "Liquid Retina Display"
    ]

    public static func format(
        rawName: String,
        isBuiltIn: Bool,
        vendorID: UInt32,
        modelID: UInt32
    ) -> String {
        let trimmed = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        if isBuiltIn {
            return genericBuiltInNames.contains(trimmed) ? "Built-in Display" : trimmed
        }
        if !trimmed.isEmpty {
            return trimmed
        }
        return fallbackExternalName(vendorID: vendorID, modelID: modelID)
    }

    public static func fallbackExternalName(vendorID: UInt32, modelID: UInt32) -> String {
        if vendorID != 0 || modelID != 0 {
            return String(format: "External Display (%04X:%04X)", vendorID, modelID)
        }
        return "External Display"
    }

    public static func extractProductName(from infoDictionary: [String: Any]) -> String? {
        guard let productNames = infoDictionary["DisplayProductName"] as? [String: String] else {
            return nil
        }
        if let enUS = productNames["en_US"]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !enUS.isEmpty {
            return enUS
        }
        if let firstName = productNames.values
            .map({ $0.trimmingCharacters(in: .whitespacesAndNewlines) })
            .first(where: { !$0.isEmpty }) {
            return firstName
        }
        return nil
    }
}
