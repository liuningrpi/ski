import Foundation
import CoreLocation

struct SkiResortRecord: Decodable {
    let name: String
    let lat: Double
    let lon: Double
    let country: String
    let region: String
}

private struct SkiResortFile: Decodable {
    let version: Int
    let count: Int
    let resorts: [SkiResortRecord]
}

struct SkiResortMatch {
    let resort: SkiResortRecord
    let distanceMeters: Double
}

final class SkiResortLocator {
    static let shared = SkiResortLocator()

    private let resorts: [SkiResortRecord]
    private let cellSizeDegrees = 0.35
    private let grid: [String: [Int]]

    private init() {
        guard
            let url = Bundle.main.url(forResource: "ski_resorts_min", withExtension: "json"),
            let data = try? Data(contentsOf: url),
            let decoded = try? JSONDecoder().decode(SkiResortFile.self, from: data)
        else {
            self.resorts = []
            self.grid = [:]
            return
        }

        self.resorts = decoded.resorts
        self.grid = SkiResortLocator.buildGrid(resorts: decoded.resorts, cellSizeDegrees: cellSizeDegrees)
    }

    func nearest(to coordinate: CLLocationCoordinate2D, maxDistanceMeters: Double) -> SkiResortMatch? {
        guard !resorts.isEmpty else { return nil }

        let cellRadius = max(
            1,
            Int(ceil((maxDistanceMeters / 111_000.0) / cellSizeDegrees))
        )
        let latIndex = gridIndex(for: coordinate.latitude)
        let lonIndex = gridIndex(for: coordinate.longitude)

        var best: SkiResortMatch?
        for dLat in -cellRadius...cellRadius {
            for dLon in -cellRadius...cellRadius {
                let key = "\(latIndex + dLat):\(lonIndex + dLon)"
                guard let indexes = grid[key] else { continue }
                for idx in indexes {
                    let resort = resorts[idx]
                    let dist = haversineMeters(
                        lat1: coordinate.latitude,
                        lon1: coordinate.longitude,
                        lat2: resort.lat,
                        lon2: resort.lon
                    )
                    if dist > maxDistanceMeters { continue }
                    if best == nil || dist < best!.distanceMeters {
                        best = SkiResortMatch(resort: resort, distanceMeters: dist)
                    }
                }
            }
        }
        return best
    }

    private func gridIndex(for value: Double) -> Int {
        Int(floor(value / cellSizeDegrees))
    }

    private static func buildGrid(resorts: [SkiResortRecord], cellSizeDegrees: Double) -> [String: [Int]] {
        var result: [String: [Int]] = [:]
        for (idx, resort) in resorts.enumerated() {
            let latIndex = Int(floor(resort.lat / cellSizeDegrees))
            let lonIndex = Int(floor(resort.lon / cellSizeDegrees))
            let key = "\(latIndex):\(lonIndex)"
            result[key, default: []].append(idx)
        }
        return result
    }

    private func haversineMeters(lat1: Double, lon1: Double, lat2: Double, lon2: Double) -> Double {
        let radius = 6_371_000.0
        let dLat = (lat2 - lat1) * .pi / 180
        let dLon = (lon2 - lon1) * .pi / 180
        let a = sin(dLat / 2) * sin(dLat / 2) +
            cos(lat1 * .pi / 180) * cos(lat2 * .pi / 180) * sin(dLon / 2) * sin(dLon / 2)
        let c = 2 * atan2(sqrt(a), sqrt(1 - a))
        return radius * c
    }
}
