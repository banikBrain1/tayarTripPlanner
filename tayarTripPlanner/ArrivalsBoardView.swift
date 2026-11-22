//
//  ArrivalsBoardView.swift
//  tayarTripPlanner
//

import SwiftUI
import Combine
import UniformTypeIdentifiers

private let vikingRed = Color(red: 0.70, green: 0.13, blue: 0.20)

struct ArrivalsBoardView: View {
    @State private var store = ArrivalStore()
    @State private var showImporter = false
    @State private var importMessage: String?
    private let minuteClock = Timer.publish(every: 60, on: .main, in: .common).autoconnect()
    private let liveClock = Timer.publish(every: 300, on: .main, in: .common).autoconnect()

    private static let importTypes: [UTType] = [
        UTType(filenameExtension: "xlsx") ?? .data, .pdf, .image,
    ]

    var body: some View {
        NavigationStack {
            List {
                Section {
                    statsHeader
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                        .listRowSeparator(.hidden)
                }

                Section("Flights") {
                    ForEach(store.filteredFlights) { flight in
                        NavigationLink(value: flight) {
                            FlightRow(flight: flight, store: store)
                        }
                    }
                }

                if !store.filteredUnknownParties.isEmpty {
                    Section {
                        NavigationLink {
                            UnknownPartiesView(store: store)
                        } label: {
                            Label {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text("Needs follow-up")
                                        .fontWeight(.semibold)
                                    Text("\(store.dataset.totalUnknownPax) pax without flight details")
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                }
                            } icon: {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.orange)
                            }
                        }
                    }
                }

                Section {
                    EmptyView()
                } footer: {
                    Text(store.isImported
                         ? "Imported list · Live positions from the open ADS-B network, refreshed every 5 minutes. Tap a flight for passengers, baggage belt and exit info."
                         : "Source: 23.11.26_Viking.xlsx · Live positions from the open ADS-B network, refreshed every 5 minutes. Tap a flight for passengers, baggage belt and exit info.")
                }
            }
            .listSectionSpacing(.compact)
            .navigationTitle("FRA Arrivals")
            .navigationSubtitle(store.dataset.dayLabel)
            .navigationDestination(for: Flight.self) { flight in
                FlightDetailView(flight: flight, store: store)
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Button {
                            showImporter = true
                        } label: {
                            Label("Import list (Excel, PDF, photo)", systemImage: "square.and.arrow.down")
                        }
                        if store.isImported {
                            Button(role: .destructive) {
                                store.resetToBuiltIn()
                                Task { await store.refreshLive() }
                            } label: {
                                Label("Reset to original list", systemImage: "arrow.uturn.backward")
                            }
                        }
                    } label: {
                        Image(systemName: "square.and.arrow.down")
                    }
                    .accessibilityLabel("Import arrival list")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await store.refreshLive() }
                    } label: {
                        if store.isRefreshing {
                            ProgressView()
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                    .accessibilityLabel("Refresh live flight data")
                }
            }
            .fileImporter(isPresented: $showImporter, allowedContentTypes: Self.importTypes) { result in
                switch result {
                case .success(let url):
                    Task {
                        do {
                            let imported = try await Task.detached { try ArrivalImporter.load(url: url) }.value
                            store.applyImported(imported)
                            importMessage = "Imported \(imported.flights.count) flights · \(imported.totalFlightPax) passengers"
                                + (imported.unknownParties.isEmpty ? "" : " · \(imported.totalUnknownPax) need follow-up")
                            await store.refreshLive()
                        } catch {
                            importMessage = error.localizedDescription
                        }
                    }
                case .failure(let error):
                    importMessage = error.localizedDescription
                }
            }
            .alert("Import", isPresented: Binding(
                get: { importMessage != nil },
                set: { if !$0 { importMessage = nil } }
            )) {
                Button("OK") { importMessage = nil }
            } message: {
                Text(importMessage ?? "")
            }
            .searchable(text: $store.searchText, prompt: "Name, flight, booking no.")
            .task { await store.refreshLive() }
            .refreshable { await store.refreshLive() }
            .onReceive(minuteClock) { store.now = $0 }
            .onReceive(liveClock) { _ in
                Task { await store.refreshLive() }
            }
        }
        .tint(vikingRed)
    }

    private var statsHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                StatTile(value: "\(store.dataset.flights.count)", label: "Flights")
                StatTile(value: "\(store.dataset.totalFlightPax)", label: "Pax")
                StatTile(value: "\(store.dataset.totalUnknownPax)", label: "Unconfirmed")
                StatTile(value: "\(store.totalMet)", label: "Met", accent: true)
            }
            HStack(spacing: 5) {
                Image(systemName: "dot.radiowaves.left.and.right")
                    .font(.caption2)
                if let error = store.liveError {
                    Text(error)
                } else if store.isRefreshing {
                    Text("Updating live data…")
                } else if let refreshed = store.lastLiveRefresh {
                    Text("Live data \(refreshed.formatted(date: .omitted, time: .shortened)) · auto-refresh every 5 min")
                } else {
                    Text("Fetching live data…")
                }
            }
            .font(.caption)
            .foregroundStyle(store.liveError == nil ? Color.secondary : Color.orange)
        }
    }
}

private struct StatTile: View {
    let value: String
    let label: String
    var accent = false

    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.title3.weight(.bold).monospacedDigit())
                .foregroundStyle(accent ? vikingRed : .primary)
            Text(label.uppercased())
                .font(.caption2.weight(.semibold))
                .kerning(0.8)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - Home list row: time, flight, status only

private struct FlightRow: View {
    let flight: Flight
    let store: ArrivalStore
    @State private var copied = false

    var body: some View {
        HStack(spacing: 12) {
            Text(flight.scheduledTime)
                .font(.title3.weight(.bold).monospacedDigit())
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(flight.number)
                        .font(.headline.monospaced())
                    Button {
                        UIPasteboard.general.string = flight.number
                        copied = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
                    } label: {
                        Image(systemName: copied ? "checkmark" : "document.on.document")
                            .font(.caption)
                            .foregroundStyle(copied ? .green : vikingRed)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Copy flight number \(flight.number)")
                }
                Text("from \(flight.origin)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            let status = store.displayStatus(for: flight)
            StatusChip(label: status.label, kind: status.kind)
        }
        .padding(.vertical, 10)
    }
}

// MARK: - Flight detail: passengers, terminal, live links

private struct FlightDetailView: View {
    let flight: Flight
    @Bindable var store: ArrivalStore
    @Environment(\.openURL) private var openURL

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(flight.scheduledTime)
                            .font(.largeTitle.weight(.bold).monospacedDigit())
                        VStack(alignment: .leading, spacing: 1) {
                            HStack(spacing: 8) {
                                Text(flight.number)
                                    .font(.headline.monospaced())
                                TerminalBadge(terminal: flight.terminal)
                            }
                            Text("from \(flight.origin) · \(flight.airline)")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }

                    HStack(spacing: 6) {
                        let status = store.displayStatus(for: flight)
                        StatusChip(label: status.label, kind: status.kind)
                        let met = store.metCount(for: flight)
                        Text(met == flight.passengers.count && met > 0
                             ? "all \(met) met"
                             : "\(met)/\(flight.passengers.count) met")
                            .font(.caption.weight(.semibold).monospacedDigit())
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(met == flight.passengers.count && met > 0
                                        ? Color.green.opacity(0.15)
                                        : Color.secondary.opacity(0.12),
                                        in: Capsule())
                            .foregroundStyle(met == flight.passengers.count && met > 0 ? .green : .secondary)
                    }
                }
                .listRowSeparator(.hidden)
            }

            Section("Live status") {
                LiveStatusPanel(flight: flight, store: store)

                Button {
                    Task { await store.refreshLive() }
                } label: {
                    HStack {
                        if store.isRefreshing {
                            ProgressView()
                            Text("Checking…")
                        } else {
                            Image(systemName: "dot.radiowaves.left.and.right")
                            Text("Check status now")
                        }
                    }
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(store.isRefreshing)
                .listRowSeparator(.hidden)

                HStack(spacing: 8) {
                    Button {
                        openURL(flight.fraLiveURL)
                    } label: {
                        Label("FRA Live · belt · exit", systemImage: "safari")
                            .font(.footnote.weight(.semibold))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)

                    Button {
                        openURL(flight.flightradarURL)
                    } label: {
                        Label("Track", systemImage: "airplane")
                            .font(.footnote.weight(.semibold))
                    }
                    .buttonStyle(.bordered)
                }
            }

            Section("Passengers · tap to check off as met") {
                ForEach(flight.passengers) { passenger in
                    PassengerRow(passenger: passenger, isMet: store.isMet(passenger)) {
                        store.toggleMet(passenger)
                    }
                }
            }

            Section {
                EmptyView()
            } footer: {
                Text("Gate / exit and baggage belt are assigned by the airport on the day — FRA Live opens the official Frankfurt Airport page for this flight.")
            }
        }
        .navigationTitle(flight.number)
        .navigationBarTitleDisplayMode(.inline)
        .tint(vikingRed)
    }
}

/// Shows matched live aircraft data for one flight, or the fallback explanation.
private struct LiveStatusPanel: View {
    let flight: Flight
    let store: ArrivalStore

    var body: some View {
        if let info = store.liveInfo(for: flight) {
            VStack(alignment: .leading, spacing: 6) {
                if info.onGround {
                    Label("On the ground · \(Int(info.distanceKm.rounded())) km from FRA", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.subheadline.weight(.semibold))
                } else {
                    Label("Airborne · \(Int(info.distanceKm.rounded())) km from FRA", systemImage: "airplane")
                        .foregroundStyle(.blue)
                        .font(.subheadline.weight(.semibold))
                }
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 3) {
                    GridRow {
                        Text("Callsign")
                        Text(info.callsign).font(.footnote.monospaced())
                    }
                    if let altitude = info.altitudeFt {
                        GridRow {
                            Text("Altitude")
                            Text("\(altitude.formatted()) ft").font(.footnote.monospaced())
                        }
                    }
                    if let speed = info.groundSpeedKt {
                        GridRow {
                            Text("Speed")
                            Text("\(Int(speed)) kt").font(.footnote.monospaced())
                        }
                    }
                    if let eta = info.etaMinutes, !info.onGround {
                        GridRow {
                            Text("Rough ETA")
                            Text("~\(eta) min").font(.footnote.monospaced())
                        }
                    }
                    GridRow {
                        Text("Checked")
                        Text(info.fetchedAt.formatted(date: .omitted, time: .shortened)).font(.footnote.monospaced())
                    }
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
            .padding(.vertical, 2)
        } else {
            VStack(alignment: .leading, spacing: 4) {
                Text("No live signal")
                    .font(.subheadline.weight(.semibold))
                Text(store.lastLiveRefresh == nil
                     ? "Live data not fetched yet — tap Check status now."
                     : "Aircraft not within ~460 km of Frankfurt — not yet in range, already parked, or flying under a different callsign. Schedule says: \(store.status(for: flight).label).")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 2)
        }
    }
}

private struct TerminalBadge: View {
    let terminal: String

    var body: some View {
        Text(terminal)
            .font(.caption.weight(.bold))
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(vikingRed.opacity(0.14), in: RoundedRectangle(cornerRadius: 5))
            .foregroundStyle(vikingRed)
    }
}

private struct StatusChip: View {
    let label: String
    let kind: StatusKind

    var body: some View {
        Text(label)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(background, in: Capsule())
            .foregroundStyle(foreground)
    }

    private var background: Color {
        switch kind {
        case .neutral: return Color.secondary.opacity(0.12)
        case .soon: return Color.orange.opacity(0.18)
        case .due: return vikingRed
        case .ok: return Color.green.opacity(0.15)
        case .live: return Color.blue.opacity(0.15)
        }
    }

    private var foreground: Color {
        switch kind {
        case .neutral: return .secondary
        case .soon: return .orange
        case .due: return .white
        case .ok: return .green
        case .live: return .blue
        }
    }
}

private struct PassengerRow: View {
    let passenger: Passenger
    let isMet: Bool
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            HStack(spacing: 10) {
                Image(systemName: isMet ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isMet ? .green : .secondary)
                Text("\(Text(passenger.lastName).fontWeight(.semibold).foregroundStyle(isMet ? Color.green : Color.primary)) \(Text(passenger.title).foregroundStyle(.secondary))")
                Spacer()
                Text(passenger.resNumber)
                    .font(.caption.monospaced())
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(passenger.displayName), \(isMet ? "met" : "not met")")
    }
}

// MARK: - Unknown parties

private struct UnknownPartiesView: View {
    let store: ArrivalStore

    var body: some View {
        List {
            Section {
                ForEach(store.filteredUnknownParties) { party in
                    UnknownPartyRow(party: party)
                }
            } footer: {
                Text("On the list for 23.11. but without flight or hotel information. Chase with the office before the first wave lands.")
            }
        }
        .navigationTitle("Needs follow-up")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct UnknownPartyRow: View {
    let party: UnknownParty

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(party.issue.uppercased())
                .font(.caption2.weight(.bold))
                .kerning(0.6)
                .foregroundStyle(.orange)
            ForEach(party.passengers) { passenger in
                HStack {
                    Text("\(Text(passenger.lastName).fontWeight(.semibold)) \(Text(passenger.title).foregroundStyle(.secondary))")
                    Spacer()
                    Text(passenger.resNumber)
                        .font(.caption.monospaced())
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    ArrivalsBoardView()
}
