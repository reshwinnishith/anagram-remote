import CoreMIDI
import XCTest
@testable import AnagramRemote

/// Exercises CoreMIDITransport's initialisation paths with injected fakes; no real CoreMIDI calls are made.
@MainActor
final class CoreMIDITransportInitializationTests: XCTestCase {
    private final class Recorder {
        var portRequests = 0
        var disposedClients: [MIDIClientRef] = []
    }

    private func initializer(clientStatus: OSStatus = noErr, client: MIDIClientRef = 77,
                             portStatus: OSStatus = noErr, port: MIDIPortRef = 88,
                             recorder: Recorder) -> CoreMIDIInitializer {
        CoreMIDIInitializer(
            createClient: { _ in (clientStatus, client) },
            createOutputPort: { _ in recorder.portRequests += 1; return (portStatus, port) },
            disposeClient: { recorder.disposedClients.append($0) })
    }

    func testClientCreationFailure() {
        let r = Recorder()
        let t = CoreMIDITransport(initializer: initializer(clientStatus: -50, recorder: r))
        XCTAssertEqual(t.initializationError, .clientCreationFailed(-50))
        XCTAssertEqual(r.portRequests, 0, "must not create a port without a client")
        XCTAssertTrue(r.disposedClients.isEmpty)
    }

    func testClientStatusOKButInvalidHandleIsFailure() {
        let r = Recorder()
        let t = CoreMIDITransport(initializer: initializer(client: 0, recorder: r))
        XCTAssertEqual(t.initializationError, .clientCreationFailed(-1))
        XCTAssertEqual(r.portRequests, 0)
    }

    func testPortCreationFailureDisposesClient() {
        let r = Recorder()
        let t = CoreMIDITransport(initializer: initializer(portStatus: -50, recorder: r))
        XCTAssertEqual(t.initializationError, .outputPortCreationFailed(-50))
        XCTAssertEqual(r.disposedClients, [77])
    }

    func testSuccessfulInitialization() {
        let r = Recorder()
        let t = CoreMIDITransport(initializer: initializer(recorder: r))
        XCTAssertNil(t.initializationError)
        XCTAssertEqual(r.portRequests, 1)
        XCTAssertTrue(r.disposedClients.isEmpty)
    }

    func testSendAfterFailedInitializationFailsSafely() {
        let t = CoreMIDITransport(initializer: initializer(clientStatus: -50, recorder: Recorder()))
        XCTAssertThrowsError(try t.send([0xC0, 0x00], to: 1)) {
            XCTAssertEqual($0 as? MIDITransportError, .clientCreationFailed(-50))
        }
        XCTAssertTrue(t.destinations.isEmpty)
    }

    func testErrorMessagesIncludeOSStatus() {
        XCTAssertTrue(MIDITransportError.clientCreationFailed(-50).localizedDescription.contains("-50"))
        XCTAssertTrue(MIDITransportError.outputPortCreationFailed(-50).localizedDescription.contains("-50"))
    }
}
