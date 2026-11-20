import Foundation
import XCTest
@testable import OpenBetterDisplayCore

final class DDCProtocolTests: XCTestCase {
    func testBuildsStandardGetLuminancePacketWithExpectedChecksum() {
        // VESA DDC/CI Get VCP Feature (0x01) for Luminance (0x10):
        // chk = (0x37 << 1) ^ 0x51 ^ 0x82 ^ 0x01 ^ 0x10 = 0xAC
        XCTAssertEqual(
            DDCProtocol.makeGetLuminancePacket(),
            [0x82, 0x01, 0x10, 0xAC]
        )
    }

    func testBuildsSetLuminancePacketsWithIndependentChecksums() {
        // Luminance = 50 / 100 (0x0032):
        // chk = 0x6E ^ 0x51 ^ 0x84 ^ 0x03 ^ 0x10 ^ 0x00 ^ 0x32 = 0x9A
        XCTAssertEqual(
            DDCProtocol.makeSetLuminancePacket(level: 0.50, maxValue: 100),
            [0x84, 0x03, 0x10, 0x00, 0x32, 0x9A]
        )

        // Clamps above 1.0 -> 100 (0x0064):
        // chk = 0x6E ^ 0x51 ^ 0x84 ^ 0x03 ^ 0x10 ^ 0x00 ^ 0x64 = 0xCC
        XCTAssertEqual(
            DDCProtocol.makeSetLuminancePacket(level: 1.5, maxValue: 100),
            [0x84, 0x03, 0x10, 0x00, 0x64, 0xCC]
        )

        // Clamps below 0.0 -> 0 (0x0000):
        // chk = 0x6E ^ 0x51 ^ 0x84 ^ 0x03 ^ 0x10 ^ 0x00 ^ 0x00 = 0xA8
        XCTAssertEqual(
            DDCProtocol.makeSetLuminancePacket(level: -0.2, maxValue: 100),
            [0x84, 0x03, 0x10, 0x00, 0x00, 0xA8]
        )

        // 16-bit maxValue = 1023, level = 0.5 -> rounded(511.5) = 512 (0x0200):
        // chk = 0x6E ^ 0x51 ^ 0x84 ^ 0x03 ^ 0x10 ^ 0x02 ^ 0x00 = 0xAA
        XCTAssertEqual(
            DDCProtocol.makeSetLuminancePacket(level: 0.5, maxValue: 1023),
            [0x84, 0x03, 0x10, 0x02, 0x00, 0xAA]
        )
    }

    func testParsesValidLuminanceReplyAndRejectsMalformedReplies() {
        // Valid 11-byte reply: max = 100 (0x0064), current = 75 (0x004B), chk = 0x8B
        let validReply: [UInt8] = [0x6E, 0x88, 0x02, 0x00, 0x10, 0x00, 0x00, 0x64, 0x00, 0x4B, 0x8B]
        let parsed = DDCProtocol.parseLuminanceReply(validReply)
        XCTAssertEqual(parsed?.currentValue, 75)
        XCTAssertEqual(parsed?.maxValue, 100)
        XCTAssertEqual(parsed?.normalizedLevel ?? -1, 0.75, accuracy: 0.0001)

        // Valid 16-bit reply: max = 1000 (0x03E8), current = 250 (0x00FA)
        // chk = 0x50 ^ 0x6E ^ 0x88 ^ 0x02 ^ 0x00 ^ 0x10 ^ 0x00 ^ 0x03 ^ 0xE8 ^ 0x00 ^ 0xFA = 0xB5
        let highResReply: [UInt8] = [0x6E, 0x88, 0x02, 0x00, 0x10, 0x00, 0x03, 0xE8, 0x00, 0xFA, 0xB5]
        let parsedHighRes = DDCProtocol.parseLuminanceReply(highResReply)
        XCTAssertEqual(parsedHighRes?.currentValue, 250)
        XCTAssertEqual(parsedHighRes?.maxValue, 1000)
        XCTAssertEqual(parsedHighRes?.normalizedLevel ?? -1, 0.25, accuracy: 0.0001)

        // Bad checksum
        var badChecksum = validReply
        badChecksum[10] ^= 0xFF
        XCTAssertNil(DDCProtocol.parseLuminanceReply(badChecksum))

        // Unsupported VCP result code (0x01) with valid checksum (0x8B ^ 0x01 = 0x8A)
        var unsupported = validReply
        unsupported[3] = 0x01
        unsupported[10] = 0x8A
        XCTAssertNil(DDCProtocol.parseLuminanceReply(unsupported))

        // Wrong VCP code (0x12 Contrast instead of 0x10) with valid checksum (0x8B ^ 0x02 = 0x89)
        var wrongVCP = validReply
        wrongVCP[4] = 0x12
        wrongVCP[10] = 0x89
        XCTAssertNil(DDCProtocol.parseLuminanceReply(wrongVCP))

        // Zero maxValue (division by zero protection) with valid checksum (0x8B ^ 0x64 = 0xEF)
        var zeroMax = validReply
        zeroMax[7] = 0x00
        zeroMax[10] = 0xEF
        XCTAssertNil(DDCProtocol.parseLuminanceReply(zeroMax))

        // Truncated packet
        XCTAssertNil(DDCProtocol.parseLuminanceReply([0x6E, 0x88, 0x02]))
    }

    func testParsesEDIDAndScoresAppleSiliconDCPAVServiceProxyCandidates() {
        var edid = Data(repeating: 0, count: 128)
        // Standard EDID header
        let header: [UInt8] = [0x00, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0x00]
        edid.replaceSubrange(0..<8, with: header)
        // DELL U2725QE identifiers: vendor 0x10AC, model 0x436B, serial 0x3332314C, week 44, year 2025 (35)
        edid[8] = 0x10
        edid[9] = 0xAC
        edid[10] = 0x6B
        edid[11] = 0x43
        edid[12] = 0x4C
        edid[13] = 0x31
        edid[14] = 0x32
        edid[15] = 0x33
        edid[16] = 44
        edid[17] = 35

        // Descriptor block at offset 54: tag 0xFC (Product Name "DELL U2725QE\n")
        let nameBytes: [UInt8] = [0x00, 0x00, 0x00, 0xFC, 0x00] + Array("DELL U2725QE\n".utf8)
        edid.replaceSubrange(54..<(54 + nameBytes.count), with: nameBytes)

        // Descriptor block at offset 72: tag 0xFF (Alphanumeric Serial "ABC1234\n")
        let serialBytes: [UInt8] = [0x00, 0x00, 0x00, 0xFF, 0x00] + Array("ABC1234\n     ".utf8)
        edid.replaceSubrange(72..<(72 + serialBytes.count), with: serialBytes)

        let parsed = DDCProtocol.parseEDID(edid)
        XCTAssertEqual(parsed?.vendorID, 0x10AC)
        XCTAssertEqual(parsed?.modelID, 0x436B)
        XCTAssertEqual(parsed?.serialNumber, 0x3332314C)
        XCTAssertEqual(parsed?.weekOfManufacture, 44)
        XCTAssertEqual(parsed?.yearOfManufacture, 2025)
        XCTAssertEqual(parsed?.productName, "DELL U2725QE")
        XCTAssertEqual(parsed?.alphanumericSerial, "ABC1234")

        // Pipe token extraction for M4 EPIC and M1-M3 IODisplayLocation paths
        let m4Location = "IOService:/AppleARMPE/arm-io@10F00000/AppleH16GFamilyIO/dispext0@A0000000/IOMobileFramebufferShim"
        XCTAssertEqual(DDCProtocol.extractDisplayPipeToken(from: m4Location), "dispext0")

        let target = DDCProtocol.DisplayMatchTarget(
            vendorID: 0x10AC,
            modelID: 0x436B,
            serialNumber: 0x3332314C,
            productName: "DELL U2725QE",
            alphanumericSerial: "ABC1234",
            weekOfManufacture: 44,
            yearOfManufacture: 2025,
            ioDisplayLocation: m4Location
        )

        let matchingCandidate = DDCProtocol.DDCServiceCandidate(
            registryPath: "IOService:/AppleARMPE/arm-io@10F00000/AppleH16GFamilyIO/dcpext0@A2E00000/dispext0:dcpav-service-epic:0/DCPAVServiceProxy",
            edid: parsed
        )
        let wrongPipeCandidate = DDCProtocol.DDCServiceCandidate(
            registryPath: "IOService:/AppleARMPE/arm-io@10F00000/AppleH16GFamilyIO/dcpext1@A2E00000/dispext1:dcpav-service-epic:0/DCPAVServiceProxy",
            edid: parsed
        )
        let differentMonitorCandidate = DDCProtocol.DDCServiceCandidate(
            registryPath: "IOService:/AppleARMPE/arm-io@10F00000/AppleH16GFamilyIO/dcpext1@A2E00000/dispext1:dcpav-service-epic:0/DCPAVServiceProxy",
            edid: DDCProtocol.ParsedEDID(
                vendorID: 0x10AC,
                modelID: 0xD0B3,
                serialNumber: 0x99999999,
                weekOfManufacture: 10,
                yearOfManufacture: 2020,
                productName: "DELL P2217H",
                alphanumericSerial: "XYZ9999"
            )
        )

        let matchingScore = DDCProtocol.matchScore(target: target, candidate: matchingCandidate)
        let wrongPipeScore = DDCProtocol.matchScore(target: target, candidate: wrongPipeCandidate)
        let mismatchScore = DDCProtocol.matchScore(target: target, candidate: differentMonitorCandidate)

        XCTAssertNotNil(matchingScore)
        XCTAssertNotNil(wrongPipeScore)
        XCTAssertGreaterThan(matchingScore!, wrongPipeScore!)
        XCTAssertNil(mismatchScore)
    }

    func testBuildsSoftwareGammaTableWithSafeMinimumFloorAtZero() {
        let zeroTable = DDCProtocol.makeSoftwareGammaTable(level: 0.0)
        XCTAssertEqual(zeroTable.count, 256)
        XCTAssertEqual(zeroTable.first ?? -1, 0.0, accuracy: 0.0001)
        XCTAssertEqual(zeroTable.last ?? -1, 0.08, accuracy: 0.0001)

        let halfTable = DDCProtocol.makeSoftwareGammaTable(level: 0.5)
        XCTAssertEqual(halfTable.count, 256)
        XCTAssertEqual(halfTable.first ?? -1, 0.0, accuracy: 0.0001)
        XCTAssertEqual(halfTable.last ?? -1, 0.50, accuracy: 0.0001)

        let fullTable = DDCProtocol.makeSoftwareGammaTable(level: 1.0)
        XCTAssertEqual(fullTable.count, 256)
        XCTAssertEqual(fullTable.first ?? -1, 0.0, accuracy: 0.0001)
        XCTAssertEqual(fullTable.last ?? -1, 1.00, accuracy: 0.0001)
    }
}
