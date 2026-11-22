//
//  ArrivalStore.swift
//  tayarTripPlanner
//

import Foundation
import Observation

enum FlightStatus: Equatable {
    case scheduled(countdown: String)
    case landingSoon(minutes: Int)
    case due
    case arrived
    case dayComplete

    var label: String {
        switch self {
        case .scheduled(let countdown): return countdown
        case .landingSoon(let minutes): return "landing soon — in \(minutes) min"
        case .due: return "due — check live"
        case .arrived: return "arrived (sched.)"
        case .dayComplete: return "day complete"
        }
    }
}

enum StatusKind {
    case neutral, soon, due, ok, live
}

/// Live aircraft data matched from the open ADS-B network (adsb.lol).
struct LiveFlightInfo: Equatable {
    let callsign: String
    let distanceKm: Double
    let altitudeFt: Int?        // nil means on the ground
    let groundSpeedKt: Double?
    let fetchedAt: Date

    var onGround: Bool { altitudeFt == nil }

    var etaMinutes: Int? {
        guard let speed = groundSpeedKt, speed > 60 else { return nil }
        return Int((distanceKm / (speed * 1.852) * 60).rounded())
    }
}

@MainActor
@Observable
final class ArrivalStore {
    private(set) var metResNumbers: Set<String>
    var now: Date = .now
    var searchText: String = ""

    /// Current arrival list: the built-in Viking list, or the last imported one.
    private(set) var dataset: ArrivalDataSet
    private(set) var isImported = false

    // Live data
    private(set) var live: [String: LiveFlightInfo] = [:]   // Flight.id → info
    private(set) var lastLiveRefresh: Date?
    private(set) var isRefreshing = false
    private(set) var liveError: String?

    private static let storageKey = "viking-fra-2026-11-23-met"
    static let berlin = TimeZone(identifier: "Europe/Berlin")!

    /// FRA reference point for distance calculations.
    private static let fraLat = 50.0379, fraLon = 8.5622
    /// All aircraft within 250 nm (~460 km) of FRA in a single request, no API key.
    private static let adsbURL = URL(string: "https://api.adsb.lol/v2/point/50.0379/8.5622/250")!

    private static let icaoPrefix: [String: String] = [
        "LH": "DLH", "AA": "AAL", "UA": "UAL", "DL": "DAL", "AF": "AFR",
        "LX": "SWR", "BA": "BAW", "KL": "KLM", "AC": "ACA", "4Y": "OCN",
    ]

    private static var importedFileURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("imported-arrivals.json")
    }

    init() {
        let saved = UserDefaults.standard.stringArray(forKey: Self.storageKey) ?? []
        metResNumbers = Set(saved)
        if let data = try? Data(contentsOf: Self.importedFileURL),
           let imported = try? JSONDecoder().decode(ArrivalDataSet.self, from: data) {
            dataset = imported
            isImported = true
        } else {
            dataset = ArrivalData.builtIn
        }
    }

    // MARK: - Import

    func applyImported(_ newDataset: ArrivalDataSet) {
        dataset = newDataset
        isImported = true
        live = [:]
        lastLiveRefresh = nil
        if let data = try? JSONEncoder().encode(newDataset) {
            try? data.write(to: Self.importedFileURL, options: .atomic)
        }
    }

    func resetToBuiltIn() {
        dataset = ArrivalData.builtIn
        isImported = false
        live = [:]
        lastLiveRefresh = nil
        try? FileManager.default.removeItem(at: Self.importedFileURL)
    }

    // MARK: - Met check-offs

    func isMet(_ passenger: Passenger) -> Bool {
        metResNumbers.contains(passenger.resNumber)
    }

    func toggleMet(_ passenger: Passenger) {
        if metResNumbers.contains(passenger.resNumber) {
            metResNumbers.remove(passenger.resNumber)
        } else {
            metResNumbers.insert(passenger.resNumber)
        }
        UserDefaults.standard.set(Array(metResNumbers), forKey: Self.storageKey)
    }

    func metCount(for flight: Flight) -> Int {
        flight.passengers.filter { isMet($0) }.count
    }

    var totalMet: Int {
        let allRes = Set(dataset.flights.flatMap { $0.passengers.map(\.resNumber) })
        return metResNumbers.intersection(allRes).count
    }

    // MARK: - Live ADS-B refresh

    func refreshLive() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            var request = URLRequest(url: Self.adsbURL)
            request.timeoutInterval = 20
            let (data, _) = try await URLSession.shared.data(for: request)
            let aircraft = Self.parseAircraft(data)
            var matched: [String: LiveFlightInfo] = [:]
            for flight in dataset.flights {
                if let info = Self.match(flight: flight, in: aircraft) {
                    matched[flight.id] = info
                }
            }
            live = matched
            lastLiveRefresh = .now
            liveError = nil
        } catch {
            liveError = "Live data unavailable — check connection"
        }
    }

    private struct Aircraft {
        let airlinePrefix: String   // letters at the start of the callsign
        let flightDigits: Int?      // numeric part of the callsign, if purely numeric
        let lat: Double
        let lon: Double
        let altitudeFt: Int?        // nil = on ground
        let groundSpeedKt: Double?
        let callsign: String
    }

    private static func parseAircraft(_ data: Data) -> [Aircraft] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let list = root["ac"] as? [[String: Any]] else { return [] }
        return list.compactMap { entry in
            guard let rawCallsign = entry["flight"] as? String,
                  let lat = entry["lat"] as? Double,
                  let lon = entry["lon"] as? Double else { return nil }
            let callsign = rawCallsign.trimmingCharacters(in: .whitespaces).uppercased()
            guard !callsign.isEmpty else { return nil }

            let letters = String(callsign.prefix(while: { $0.isLetter }))
            let rest = String(callsign.dropFirst(letters.count))
            let digits = rest.allSatisfy(\.isNumber) ? Int(rest) : nil

            var altitude: Int?
            if let alt = entry["alt_baro"] as? Int { altitude = alt }
            else if let alt = entry["alt_baro"] as? Double { altitude = Int(alt) }
            // "ground" string → nil altitude = on ground

            let speed = entry["gs"] as? Double
            return Aircraft(airlinePrefix: letters, flightDigits: digits,
                            lat: lat, lon: lon, altitudeFt: altitude,
                            groundSpeedKt: speed, callsign: callsign)
        }
    }

    private static func match(flight: Flight, in aircraft: [Aircraft]) -> LiveFlightInfo? {
        let parts = flight.number.split(separator: " ")
        guard parts.count == 2, let number = Int(parts[1]) else { return nil }
        let iata = String(parts[0]).uppercased()
        let icao = icaoPrefix[iata]

        guard let hit = aircraft.first(where: { ac in
            guard ac.flightDigits == number else { return false }
            return ac.airlinePrefix == icao || ac.airlinePrefix == iata
        }) else { return nil }

        let distance = haversineKm(lat1: hit.lat, lon1: hit.lon, lat2: fraLat, lon2: fraLon)
        return LiveFlightInfo(callsign: hit.callsign, distanceKm: distance,
                              altitudeFt: hit.altitudeFt, groundSpeedKt: hit.groundSpeedKt,
                              fetchedAt: .now)
    }

    private static func haversineKm(lat1: Double, lon1: Double, lat2: Double, lon2: Double) -> Double {
        let r = 6371.0
        let dLat = (lat2 - lat1) * .pi / 180
        let dLon = (lon2 - lon1) * .pi / 180
        let a = sin(dLat / 2) * sin(dLat / 2)
            + cos(lat1 * .pi / 180) * cos(lat2 * .pi / 180) * sin(dLon / 2) * sin(dLon / 2)
        return r * 2 * atan2(sqrt(a), sqrt(1 - a))
    }

    /// Live info for a flight, if fetched recently enough to still be meaningful.
    func liveInfo(for flight: Flight) -> LiveFlightInfo? {
        guard let info = live[flight.id] else { return nil }
        guard now.timeIntervalSince(info.fetchedAt) < 15 * 60 else { return nil }
        return info
    }

    // MARK: - Display status: live signal first, schedule as fallback

    func displayStatus(for flight: Flight) -> (label: String, kind: StatusKind) {
        if let info = liveInfo(for: flight) {
            if info.onGround, info.distanceKm < 8 {
                return ("landed · at FRA", .ok)
            }
            if !info.onGround {
                var label = "✈ \(Int(info.distanceKm.rounded())) km out"
                if let eta = info.etaMinutes, eta < 180 { label += " · ~\(eta) min" }
                return (label, .live)
            }
        }
        let scheduled = status(for: flight)
        let kind: StatusKind
        switch scheduled {
        case .scheduled: kind = .neutral
        case .landingSoon: kind = .soon
        case .due: kind = .due
        case .arrived, .dayComplete: kind = .ok
        }
        return (scheduled.label, kind)
    }

    // MARK: - Schedule status against Europe/Berlin clock

    func status(for flight: Flight) -> FlightStatus {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = Self.berlin
        let nowParts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: now)
        let day = dataset.dayComponents

        let nowDate = (nowParts.year!, nowParts.month!, nowParts.day!)
        let flightDate = (day.year!, day.month!, day.day!)

        if nowDate < flightDate { return .scheduled(countdown: "scheduled") }
        if nowDate > flightDate { return .dayComplete }

        let nowMinutes = nowParts.hour! * 60 + nowParts.minute!
        let delta = flight.scheduledMinutes - nowMinutes
        if delta > 45 {
            let text = delta >= 60 ? "in \(delta / 60) h \(delta % 60) min" : "in \(delta) min"
            return .scheduled(countdown: text)
        }
        if delta > 0 { return .landingSoon(minutes: delta) }
        if delta > -120 { return .due }
        return .arrived
    }

    // MARK: - Search

    var filteredFlights: [Flight] {
        let query = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        guard !query.isEmpty else { return dataset.flights }
        return dataset.flights.filter { flight in
            flight.matches(query) || flight.passengers.contains { passengerMatches($0, query) }
        }
    }

    var filteredUnknownParties: [UnknownParty] {
        let query = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        guard !query.isEmpty else { return dataset.unknownParties }
        return dataset.unknownParties.filter { party in
            party.passengers.contains { passengerMatches($0, query) }
        }
    }

    /// Passengers of a flight to show for the current search: all of them when the
    /// flight itself matches, otherwise just the matching ones.
    func visiblePassengers(of flight: Flight) -> [Passenger] {
        let query = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        guard !query.isEmpty, !flight.matches(query) else { return flight.passengers }
        return flight.passengers.filter { passengerMatches($0, query) }
    }

    private func passengerMatches(_ passenger: Passenger, _ query: String) -> Bool {
        "\(passenger.lastName) \(passenger.title) \(passenger.resNumber)".lowercased().contains(query)
    }
}
