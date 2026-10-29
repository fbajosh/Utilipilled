// Atomically publish an already verified bundle on the same filesystem.
// During replacement the old bundle moves to the staging path, whose owner cleans it up.
import Foundation
import Darwin

func fail(_ message: String) -> Never {
    fputs("Bundle publication failed: \(message)\n", stderr)
    exit(1)
}

guard CommandLine.arguments.count == 3 else { fail("expected staging and destination paths") }
let source = CommandLine.arguments[1]
let destination = CommandLine.arguments[2]
var metadata = stat()
if lstat(destination, &metadata) == 0 {
    guard (metadata.st_mode & S_IFMT) == S_IFDIR else {
        fail("destination must be a directory, not a symlink or file")
    }
    guard renamex_np(source, destination, UInt32(RENAME_SWAP)) == 0 else {
        fail(String(cString: strerror(errno)))
    }
} else {
    guard errno == ENOENT else { fail(String(cString: strerror(errno))) }
    guard rename(source, destination) == 0 else { fail(String(cString: strerror(errno))) }
}
