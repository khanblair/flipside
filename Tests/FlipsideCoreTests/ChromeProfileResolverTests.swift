import XCTest
@testable import FlipsideCore

final class ChromeProfileResolverTests: XCTestCase {
    // MARK: - extractProfileDirectory

    func testExtractProfileDirectoryFindsValueAmongUnrelatedFlags() {
        let arguments = [
            "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
            "--type=renderer",
            "--enable-features=SomeFeature",
            "--profile-directory=Profile 2",
            "--lang=en-US",
            "--no-sandbox"
        ]

        XCTAssertEqual(ChromeProfileResolver.extractProfileDirectory(from: arguments), "Profile 2")
    }

    func testExtractProfileDirectoryReturnsNilWhenAbsent() {
        let arguments = [
            "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
            "--type=renderer",
            "--enable-features=SomeFeature",
            "--lang=en-US",
            "--no-sandbox"
        ]

        XCTAssertNil(ChromeProfileResolver.extractProfileDirectory(from: arguments))
    }

    // MARK: - parseProcArgs2

    func testParseProcArgs2RecoversArgvFromHandConstructedBuffer() {
        // Layout per KERN_PROCARGS2:
        // [4-byte LE argc][exec path\0][NUL padding...][argv[0]\0][argv[1]\0]...[argv[argc-1]\0]
        let execPath = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
        let expectedArgv = [
            "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome", // argv[0], duplicates exec path
            "--type=renderer",
            "--profile-directory=Profile 2",
            "--some-other-flag"
        ]

        var buffer: [UInt8] = []

        // argc as little-endian Int32
        let argc = Int32(expectedArgv.count)
        withUnsafeBytes(of: argc.littleEndian) { buffer.append(contentsOf: $0) }

        // Exec path + NUL terminator
        buffer.append(contentsOf: Array(execPath.utf8))
        buffer.append(0)

        // Variable-length NUL padding (simulating pointer-alignment padding)
        buffer.append(contentsOf: [0, 0, 0])

        // argv strings, each NUL-terminated
        for arg in expectedArgv {
            buffer.append(contentsOf: Array(arg.utf8))
            buffer.append(0)
        }

        // envp strings that should be ignored once argc strings are collected
        buffer.append(contentsOf: Array("SOME_ENV=value".utf8))
        buffer.append(0)

        let parsed = ProcessArgumentsReader.parseProcArgs2(buffer)

        XCTAssertEqual(parsed, expectedArgv)

        // Compose with extractProfileDirectory to prove the two halves work together.
        XCTAssertEqual(ChromeProfileResolver.extractProfileDirectory(from: parsed), "Profile 2")
    }
}
