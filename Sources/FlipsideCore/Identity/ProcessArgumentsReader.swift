import Darwin

/// Thin adapter over `sysctl(KERN_PROCARGS2)` for reading another process's
/// command-line arguments. Not unit-testable: there is no live process to
/// query in an automated test environment. The pure byte-parsing logic is
/// factored out into `parseProcArgs2` so *that* can be exercised directly.
enum ProcessArgumentsReader {
    /// Reads the command-line arguments of the process identified by `pid`.
    ///
    /// Works for any process owned by the current user without elevated
    /// privileges, per KERN_PROCARGS2 semantics on macOS. Returns `nil` if
    /// the process cannot be queried (e.g. it has exited, or it's owned by
    /// another user).
    static func arguments(forPID pid: pid_t) -> [String]? {
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]

        var size = 0
        let sizeResult = sysctl(&mib, UInt32(mib.count), nil, &size, nil, 0)
        guard sizeResult == 0, size > 0 else {
            return nil
        }

        var buffer = [UInt8](repeating: 0, count: size)
        let fetchResult = buffer.withUnsafeMutableBytes { rawBuffer -> Int32 in
            var fetchedSize = size
            let result = sysctl(&mib, UInt32(mib.count), rawBuffer.baseAddress, &fetchedSize, nil, 0)
            size = fetchedSize
            return result
        }
        guard fetchResult == 0 else {
            return nil
        }

        // Use the size actually reported by the second call, not the first
        // (the process's argument list can change between the two calls).
        let trimmed = Array(buffer.prefix(size))
        return parseProcArgs2(trimmed)
    }

    /// Parses the raw KERN_PROCARGS2 buffer layout into an argv array.
    ///
    /// Layout (documented/commonly-observed, see caller-side caveats):
    /// - 4 bytes: `argc` as a little-endian `Int32`.
    /// - The executable path, NUL-terminated.
    /// - A run of NUL padding bytes (variable length, for pointer alignment).
    /// - `argc` NUL-terminated argv strings in sequence, the first of which
    ///   (`argv[0]`) is typically the executable path again.
    /// - Environment (`envp`) strings may follow; these are ignored — parsing
    ///   stops as soon as `argc` argv strings have been collected.
    ///
    /// Pure and side-effect free, so it can be unit tested against
    /// hand-built buffers without a live process.
    static func parseProcArgs2(_ buffer: [UInt8]) -> [String] {
        guard buffer.count >= 4 else {
            return []
        }

        let argc = buffer.withUnsafeBytes { rawBuffer -> Int32 in
            rawBuffer.load(fromByteOffset: 0, as: Int32.self).littleEndian
        }
        guard argc > 0 else {
            return []
        }

        var offset = 4

        // Skip the executable path up to and including its NUL terminator.
        while offset < buffer.count, buffer[offset] != 0 {
            offset += 1
        }
        while offset < buffer.count, buffer[offset] == 0 {
            offset += 1
        }

        var argv: [String] = []
        argv.reserveCapacity(Int(argc))

        while argv.count < argc, offset < buffer.count {
            let start = offset
            while offset < buffer.count, buffer[offset] != 0 {
                offset += 1
            }
            let stringBytes = buffer[start..<offset]
            argv.append(String(decoding: stringBytes, as: UTF8.self))

            // Skip the terminating NUL (if present) before reading the next string.
            if offset < buffer.count {
                offset += 1
            }
        }

        return argv
    }
}
