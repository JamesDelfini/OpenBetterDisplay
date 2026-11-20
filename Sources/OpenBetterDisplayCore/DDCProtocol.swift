import Foundation

public enum DDCProtocol {
    public static let chipAddress: UInt32 = 0x37
    public static let writeDataAddress: UInt32 = 0x51
    public static let readDataAddress: UInt32 = 0x00
    public static let luminanceVCPCode: UInt8 = 0x10
    public static let minimumSoftwareGammaFloor: Double = 0.08

    public struct LuminanceReply: Equatable, Sendable {
        public let currentValue: Int
        public let maxValue: Int
        public let normalizedLevel: Double

        public init(currentValue: Int, maxValue: Int, normalizedLevel: Double) {
            self.currentValue = currentValue
            self.maxValue = maxValue
            self.normalizedLevel = normalizedLevel
        }
    }

    public struct ParsedEDID: Equatable, Sendable {
        public let vendorID: UInt32
        public let modelID: UInt32
        public let serialNumber: UInt32
        public let weekOfManufacture: Int
        public let yearOfManufacture: Int
        public let productName: String?
        public let alphanumericSerial: String?

        public init(
            vendorID: UInt32,
            modelID: UInt32,
            serialNumber: UInt32,
            weekOfManufacture: Int,
            yearOfManufacture: Int,
            productName: String?,
            alphanumericSerial: String?
        ) {
            self.vendorID = vendorID
            self.modelID = modelID
            self.serialNumber = serialNumber
            self.weekOfManufacture = weekOfManufacture
            self.yearOfManufacture = yearOfManufacture
            self.productName = productName
            self.alphanumericSerial = alphanumericSerial
        }
    }

    public struct DisplayMatchTarget: Equatable, Sendable {
        public let vendorID: UInt32
        public let modelID: UInt32
        public let serialNumber: UInt32
        public let productName: String?
        public let alphanumericSerial: String?
        public let weekOfManufacture: Int?
        public let yearOfManufacture: Int?
        public let ioDisplayLocation: String?

        public init(
            vendorID: UInt32,
            modelID: UInt32,
            serialNumber: UInt32,
            productName: String? = nil,
            alphanumericSerial: String? = nil,
            weekOfManufacture: Int? = nil,
            yearOfManufacture: Int? = nil,
            ioDisplayLocation: String? = nil
        ) {
            self.vendorID = vendorID
            self.modelID = modelID
            self.serialNumber = serialNumber
            self.productName = productName
            self.alphanumericSerial = alphanumericSerial
            self.weekOfManufacture = weekOfManufacture
            self.yearOfManufacture = yearOfManufacture
            self.ioDisplayLocation = ioDisplayLocation
        }
    }

    public struct DDCServiceCandidate: Equatable, Sendable {
        public let registryPath: String
        public let edid: ParsedEDID?

        public init(registryPath: String, edid: ParsedEDID?) {
            self.registryPath = registryPath
            self.edid = edid
        }
    }

    public static func makeGetLuminancePacket() -> [UInt8] {
        var packet: [UInt8] = [0x82, 0x01, luminanceVCPCode, 0x00]
        packet[3] = writeChecksum(for: packet[0..<3])
        return packet
    }

    public static func makeSetLuminancePacket(level: Double, maxValue: Int = 100) -> [UInt8] {
        let clamped = max(0.0, min(1.0, level))
        let effectiveMax = max(1, maxValue)
        let target = max(0, min(effectiveMax, Int((clamped * Double(effectiveMax)).rounded())))
        let valHi = UInt8((target >> 8) & 0xFF)
        let valLo = UInt8(target & 0xFF)

        var packet: [UInt8] = [0x84, 0x03, luminanceVCPCode, valHi, valLo, 0x00]
        packet[5] = writeChecksum(for: packet[0..<5])
        return packet
    }

    public static func parseLuminanceReply(_ reply: [UInt8]) -> LuminanceReply? {
        guard reply.count >= 11 else { return nil }

        let computedChecksum = reply[0..<10].reduce(UInt8(0x50), ^)
        guard computedChecksum == reply[10] else { return nil }
        guard reply[2] == 0x02, reply[3] == 0x00, reply[4] == luminanceVCPCode else { return nil }

        let maxValue = (Int(reply[6]) << 8) | Int(reply[7])
        let currentValue = (Int(reply[8]) << 8) | Int(reply[9])
        guard maxValue > 0 else { return nil }

        let normalized = min(1.0, max(0.0, Double(currentValue) / Double(maxValue)))
        return LuminanceReply(
            currentValue: currentValue,
            maxValue: maxValue,
            normalizedLevel: normalized
        )
    }

    public static func parseEDID(_ data: Data) -> ParsedEDID? {
        guard data.count >= 128 else { return nil }
        let bytes = [UInt8](data.prefix(128))
        let expectedHeader: [UInt8] = [0x00, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0x00]
        guard Array(bytes[0..<8]) == expectedHeader else { return nil }

        let vendorID = (UInt32(bytes[8]) << 8) | UInt32(bytes[9])
        let modelID = UInt32(bytes[10]) | (UInt32(bytes[11]) << 8)
        let serialNumber =
            UInt32(bytes[12])
            | (UInt32(bytes[13]) << 8)
            | (UInt32(bytes[14]) << 16)
            | (UInt32(bytes[15]) << 24)
        let week = Int(bytes[16])
        let year = 1990 + Int(bytes[17])

        var productName: String?
        var alphanumericSerial: String?

        for offset in [54, 72, 90, 108] {
            guard bytes[offset] == 0x00, bytes[offset + 1] == 0x00, bytes[offset + 2] == 0x00 else {
                continue
            }
            let tag = bytes[offset + 3]
            let slice = bytes[(offset + 5)..<(offset + 18)]
            let text = parseDescriptorText(slice)
            guard !text.isEmpty else { continue }

            if tag == 0xFC, productName == nil {
                productName = text
            } else if tag == 0xFF, alphanumericSerial == nil {
                alphanumericSerial = text
            }
        }

        return ParsedEDID(
            vendorID: vendorID,
            modelID: modelID,
            serialNumber: serialNumber,
            weekOfManufacture: week,
            yearOfManufacture: year,
            productName: productName,
            alphanumericSerial: alphanumericSerial
        )
    }

    public static func extractDisplayPipeToken(from ioDisplayLocation: String) -> String? {
        let pattern = #"/(disp(?:ext)?\d+)(?:@|/)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(ioDisplayLocation.startIndex..., in: ioDisplayLocation)
        guard let match = regex.firstMatch(in: ioDisplayLocation, range: range),
            let tokenRange = Range(match.range(at: 1), in: ioDisplayLocation)
        else {
            return nil
        }
        return String(ioDisplayLocation[tokenRange])
    }

    public static func matchScore(
        target: DisplayMatchTarget,
        candidate: DDCServiceCandidate
    ) -> Int? {
        var score = 0

        if let edid = candidate.edid {
            if target.vendorID != 0, edid.vendorID != 0 {
                guard edid.vendorID == target.vendorID else { return nil }
                score += 50
            }
            if target.modelID != 0, edid.modelID != 0 {
                guard edid.modelID == target.modelID else { return nil }
                score += 50
            }
            if target.serialNumber != 0, edid.serialNumber != 0 {
                guard edid.serialNumber == target.serialNumber else { return nil }
                score += 200
            }
            if let targetAlpha = normalizedToken(target.alphanumericSerial),
                let edidAlpha = normalizedToken(edid.alphanumericSerial)
            {
                guard targetAlpha == edidAlpha else { return nil }
                score += 200
            }
            if let targetName = normalizedToken(target.productName),
                let edidName = normalizedToken(edid.productName),
                targetName == edidName
            {
                score += 50
            }
            if let targetYear = target.yearOfManufacture,
                let targetWeek = target.weekOfManufacture,
                edid.yearOfManufacture == targetYear,
                edid.weekOfManufacture == targetWeek
            {
                score += 30
            }
        }

        if let location = target.ioDisplayLocation,
            let pipe = extractDisplayPipeToken(from: location),
            registryPathMatchesPipe(candidate.registryPath, pipe: pipe)
        {
            score += 80
        }

        return score > 0 ? score : nil
    }

    public static func makeSoftwareGammaTable(level: Double, sampleCount: Int = 256) -> [Float] {
        let count = max(2, sampleCount)
        let scale = Float(max(minimumSoftwareGammaFloor, min(1.0, level)))
        let maxIndex = Float(count - 1)
        return (0..<count).map { index in
            (Float(index) / maxIndex) * scale
        }
    }

    private static func writeChecksum(for payload: ArraySlice<UInt8>) -> UInt8 {
        let seed = UInt8((chipAddress << 1) & 0xFF) ^ UInt8(writeDataAddress & 0xFF)
        return payload.reduce(seed, ^)
    }

    private static func parseDescriptorText(_ bytes: ArraySlice<UInt8>) -> String {
        let rawBytes = bytes.prefix(while: { $0 != 0x0A && $0 != 0x00 })
        return String(bytes: rawBytes, encoding: .ascii)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private static func normalizedToken(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
            !trimmed.isEmpty
        else {
            return nil
        }
        return trimmed.lowercased()
    }

    private static func registryPathMatchesPipe(_ registryPath: String, pipe: String) -> Bool {
        if registryPath.contains("/\(pipe):")
            || registryPath.contains("/\(pipe)@")
            || registryPath.contains("/\(pipe)/")
        {
            return true
        }
        if pipe.hasPrefix("dispext") {
            let suffix = pipe.dropFirst("dispext".count)
            if registryPath.contains("/dcpext\(suffix)@") {
                return true
            }
        }
        return false
    }
}
