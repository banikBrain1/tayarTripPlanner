//
//  ArrivalImporter.swift
//  tayarTripPlanner
//
//  Imports an arrival list from an .xlsx workbook, a PDF, or a photo of the
//  list (OCR). All parsing happens on-device.
//

import Foundation
import ImageIO
#if canImport(PDFKit)
import PDFKit
#endif
#if canImport(Vision)
import Vision
#endif

nonisolated enum ImportError: LocalizedError {
    case unsupportedType
    case unreadable
    case noRowsFound

    var errorDescription: String? {
        switch self {
        case .unsupportedType: return "Unsupported file type — use an Excel (.xlsx), PDF, or image file."
        case .unreadable: return "The file could not be read."
        case .noRowsFound: return "No passenger rows found. The list needs booking number, name, flight and time per row (like the Viking arrival sheet)."
        }
    }
}

nonisolated enum ArrivalImporter {

    // MARK: - Entry points

    static func load(url: URL) throws -> ArrivalDataSet {
        let secured = url.startAccessingSecurityScopedResource()
        defer { if secured { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else { throw ImportError.unreadable }

        switch url.pathExtension.lowercased() {
        case "xlsx": return try parseXLSX(data)
        case "pdf": return try parsePDF(data)
        case "png", "jpg", "jpeg", "heic", "heif", "tiff", "webp", "bmp": return try parseImage(data)
        default:
            // Fall back on content sniffing: ZIP magic → xlsx, %PDF → pdf, else image.
            if data.starts(with: [0x50, 0x4B]) { return try parseXLSX(data) }
            if data.starts(with: [0x25, 0x50, 0x44, 0x46]) { return try parsePDF(data) }
            return try parseImage(data)
        }
    }

    // MARK: - Raw record model shared by all sources

    struct RawRecord {
        var res = ""
        var lastName = ""
        var titleFirst = ""
        var flightField = ""
        var time = ""
        var startsBlock = false
        var isUnknown = false
    }

    // MARK: - XLSX

    static func parseXLSX(_ data: Data) throws -> ArrivalDataSet {
        let entries = MiniZip.entries(in: data)
        guard !entries.isEmpty else { throw ImportError.unreadable }

        var sharedStrings: [String] = []
        if MiniZip.extract("xl/sharedStrings.xml", from: data) != nil,
           let stringsData = MiniZip.extract("xl/sharedStrings.xml", from: data) {
            sharedStrings = SharedStringsParser.parse(stringsData)
        }

        // First worksheet by name order (sheet1.xml, sheet2.xml, …).
        let sheetNames = entries.map(\.name)
            .filter { $0.hasPrefix("xl/worksheets/sheet") && $0.hasSuffix(".xml") }
            .sorted()
        guard let firstSheet = sheetNames.first,
              let sheetData = MiniZip.extract(firstSheet, from: data) else { throw ImportError.unreadable }

        let rows = SheetParser.parse(sheetData, sharedStrings: sharedStrings)
        guard !rows.isEmpty else { throw ImportError.noRowsFound }

        // Column mapping: detect a header row, else assume the Viking layout B..G.
        var resCol = "B", lastCol = "C", firstCol = "D", flightCol = "E", timeCol = "F", paxCol = "G"
        var headerRow = -1
        for (rowIndex, cells) in rows.sorted(by: { $0.key < $1.key }) {
            for (col, value) in cells {
                let v = value.lowercased().replacingOccurrences(of: " ", with: "")
                if v == "resnumber" { resCol = col; headerRow = rowIndex }
                if v == "lastname" { lastCol = col }
                if v == "firstname" { firstCol = col }
                if v == "flight" { flightCol = col }
                if v == "time" { timeCol = col }
                if v == "pax" { paxCol = col }
            }
            if headerRow >= 0 { break }
        }

        var blocks: [[RawRecord]] = []
        var current: [RawRecord] = []
        var allText: [String] = []

        // Separator rows hold only empty cells, so they are absent from `rows` —
        // walk the full row range so gaps close the current block.
        let rowRange = rows.keys.min()!...rows.keys.max()!
        for rowIndex in rowRange {
            let cells = rows[rowIndex] ?? [:]
            allText.append(contentsOf: cells.values)
            if rowIndex <= headerRow { continue }

            let res = (cells[resCol] ?? "").trimmingCharacters(in: .whitespaces)
            let last = (cells[lastCol] ?? "").trimmingCharacters(in: .whitespaces)
            let flightField = (cells[flightCol] ?? "").trimmingCharacters(in: .whitespaces)

            if last.isEmpty && flightField.isEmpty {
                if !current.isEmpty { blocks.append(current); current = [] }
                continue
            }
            guard !last.isEmpty else { continue }

            var record = RawRecord()
            record.res = res.filter(\.isNumber)
            record.lastName = last
            record.titleFirst = (cells[firstCol] ?? "").trimmingCharacters(in: .whitespaces)
            record.flightField = flightField
            record.time = normalizeTime(cells[timeCol] ?? "")
            record.startsBlock = (cells[paxCol] ?? "").lowercased().contains("pax")
            record.isUnknown = isUnknownField(flightField)
            // Also split on the "N Pax" marker, for sheets without blank separator rows.
            if record.startsBlock, !current.isEmpty {
                blocks.append(current)
                current = []
            }
            current.append(record)
        }
        if !current.isEmpty { blocks.append(current) }

        return try buildDataSet(blocks: blocks, searchableText: allText.joined(separator: "\n"))
    }

    // MARK: - PDF

    static func parsePDF(_ data: Data) throws -> ArrivalDataSet {
        #if canImport(PDFKit)
        guard let document = PDFDocument(data: data) else { throw ImportError.unreadable }
        var text = ""
        for pageIndex in 0..<document.pageCount {
            text += (document.page(at: pageIndex)?.string ?? "") + "\n"
        }
        return try parseText(text)
        #else
        throw ImportError.unsupportedType
        #endif
    }

    // MARK: - Image (OCR)

    static func parseImage(_ data: Data) throws -> ArrivalDataSet {
        #if canImport(Vision)
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { throw ImportError.unreadable }

        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false
        try VNImageRequestHandler(cgImage: image).perform([request])
        let observations = request.results ?? []

        // Cluster observations into visual lines (top → bottom, then left → right).
        struct Piece { let text: String; let x: CGFloat; let y: CGFloat; let height: CGFloat }
        let pieces: [Piece] = observations.compactMap { obs in
            guard let candidate = obs.topCandidates(1).first else { return nil }
            let box = obs.boundingBox
            return Piece(text: candidate.string, x: box.minX, y: box.midY, height: box.height)
        }
        var lines: [[Piece]] = []
        for piece in pieces.sorted(by: { $0.y > $1.y }) {
            if var last = lines.last, let anchor = last.first,
               abs(anchor.y - piece.y) < max(anchor.height, piece.height) * 0.6 {
                last.append(piece)
                lines[lines.count - 1] = last
            } else {
                lines.append([piece])
            }
        }
        let text = lines
            .map { $0.sorted { $0.x < $1.x }.map(\.text).joined(separator: " ") }
            .joined(separator: "\n")
        return try parseText(text)
        #else
        throw ImportError.unsupportedType
        #endif
    }

    // MARK: - Plain-text parsing (PDF text layer and OCR output)

    static func parseText(_ text: String) throws -> ArrivalDataSet {
        var blocks: [[RawRecord]] = []
        var current: [RawRecord] = []

        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }
            guard let record = parseLine(line) else { continue }
            // New block on a "N Pax" marker, or when switching between regular
            // and unknown-details rows (flat text has no separator rows).
            if !current.isEmpty, record.startsBlock || record.isUnknown != current.last!.isUnknown {
                blocks.append(current)
                current = []
            }
            current.append(record)
        }
        if !current.isEmpty { blocks.append(current) }

        return try buildDataSet(blocks: blocks, searchableText: text)
    }

    /// One manifest line: "98094111 LASH MS. NANCY Boston 05:20 2 Pax"
    private static func parseLine(_ line: String) -> RawRecord? {
        var tokens = line.split(separator: " ").map(String.init)
        guard let first = tokens.first, first.count >= 6, first.allSatisfy(\.isNumber) else { return nil }

        var record = RawRecord()
        record.res = first
        tokens.removeFirst()

        if let paxRange = line.range(of: #"\d+\s*Pax"#, options: [.regularExpression, .caseInsensitive]) {
            record.startsBlock = true
            let marker = String(line[paxRange])
            tokens.removeAll { marker.contains($0) }
        }
        if let timeIndex = tokens.firstIndex(where: { $0.range(of: #"^([01]?\d|2[0-3]):[0-5]\d$"#, options: .regularExpression) != nil }) {
            record.time = normalizeTime(tokens[timeIndex])
            tokens.remove(at: timeIndex)
        }

        guard let titleIndex = tokens.firstIndex(where: { token in
            token.range(of: #"^(MR|MRS|MS|MISS|DR|MSTR|PROF)\.?$"#, options: .regularExpression) != nil
        }) else { return nil }

        record.lastName = tokens[..<titleIndex].joined(separator: " ")
        guard !record.lastName.isEmpty else { return nil }

        // First name: the run of fully UPPERCASE tokens after the title.
        // Origins are mixed-case ("Boston", "St. Louis"), which ends the run.
        var index = titleIndex + 1
        var firstName: [String] = []
        while index < tokens.count {
            let token = tokens[index]
            let letters = token.filter(\.isLetter)
            guard !letters.isEmpty, letters == letters.uppercased() else { break }
            // An uppercase token that reads as a flight designator ("LH 423",
            // "KLM 1821", "4Y65") ends the name and starts the flight field.
            if token.range(of: #"^([A-Z][A-Z0-9]{1,2}|\d[A-Z])\d{1,4}$"#, options: .regularExpression) != nil { break }
            if token.range(of: #"^([A-Z][A-Z0-9]{1,2}|\d[A-Z])$"#, options: .regularExpression) != nil,
               index + 1 < tokens.count,
               tokens[index + 1].range(of: #"^\d{1,4}$"#, options: .regularExpression) != nil { break }
            firstName.append(token)
            index += 1
        }
        record.titleFirst = ([tokens[titleIndex]] + firstName).joined(separator: " ")
        record.flightField = tokens[index...].joined(separator: " ")
        record.isUnknown = isUnknownField(record.flightField) || isUnknownField(line)
        return record
    }

    // MARK: - Blocks → data set

    private static let airlineInfo: [String: (name: String, terminal: String)] = [
        "LH": ("Lufthansa", "T1"), "UA": ("United", "T1"), "LX": ("SWISS", "T1"),
        "AC": ("Air Canada", "T1"), "4Y": ("Discover Airlines", "T1"), "OS": ("Austrian", "T1"),
        "SN": ("Brussels Airlines", "T1"), "TK": ("Turkish Airlines", "T1"), "SQ": ("Singapore Airlines", "T1"),
        "AA": ("American Airlines", "T3"), "DL": ("Delta", "T3"), "AF": ("Air France", "T3"),
        "BA": ("British Airways", "T3"), "KL": ("KLM", "T3"), "AY": ("Finnair", "T3"), "IB": ("Iberia", "T3"),
    ]

    static func buildDataSet(blocks: [[RawRecord]], searchableText: String) throws -> ArrivalDataSet {
        var flights: [Flight] = []
        var unknownParties: [UnknownParty] = []

        for block in blocks {
            guard !block.isEmpty else { continue }

            if block.contains(where: \.isUnknown) {
                unknownParties.append(contentsOf: extractUnknownParties(from: block))
                continue
            }

            var code = "", number = ""
            var origin = ""
            var time = ""
            for record in block {
                if time.isEmpty { time = record.time }
                let field = record.flightField
                if let match = flightMatch(in: field) {
                    if code.isEmpty { (code, number) = match }
                    if origin.isEmpty {
                        origin = removingFlightDesignator(from: field)
                    }
                } else if origin.isEmpty, field.contains(where: \.isLetter) {
                    origin = field
                }
            }

            let passengers = block.map {
                Passenger(lastName: $0.lastName, title: $0.titleFirst, resNumber: $0.res)
            }

            guard !code.isEmpty else {
                let issue = origin.isEmpty ? "Unknown flight details" : origin
                unknownParties.append(UnknownParty(issue: issue, passengers: passengers))
                continue
            }

            let canonical = code == "KLM" ? "KL" : code
            let info = airlineInfo[canonical]
            flights.append(Flight(
                scheduledTime: time.isEmpty ? "—" : time,
                number: "\(canonical) \(Int(number) ?? 0)",
                airline: info?.name ?? canonical,
                origin: origin.isEmpty ? "–" : origin,
                terminal: info?.terminal ?? "T?",
                passengers: passengers))
        }

        guard !flights.isEmpty || !unknownParties.isEmpty else { throw ImportError.noRowsFound }

        flights.sort { lhs, rhs in
            lhs.scheduledMinutes == rhs.scheduledMinutes
                ? lhs.number < rhs.number
                : lhs.scheduledMinutes < rhs.scheduledMinutes
        }

        // Arrival day: first dd.mm.yyyy found anywhere in the document.
        var year = 0, month = 0, day = 0
        var label = "Imported arrival list"
        if let match = firstRegexMatch(#"\b(\d{1,2})\.(\d{1,2})\.(\d{2,4})\b"#, in: searchableText),
           match.count == 4, let d = Int(match[1]), let m = Int(match[2]), var y = Int(match[3]),
           (1...31).contains(d), (1...12).contains(m) {
            if y < 100 { y += 2000 }
            (year, month, day) = (y, m, d)
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
            if let date = calendar.date(from: DateComponents(year: y, month: m, day: d)) {
                let formatter = DateFormatter()
                formatter.locale = Locale(identifier: "en_US")
                formatter.timeZone = calendar.timeZone
                formatter.dateFormat = "EEEE, d MMMM yyyy"
                label = formatter.string(from: date)
            }
        }

        return ArrivalDataSet(dayLabel: label, year: year, month: month, day: day,
                              flights: flights, unknownParties: unknownParties)
    }

    private static func extractUnknownParties(from block: [RawRecord]) -> [UnknownParty] {
        // Couples share a booking number except the last digit — group by that prefix.
        var parties: [UnknownParty] = []
        var currentKey = ""
        var currentIssue = ""
        var currentPassengers: [Passenger] = []
        for record in block {
            let key = String(record.res.dropLast())
            if key != currentKey, !currentPassengers.isEmpty {
                parties.append(UnknownParty(issue: currentIssue, passengers: currentPassengers))
                currentPassengers = []
            }
            currentKey = key
            if record.isUnknown, !record.flightField.isEmpty { currentIssue = record.flightField }
            if currentIssue.isEmpty { currentIssue = "Unknown flight details" }
            currentPassengers.append(Passenger(lastName: record.lastName, title: record.titleFirst, resNumber: record.res))
        }
        if !currentPassengers.isEmpty {
            parties.append(UnknownParty(issue: currentIssue, passengers: currentPassengers))
        }
        return parties
    }

    // MARK: - Small helpers

    private static func isUnknownField(_ text: String) -> Bool {
        let lower = text.lowercased()
        return lower.contains("unknown") || lower.contains("gap in")
    }

    /// Airline designator + flight number, e.g. "LH 443", "4Y65", "KLM 1821", "Dallas AA 70".
    private static func flightMatch(in text: String) -> (code: String, number: String)? {
        guard let groups = firstRegexMatch(#"\b([A-Z][A-Z0-9]{1,2}|\d[A-Z])\s*(\d{1,4})\b"#, in: text),
              groups.count == 3 else { return nil }
        let code = groups[1]
        guard code.contains(where: \.isLetter) else { return nil }
        return (code, groups[2])
    }

    private static func removingFlightDesignator(from text: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: #"\b([A-Z][A-Z0-9]{1,2}|\d[A-Z])\s*(\d{1,4})\b"#) else { return text }
        let range = NSRange(text.startIndex..., in: text)
        let stripped = regex.stringByReplacingMatches(in: text, range: range, withTemplate: "")
        return stripped.trimmingCharacters(in: CharacterSet(charactersIn: " /·,-–"))
    }

    private static func firstRegexMatch(_ pattern: String, in text: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: range) else { return nil }
        return (0..<match.numberOfRanges).map { index in
            guard let r = Range(match.range(at: index), in: text) else { return "" }
            return String(text[r])
        }
    }

    private static func normalizeTime(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        // Excel stores times as day fractions (e.g. 0.2222 = 05:20).
        if let fraction = Double(trimmed), fraction > 0, fraction < 1 {
            let totalMinutes = Int((fraction * 24 * 60).rounded())
            return String(format: "%02d:%02d", totalMinutes / 60, totalMinutes % 60)
        }
        guard let groups = firstRegexMatch(#"^([01]?\d|2[0-3]):([0-5]\d)"#, in: trimmed),
              groups.count == 3, let hour = Int(groups[1]) else { return "" }
        return String(format: "%02d:%@", hour, groups[2])
    }
}

// MARK: - XLSX XML parsing

private nonisolated final class SharedStringsParser: NSObject, XMLParserDelegate {
    private var strings: [String] = []
    private var current = ""
    private var inText = false

    static func parse(_ data: Data) -> [String] {
        let delegate = SharedStringsParser()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.parse()
        return delegate.strings
    }

    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String] = [:]) {
        if name == "si" { current = "" }
        if name == "t" { inText = true }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if inText { current += string }
    }

    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
        if name == "t" { inText = false }
        if name == "si" { strings.append(current) }
    }
}

private nonisolated final class SheetParser: NSObject, XMLParserDelegate {
    private var rows: [Int: [String: String]] = [:]
    private var sharedStrings: [String] = []
    private var cellRef = ""
    private var cellType = ""
    private var value = ""
    private var capturing = false

    static func parse(_ data: Data, sharedStrings: [String]) -> [Int: [String: String]] {
        let delegate = SheetParser()
        delegate.sharedStrings = sharedStrings
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.parse()
        return delegate.rows
    }

    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String] = [:]) {
        switch name {
        case "c":
            cellRef = attributes["r"] ?? ""
            cellType = attributes["t"] ?? ""
            value = ""
        case "v", "t":
            capturing = true
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if capturing { value += string }
    }

    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
        switch name {
        case "v", "t":
            capturing = false
        case "c":
            guard !cellRef.isEmpty, !value.isEmpty else { break }
            var text = value
            if cellType == "s", let index = Int(value), sharedStrings.indices.contains(index) {
                text = sharedStrings[index]
            }
            let column = String(cellRef.prefix(while: \.isLetter))
            let rowNumber = Int(cellRef.drop(while: \.isLetter)) ?? 0
            rows[rowNumber, default: [:]][column] = text
        default:
            break
        }
    }
}
