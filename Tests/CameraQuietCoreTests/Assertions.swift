import Foundation
func XCTAssertEqual<T: Equatable>(_ actual: @autoclosure () throws -> T, _ expected: T, file: StaticString = #file, line: UInt = #line) {
    do { let value = try actual(); if value != expected { fatalError("Expected \(expected), got \(value)", file: file, line: line) } }
    catch { fatalError("Unexpected error: \(error)", file: file, line: line) }
}
func XCTAssertTrue(_ actual: @autoclosure () throws -> Bool, file: StaticString = #file, line: UInt = #line) {
    do { if try !actual() { fatalError("Expected true", file: file, line: line) } }
    catch { fatalError("Unexpected error: \(error)", file: file, line: line) }
}
func XCTAssertFalse(_ actual: @autoclosure () throws -> Bool, file: StaticString = #file, line: UInt = #line) {
    do { if try actual() { fatalError("Expected false", file: file, line: line) } }
    catch { fatalError("Unexpected error: \(error)", file: file, line: line) }
}
func XCTAssertNil<T>(_ actual: @autoclosure () throws -> T?, file: StaticString = #file, line: UInt = #line) {
    do { if try actual() != nil { fatalError("Expected nil", file: file, line: line) } }
    catch { fatalError("Unexpected error: \(error)", file: file, line: line) }
}
func XCTAssertNotNil<T>(_ actual: @autoclosure () throws -> T?, file: StaticString = #file, line: UInt = #line) {
    do { if try actual() == nil { fatalError("Expected non-nil", file: file, line: line) } }
    catch { fatalError("Unexpected error: \(error)", file: file, line: line) }
}
func XCTAssertThrowsError<T>(_ action: @autoclosure () throws -> T, file: StaticString = #file, line: UInt = #line) {
    do { _ = try action(); fatalError("Expected an error", file: file, line: line) } catch { }
}
