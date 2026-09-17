import Foundation

enum PolylineDecoder {
    /**
     * Decodes a Google polyline into ordered geographic coordinates.
     *
     * @param encoded The polyline string, using signed deltas at 1e-5 coordinate precision.
     * @return The decoded coordinates in route order, or an empty array for an empty string.
     * @throws NavigationError.invalidResponse if the encoding is malformed
     *         or contains invalid coordinates.
     */
    static func decode(_ encoded: String) throws -> [Coordinate] {
        let bytes = Array(encoded.utf8)
        var index = 0
        var latitude: Int64 = 0
        var longitude: Int64 = 0
        var points: [Coordinate] = []

        /**
         * Reads one signed coordinate delta, advancing the captured byte index.
         *
         * @return The decoded integer delta in units of 1e-5 degrees.
         * @throws NavigationError.invalidResponse if the component is truncated,
         *         oversized, or contains an invalid byte.
         */
        func component() throws -> Int64 {
            var result: Int64 = 0
            var shift = 0
            while index < bytes.count, shift <= 30 {
                let byte = bytes[index]
                index += 1
                guard (63...126).contains(byte) else { throw NavigationError.invalidResponse }
                let value = Int64(byte - 63)
                result |= (value & 0x1f) << shift
                if value < 0x20 { return result & 1 == 0 ? result >> 1 : ~(result >> 1) }
                shift += 5
            }
            throw NavigationError.invalidResponse
        }

        while index < bytes.count {
            latitude += try component()
            longitude += try component()
            let point = Coordinate(latitude: Double(latitude) / 100_000,
                                   longitude: Double(longitude) / 100_000)
            guard point.isValid else { throw NavigationError.invalidResponse }
            points.append(point)
        }
        return points
    }
}
