import Foundation
import CLabelBackend

struct BackendResponse: Decodable, Sendable {
    let ok: Bool
    let message: String
    let tapeMM: Int?
    let printableDots: Int?
}
// Serial actor prevents status requests from interrupting an active print.
actor PrinterService {
    private func decode(_ pointer: UnsafeMutablePointer<CChar>?) throws -> BackendResponse {
        guard let pointer else { throw RenderError.failed("No response from printer backend") }
        defer { label_backend_free(pointer) }
        return try JSONDecoder().decode(BackendResponse.self, from: Data(String(cString: pointer).utf8))
    }
    func status() throws -> BackendResponse { try decode(label_backend_status()) }
    func printLabel(pixels: [UInt8], width: Int, height: Int, tape: Int, copies: Int, cut: Bool) throws -> BackendResponse {
        try pixels.withUnsafeBufferPointer { buffer in
            try decode(label_backend_print(buffer.baseAddress, buffer.count, UInt32(width), UInt32(height),
                                           UInt8(tape), UInt16(copies), cut ? 1 : 0))
        }
    }
}
