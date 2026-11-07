import Foundation
import GPKit

/// CelesTrak's GP data, asked for by the queries CelesTrak documents (`gp.php`, on celestrak.org), and read by GPKit.
///
/// The rules are what CelesTrak asks, as gpconf records its pages (docs/RESEARCH.md of gp-omm-conformance, read
/// 2026-09-20 to 2026-10-05), and GPKit's own where CelesTrak sets none:
///
/// - GP data is updated every two hours and is to be downloaded once per update: an address is asked at most once
///   in two hours (`Ledger`), and within them its last good answer is given back (`Fetched.cached`);
/// - a program stops at any answer that is not a 200 and tells a person (CelesTrak's usage policy): such an answer
///   is given back as `stopped`, and nothing more is asked of celestrak.org for two hours, GPKit's own margin
///   under the firewall CelesTrak puts up for more than 50 errors from one address in two hours;
/// - nothing is repeated and no redirect is followed; always https://celestrak.org, since celestrak.com answers with
///   redirects, which count as errors;
/// - TLE formats do not carry objects above 99999, so such a request is not made (`Fetched.notAsked`).
///
/// A query asks for what CelesTrak has now; how it is answered is CelesTrak's. GPKitSources makes no request by
/// itself: only `fetch` does, when it is called.
public enum CelesTrak {

    public static let host = "celestrak.org"
    public static let gp = URL(string: "https://celestrak.org/NORAD/elements/gp.php")!

    /// What to ask for: one of CelesTrak's GP queries.
    public enum Query: Sendable, Hashable {
        /// One object, by its catalog number (`CATNR`).
        case catalogNumber(Int)
        /// The objects of one launch or one object, by international designator (`INTDES`), for example "1998-067".
        case internationalDesignator(String)
        /// One of CelesTrak's groups (`GROUP`), for example "amateur" or "stations".
        case group(String)
        /// Objects whose name holds the text (`NAME`).
        case name(String)
    }

    /// The form of the answer (`FORMAT`). CSV is CelesTrak's own default for GP queries.
    public enum AnswerFormat: String, Sendable, Hashable, CaseIterable {
        case csv = "CSV", json = "JSON", xml = "XML", kvn = "KVN", tle = "TLE"

        /// The format GPKit reads it as.
        public var format: Format {
            switch self {
            case .csv: .csv
            case .json: .json
            case .xml: .xml
            case .kvn: .kvn
            case .tle: .tle
            }
        }
    }

    /// The address of a query. Nil for text that is empty or holds a character a query cannot carry as it is.
    public static func url(_ query: Query, format: AnswerFormat = .csv) -> URL? {
        let (name, value): (String, String)
        switch query {
        case .catalogNumber(let number):
            guard number >= 0 else { return nil }
            (name, value) = ("CATNR", String(number))
        case .internationalDesignator(let text): (name, value) = ("INTDES", text)
        case .group(let text): (name, value) = ("GROUP", text)
        case .name(let text): (name, value) = ("NAME", text)
        }
        let allowed = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_.() ")
        guard !value.isEmpty, value.allSatisfy(allowed.contains) else { return nil }
        var parts = URLComponents(url: gp, resolvingAgainstBaseURL: false)!
        parts.queryItems = [URLQueryItem(name: name, value: value), URLQueryItem(name: "FORMAT", value: format.rawValue)]
        return parts.url
    }

    /// Asks CelesTrak once, if the rules allow it, and reads the answer as element sets. CelesTrak's own words for
    /// no data, `No GP data found`, read as a file with no element sets and that message: nothing to load is a result.
    public static func fetch(_ query: Query, format: AnswerFormat = .csv, with client: SourceClient, now: Date = Date()) async -> Fetched<ElementSetFile> {
        if format == .tle, case .catalogNumber(let number) = query, number > 99999 {
            return .notAsked("TLE formats do not carry objects above 99999; ask for \(number) as OMM (CSV, JSON, XML or KVN)")
        }
        guard let url = url(query, format: format) else { return .notAsked("the query's text is empty or holds a character a query cannot carry") }
        let read = format.format
        return await client.fetch(url, accept: "*/*", now: now) { data in
            do { return try ElementSets.read(data, as: read) } catch { throw error }
        }
    }
}
