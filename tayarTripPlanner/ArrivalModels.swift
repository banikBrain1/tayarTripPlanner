//
//  ArrivalModels.swift
//  tayarTripPlanner
//
//  Arrival list for 23.11.2026 at Frankfurt Airport (FRA),
//  imported from 23.11.26_Viking.xlsx (ARRIVAL LIST sheet).
//

import Foundation

nonisolated struct Passenger: Identifiable, Hashable, Codable {
    let lastName: String
    let title: String
    let resNumber: String

    var id: String { resNumber }
    var displayName: String { "\(lastName) \(title)" }
}

nonisolated struct Flight: Identifiable, Hashable, Codable {
    let scheduledTime: String   // "HH:mm", Europe/Berlin
    let number: String          // "LH 1333"
    let airline: String
    let origin: String
    let terminal: String        // "T1" or "T3"
    let passengers: [Passenger]

    var id: String { "\(number)-\(scheduledTime)" }

    var scheduledMinutes: Int {
        let parts = scheduledTime.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2 else { return 0 }
        return parts[0] * 60 + parts[1]
    }

    /// Official Frankfurt Airport live page for this flight: landed time, baggage belt, exit.
    var fraLiveURL: URL {
        let slug = number.replacingOccurrences(of: " ", with: "+")
        return URL(string: "https://www.frankfurt-airport.com/en/flights-and-transfer/arrivals.html/\(slug)")!
    }

    var flightradarURL: URL {
        let slug = number.replacingOccurrences(of: " ", with: "").lowercased()
        return URL(string: "https://www.flightradar24.com/data/flights/\(slug)")!
    }

    func matches(_ query: String) -> Bool {
        let haystack = "\(number) \(airline) \(origin)".lowercased()
        return haystack.contains(query)
    }
}

nonisolated struct UnknownParty: Identifiable, Hashable, Codable {
    let issue: String
    let passengers: [Passenger]

    var id: String { passengers.first?.resNumber ?? issue }
}

/// A complete arrival list: the built-in Viking list or one imported from a file.
nonisolated struct ArrivalDataSet: Codable, Equatable {
    var dayLabel: String
    var year: Int
    var month: Int
    var day: Int
    var flights: [Flight]
    var unknownParties: [UnknownParty]

    var dayComponents: DateComponents { DateComponents(year: year, month: month, day: day) }
    var totalFlightPax: Int { flights.reduce(0) { $0 + $1.passengers.count } }
    var totalUnknownPax: Int { unknownParties.reduce(0) { $0 + $1.passengers.count } }
}

nonisolated enum ArrivalData {
    static let builtIn = ArrivalDataSet(
        dayLabel: "Monday, 23 November 2026",
        year: 2026, month: 11, day: 23,
        flights: builtInFlights,
        unknownParties: builtInUnknownParties
    )

    private static let builtInFlights: [Flight] = [
        Flight(scheduledTime: "05:20", number: "LH 423", airline: "Lufthansa", origin: "Boston (BOS)", terminal: "T1", passengers: [
            Passenger(lastName: "LASH", title: "MS. NANCY", resNumber: "98094111"),
            Passenger(lastName: "CARON", title: "MS. MARGARET", resNumber: "98094112"),
        ]),
        Flight(scheduledTime: "06:15", number: "LH 443", airline: "Lufthansa", origin: "Detroit (DTW)", terminal: "T1", passengers: [
            Passenger(lastName: "WARECK", title: "MR. DAVID", resNumber: "96658731"),
            Passenger(lastName: "CHANDOCHIN", title: "MRS. LENA", resNumber: "96658732"),
            Passenger(lastName: "WILSON", title: "MR. DONALD", resNumber: "99567181"),
            Passenger(lastName: "WILSON", title: "MS. CATHERINE", resNumber: "99567182"),
        ]),
        Flight(scheduledTime: "07:15", number: "AA 70", airline: "American Airlines", origin: "Dallas/Fort Worth (DFW)", terminal: "T3", passengers: [
            Passenger(lastName: "FRIELDS REIFSTECK", title: "MR. TYLER", resNumber: "97526062"),
        ]),
        Flight(scheduledTime: "07:25", number: "UA 989", airline: "United", origin: "Washington (IAD)", terminal: "T1", passengers: [
            Passenger(lastName: "FONTANILLA", title: "MRS. ROSARIO", resNumber: "98597161"),
        ]),
        Flight(scheduledTime: "07:30", number: "LH 449", airline: "Lufthansa", origin: "St. Louis (STL)", terminal: "T1", passengers: [
            Passenger(lastName: "PHILLIPS", title: "MR. MARK", resNumber: "96198481"),
            Passenger(lastName: "PHILLIPS", title: "MRS. TAMMY", resNumber: "96198482"),
            Passenger(lastName: "FRIELDS", title: "MS. ANGELA", resNumber: "97526061"),
        ]),
        Flight(scheduledTime: "07:30", number: "LH 431", airline: "Lufthansa", origin: "Chicago (ORD)", terminal: "T1", passengers: [
            Passenger(lastName: "WALL", title: "MR. PHILLIP", resNumber: "98444981"),
            Passenger(lastName: "LIDDICOAT", title: "MS. SUSAN", resNumber: "98444982"),
        ]),
        Flight(scheduledTime: "07:45", number: "LH 463", airline: "Lufthansa", origin: "Miami (MIA)", terminal: "T1", passengers: [
            Passenger(lastName: "ATKINS", title: "MRS. SHERRY", resNumber: "99027881"),
            Passenger(lastName: "WALLACE", title: "MR. PAUL", resNumber: "99027882"),
        ]),
        Flight(scheduledTime: "07:50", number: "DL 14", airline: "Delta", origin: "Atlanta (ATL)", terminal: "T3", passengers: [
            Passenger(lastName: "TAM", title: "MRS. CHRISTINA WAI FUN", resNumber: "96895301"),
            Passenger(lastName: "KONG", title: "MRS. SHIRLEY", resNumber: "96895302"),
        ]),
        Flight(scheduledTime: "08:40", number: "DL 106", airline: "Delta", origin: "New York (JFK)", terminal: "T3", passengers: [
            Passenger(lastName: "LAZORE", title: "MR. MARK", resNumber: "96623621"),
            Passenger(lastName: "PERHAMLAZORE", title: "MRS. TERACIA", resNumber: "96623622"),
            Passenger(lastName: "YUNG WONG", title: "MRS. MO WAH", resNumber: "96895341"),
            Passenger(lastName: "SO LAU", title: "MRS. SAU YUK", resNumber: "96895342"),
        ]),
        Flight(scheduledTime: "08:45", number: "LH 441", airline: "Lufthansa", origin: "Houston (IAH)", terminal: "T1", passengers: [
            Passenger(lastName: "MANALO", title: "MR. ALEXANDER", resNumber: "98405861"),
            Passenger(lastName: "MANALO", title: "MRS. MA LEAH CARIDAD", resNumber: "98405862"),
            Passenger(lastName: "NARCISO", title: "MRS. LOURDES", resNumber: "98405671"),
            Passenger(lastName: "NARCISO", title: "MR. TOMAS", resNumber: "98405672"),
        ]),
        Flight(scheduledTime: "08:50", number: "AA 704", airline: "American Airlines", origin: "Charlotte (CLT)", terminal: "T3", passengers: [
            Passenger(lastName: "ELLIS", title: "DR. CARYL", resNumber: "96611821"),
            Passenger(lastName: "ELLIS", title: "MISS. NISA", resNumber: "96611822"),
            Passenger(lastName: "COZLIN", title: "MRS. ANDREA", resNumber: "97768091"),
            Passenger(lastName: "COZLIN", title: "MR. WAYNE", resNumber: "97768092"),
            Passenger(lastName: "WISTOCKI", title: "MR. DAVID", resNumber: "96858121"),
            Passenger(lastName: "WISTOCKI", title: "MRS. CYNTHIA", resNumber: "96858122"),
            Passenger(lastName: "WANG", title: "MR. YANG", resNumber: "97555751"),
            Passenger(lastName: "SUN", title: "MS. KEN JIAN", resNumber: "97555752"),
        ]),
        Flight(scheduledTime: "09:30", number: "4Y 65", airline: "Discover Airlines", origin: "Tampa (TPA)", terminal: "T1", passengers: [
            Passenger(lastName: "PARISH", title: "MR. DARRYL", resNumber: "96842991"),
            Passenger(lastName: "HOEHN PARISH", title: "MRS. JOYCE", resNumber: "96842992"),
        ]),
        Flight(scheduledTime: "09:30", number: "AF 1518", airline: "Air France", origin: "Paris (CDG)", terminal: "T3", passengers: [
            Passenger(lastName: "KUBIK", title: "MS. ELIZABETH", resNumber: "97554151"),
            Passenger(lastName: "KUBIK", title: "MR. KENNETH", resNumber: "97554152"),
        ]),
        Flight(scheduledTime: "09:35", number: "UA 907", airline: "United", origin: "Chicago (ORD)", terminal: "T1", passengers: [
            Passenger(lastName: "GELETA", title: "MRS. THERESA", resNumber: "98838621"),
            Passenger(lastName: "GELETA", title: "MR. MATTHEW", resNumber: "98838622"),
            Passenger(lastName: "WICHTOWSKI", title: "MRS. TRACY", resNumber: "98887891"),
            Passenger(lastName: "WICHTOWSKI", title: "MR. THOMAS", resNumber: "98887892"),
        ]),
        Flight(scheduledTime: "10:00", number: "LX 3612", airline: "SWISS", origin: "Zürich (ZRH)", terminal: "T1", passengers: [
            Passenger(lastName: "NAYYAR", title: "MRS. MARIA", resNumber: "98597162"),
        ]),
        Flight(scheduledTime: "10:35", number: "BA 900", airline: "British Airways", origin: "London (LHR)", terminal: "T3", passengers: [
            Passenger(lastName: "UY", title: "MRS. NAOMI", resNumber: "97662481"),
            Passenger(lastName: "WILKINSON", title: "MR. MARK", resNumber: "97662482"),
            Passenger(lastName: "SIMONS", title: "MRS. MARY", resNumber: "98885321"),
            Passenger(lastName: "SIMONS", title: "MR. PAUL", resNumber: "98885322"),
        ]),
        Flight(scheduledTime: "11:10", number: "KL 1817", airline: "KLM", origin: "Amsterdam (AMS)", terminal: "T3", passengers: [
            Passenger(lastName: "CHAN", title: "MR. HANG LEUNG", resNumber: "98682161"),
            Passenger(lastName: "CHAN", title: "MS. CATHERINE MUI YING", resNumber: "98682162"),
            Passenger(lastName: "ZEE", title: "MS. CATHERINE", resNumber: "98681651"),
        ]),
        Flight(scheduledTime: "11:10", number: "AC 842", airline: "Air Canada", origin: "Toronto (YYZ)", terminal: "T1", passengers: [
            Passenger(lastName: "CHAN", title: "MS. JESSICA HANG MING", resNumber: "98681652"),
        ]),
        Flight(scheduledTime: "11:15", number: "AF 1618", airline: "Air France", origin: "Paris (CDG)", terminal: "T3", passengers: [
            Passenger(lastName: "CHAKMAK", title: "MRS. LINDA", resNumber: "99503111"),
            Passenger(lastName: "GARLICK", title: "MR. DAVID", resNumber: "99503112"),
            Passenger(lastName: "SCHULMAN", title: "MS. MARILYN", resNumber: "97550731"),
        ]),
        Flight(scheduledTime: "11:45", number: "LH 1333", airline: "Lufthansa", origin: "Budapest (BUD)", terminal: "T1", passengers: [
            Passenger(lastName: "DEAN", title: "MRS. JENNIFER", resNumber: "96673861"),
            Passenger(lastName: "DEAN", title: "MR. KENT", resNumber: "96673862"),
            Passenger(lastName: "NGUYEN", title: "MRS. SARA", resNumber: "96673921"),
            Passenger(lastName: "NGUYEN", title: "MR. HAI", resNumber: "96673922"),
            Passenger(lastName: "MATTISON", title: "MRS. LORRAINE", resNumber: "98085671"),
            Passenger(lastName: "MATTISON", title: "MR. STUART", resNumber: "98085672"),
            Passenger(lastName: "FARRIS", title: "MR. ANTHONY", resNumber: "98038551"),
            Passenger(lastName: "FARRIS", title: "MRS. THRESA", resNumber: "98038552"),
            Passenger(lastName: "BROWN", title: "MRS. JOANN", resNumber: "98059821"),
            Passenger(lastName: "BROWN", title: "MR. CLINTON", resNumber: "98059822"),
            Passenger(lastName: "DOWD", title: "MR. MICHAEL", resNumber: "97943691"),
            Passenger(lastName: "DOWD", title: "MRS. LUZ", resNumber: "97943692"),
            Passenger(lastName: "GUST", title: "MRS. KATHRYN", resNumber: "96702691"),
            Passenger(lastName: "GUST", title: "MR. GARY", resNumber: "96702692"),
            Passenger(lastName: "TOOLAN", title: "MRS. JOAN", resNumber: "96483641"),
            Passenger(lastName: "TOOLAN", title: "MR. TIMOTHY", resNumber: "96483642"),
            Passenger(lastName: "BALLARD", title: "MRS. MARY", resNumber: "97835041"),
            Passenger(lastName: "BALLARD", title: "MR. ARDEN", resNumber: "97835042"),
            Passenger(lastName: "CIPOLLETTI", title: "MR. JOHN", resNumber: "97834771"),
            Passenger(lastName: "CIPOLLETTI", title: "MRS. MARCY", resNumber: "97834772"),
            Passenger(lastName: "SILACCI", title: "MRS. ANASTASIA", resNumber: "96657291"),
            Passenger(lastName: "SILACCI", title: "MR. SAMUEL", resNumber: "96657292"),
        ]),
        Flight(scheduledTime: "13:25", number: "LH 1335", airline: "Lufthansa", origin: "Budapest (BUD)", terminal: "T1", passengers: [
            Passenger(lastName: "HILTON", title: "MR. CAMERON", resNumber: "97285131"),
            Passenger(lastName: "HILTON", title: "MRS. SHARON", resNumber: "97285132"),
            Passenger(lastName: "SANTOS", title: "MRS. ELVIRA", resNumber: "96661601"),
            Passenger(lastName: "SANTOS", title: "MR. GREG", resNumber: "96661602"),
            Passenger(lastName: "TUASON", title: "MR. DOMINGO", resNumber: "96661581"),
            Passenger(lastName: "TUASON", title: "MRS. ERLINDA", resNumber: "96661582"),
            Passenger(lastName: "COY", title: "MRS. MARIA", resNumber: "97255451"),
            Passenger(lastName: "COY", title: "MR. BERNIE", resNumber: "97255452"),
        ]),
        Flight(scheduledTime: "13:35", number: "KL 1819", airline: "KLM", origin: "Amsterdam (AMS)", terminal: "T3", passengers: [
            Passenger(lastName: "BRESHEARS", title: "MS. SHARON", resNumber: "97461791"),
            Passenger(lastName: "BRESHEARS", title: "MS. DONNA", resNumber: "97461792"),
        ]),
        Flight(scheduledTime: "14:55", number: "UA 926", airline: "United", origin: "San Francisco (SFO)", terminal: "T1", passengers: [
            Passenger(lastName: "CALICDAN", title: "MR. ALBERTO", resNumber: "96306831"),
            Passenger(lastName: "CALICDAN", title: "MRS. MARIA EMMA", resNumber: "96306832"),
        ]),
        Flight(scheduledTime: "18:00", number: "KL 1821", airline: "KLM", origin: "Amsterdam (AMS)", terminal: "T3", passengers: [
            Passenger(lastName: "RAMIREZ", title: "MRS. JULIA", resNumber: "98902901"),
            Passenger(lastName: "NICHOL", title: "MRS. CARYN", resNumber: "98902902"),
        ]),
    ]

    private static let builtInUnknownParties: [UnknownParty] = [
        UnknownParty(issue: "Gap in pax details / unknown hotel", passengers: [
            Passenger(lastName: "DULFER", title: "MR. JAMES", resNumber: "96642471"),
            Passenger(lastName: "DULFER", title: "MRS. ANNE", resNumber: "96642472"),
        ]),
        UnknownParty(issue: "Gap in pax details / unknown hotel", passengers: [
            Passenger(lastName: "DE GUIA", title: "MR. ANDREW", resNumber: "98684751"),
            Passenger(lastName: "DE GUIA", title: "MRS. LILIAN", resNumber: "98684752"),
        ]),
        UnknownParty(issue: "Unknown flight details", passengers: [
            Passenger(lastName: "ARMSTRONG", title: "MR. ROBERT", resNumber: "97842281"),
            Passenger(lastName: "ARMSTRONG", title: "MRS. CAROLE", resNumber: "97842282"),
        ]),
        UnknownParty(issue: "Gap in pax details / unknown hotel", passengers: [
            Passenger(lastName: "SCHROCK", title: "MRS. FRANCES", resNumber: "98177171"),
            Passenger(lastName: "KERL", title: "MR. KENNETH", resNumber: "98177172"),
        ]),
        UnknownParty(issue: "Gap in pax details / unknown hotel", passengers: [
            Passenger(lastName: "KLAPETZKY", title: "MR. DAVID", resNumber: "98049841"),
            Passenger(lastName: "KLAPETZKY", title: "MRS. NANCY", resNumber: "98049842"),
        ]),
        UnknownParty(issue: "Unknown flight details", passengers: [
            Passenger(lastName: "FITZPATRICK", title: "MRS. SHAYLEE", resNumber: "97792221"),
            Passenger(lastName: "DANAHER", title: "MRS. KERRI", resNumber: "97792222"),
        ]),
        UnknownParty(issue: "Gap in pax details / unknown hotel", passengers: [
            Passenger(lastName: "PETERSON", title: "MRS. NIKKI", resNumber: "98795991"),
            Passenger(lastName: "PETERSON", title: "MR. JOHN", resNumber: "98795992"),
        ]),
    ]
}
