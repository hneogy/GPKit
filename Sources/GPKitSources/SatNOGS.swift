import Foundation
import GPKit

/// SatNOGS DB's transmitters (db.satnogs.org): the radios of the satellites, with what is needed to tune to them,
/// paired with GPKit's Doppler.
///
/// What SatNOGS says of its API and data, as GP Passes read it on 2026-10-07: "API access is open to anyone. All API
/// data are freely distributed under the CC BY-SA license" (docs.satnogs.org, the SatNOGS DB API page), and "All data
/// are public and freely distributed under the Creative Commons Atribution-Share Alike v4.0 license"
/// (db.satnogs.org/about). Neither page asks for an interval between requests, so the rules are GPKitSources' own,
/// the same as for CelesTrak: an address at most once in two hours, a stop at any answer that is not a 200, nothing
/// repeated. Wherever the data is shown, `credit` is to be shown with it.
public enum SatNOGS {

    public static let host = "db.satnogs.org"

    /// Every active transmitter of every satellite: one list, the API's own filter.
    public static let activeTransmitters = URL(string: "https://db.satnogs.org/api/transmitters/?format=json&status=active")!

    /// The credit CC BY-SA asks for: whose the data is, and the licence with its address.
    public static let credit = "Data from SatNOGS DB (db.satnogs.org), by Libre Space Foundation and its contributors, under CC BY-SA 4.0 (https://creativecommons.org/licenses/by-sa/4.0/)"

    /// Not the list the API describes.
    public struct Unreadable: Error, CustomStringConvertible {
        public let description: String
    }

    /// The transmitters in a list as the API gives it. Only the fields used here are read; the rest is passed over.
    public static func transmitters(from data: Data) throws(Unreadable) -> [Transmitter] {
        let entries: [Entry]
        do {
            entries = try JSONDecoder().decode([Entry].self, from: data)
        } catch {
            throw Unreadable(description: "not a list of SatNOGS DB transmitters: \(error)")
        }
        return entries.map(Transmitter.init)
    }

    /// Asks SatNOGS DB once for every active transmitter, if the rules allow it.
    public static func fetchActiveTransmitters(with client: SourceClient, now: Date = Date()) async -> Fetched<[Transmitter]> {
        await client.fetch(activeTransmitters, accept: "application/json", now: now) { data in
            do { return try transmitters(from: data) } catch { throw error }
        }
    }

    struct Entry: Decodable {
        let uuid: String
        let description: String?
        let type: String?
        let alive: Bool?
        let status: String?
        let uplink_low: Int64?
        let uplink_high: Int64?
        let downlink_low: Int64?
        let downlink_high: Int64?
        let mode: Words?
        let uplink_mode: Words?
        let invert: Bool?
        let baud: Double?
        let sat_id: String?
        let norad_cat_id: Int?
        let norad_follow_id: Int?
        let service: String?
        let unconfirmed: Bool?
        let updated: String?
    }

    /// A mode's name. The API's description calls it an integer and sends its name; either is taken.
    struct Words: Decodable {
        let text: String?

        init(from decoder: any Decoder) throws {
            let value = try decoder.singleValueContainer()
            if let text = try? value.decode(String.self) {
                self.text = text.isEmpty ? nil : text
            } else if let number = try? value.decode(Int.self) {
                self.text = String(number)
            } else {
                self.text = nil
            }
        }
    }
}

/// One transmitter, transceiver or transponder of a satellite, as SatNOGS DB describes it. Frequencies in hertz.
public struct Transmitter: Sendable, Hashable, Identifiable {
    /// SatNOGS DB's identifier for the entry.
    public var id: String
    /// For example "Mode V APRS".
    public var description: String
    /// "Transmitter", "Transceiver" or "Transponder".
    public var kind: String
    /// SatNOGS DB's identifier for the satellite.
    public var satelliteID: String?
    /// The catalog number SatNOGS DB lists the satellite under.
    public var catalogNumber: Int?
    /// The catalog number of the object SatNOGS DB follows for it while its own is not settled.
    public var followedCatalogNumber: Int?
    /// The downlink, or the bottom of a transponder's downlink range.
    public var downlinkLow: Int64?
    public var downlinkHigh: Int64?
    /// The uplink, or the bottom of a transponder's uplink range.
    public var uplinkLow: Int64?
    public var uplinkHigh: Int64?
    /// For example "AFSK".
    public var mode: String?
    public var uplinkMode: String?
    /// Symbols a second.
    public var baud: Double?
    /// True for an inverting transponder.
    public var inverting: Bool
    /// For example "Amateur".
    public var service: String?
    /// "active", "inactive" or "invalid".
    public var status: String?
    /// Whether SatNOGS DB holds the transmitter to be working.
    public var alive: Bool?
    /// True where SatNOGS DB marks the entry as not confirmed.
    public var unconfirmed: Bool
    /// When the entry was last changed, as SatNOGS DB writes it.
    public var updated: String?

    init(_ entry: SatNOGS.Entry) {
        id = entry.uuid
        description = entry.description ?? ""
        kind = entry.type ?? "Transmitter"
        satelliteID = entry.sat_id
        catalogNumber = entry.norad_cat_id
        followedCatalogNumber = entry.norad_follow_id
        downlinkLow = entry.downlink_low
        downlinkHigh = entry.downlink_high
        uplinkLow = entry.uplink_low
        uplinkHigh = entry.uplink_high
        mode = entry.mode?.text
        uplinkMode = entry.uplink_mode?.text
        baud = entry.baud
        inverting = entry.invert ?? false
        service = entry.service
        status = entry.status
        alive = entry.alive
        unconfirmed = entry.unconfirmed ?? false
        updated = entry.updated
    }

    /// What to tune a receiver to for the downlink at the satellite's look: its frequency with the Doppler shift.
    /// For a transponder, the bottom of the downlink range. Nil where there is no downlink.
    public func downlink(at look: Look) -> Double? {
        downlinkLow.map { look.received(from: Double($0)) }
    }

    /// What to send on for the signal to arrive at the satellite on its uplink, at its look. For a transponder, the
    /// bottom of the uplink range. Nil where there is no uplink.
    public func uplink(at look: Look) -> Double? {
        uplinkLow.map { look.transmit(toBeReceivedAt: Double($0)) }
    }

    /// Where a transponder sends down what arrives on `uplink`, at the satellite, before any Doppler: the same place
    /// in the downlink range, or the mirror place for an inverting one. Nil for a frequency outside the uplink range,
    /// or for an entry that is not a transponder with both ranges.
    public func downlink(forUplink uplink: Double) -> Double? {
        guard let uplinkLow, let uplinkHigh, let downlinkLow, let downlinkHigh, uplinkHigh > uplinkLow, downlinkHigh > downlinkLow,
              uplink >= Double(uplinkLow), uplink <= Double(uplinkHigh) else { return nil }
        let offset = uplink - Double(uplinkLow)
        return inverting ? Double(downlinkHigh) - offset : Double(downlinkLow) + offset
    }
}

extension Collection where Element == Transmitter {
    /// The transmitters of one satellite, by the catalog number SatNOGS DB lists it under or follows for it.
    public func of(catalogNumber: Int) -> [Transmitter] {
        filter { $0.catalogNumber == catalogNumber || $0.followedCatalogNumber == catalogNumber }
    }
}
