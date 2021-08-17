import XCTest

#if !canImport(ObjectiveC)
public func allTests() -> [XCTestCaseEntry] {
    return [
        testCase(fishy_actor_transportTests.allTests),
    ]
}
#endif
