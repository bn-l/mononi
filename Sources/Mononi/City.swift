import Foundation

/// A city from the built-in list in Cities.swift, used to set the location by name.
struct City: Sendable {
    let name: String
    let region: String
    let country: String
    /// The ISO 3166 two-letter code, such as "AU"; empty for disputed areas.
    let countryCode: String
    let location: Location

    /// Every city in the built-in list, most populous first.
    static let all: [City] = table.split(separator: "\n").map { line in
        let field = line.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        return City(
            name: field[0], region: field[1], country: field[2], countryCode: field[3],
            location: Location(latitude: Double(field[4])!, longitude: Double(field[5])!)
        )
    }

    /// The cities matching `query`, most populous first. The query is a city name, optionally followed by
    /// a comma and a region, country or country code, as in "Newcastle, Australia" or "Portland, US".
    /// Matching ignores case and accents, and a region or country may be shortened from its start.
    static func matching(_ query: String) -> [City] {
        let parts = query.split(separator: ",", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces).folded }
        guard let name = parts.first else { return [] }
        let qualifier = parts.dropFirst().first
        return all.filter { city in
            city.name.folded == name && qualifier.map(city.isIn) ?? true
        }
    }

    /// Whether a folded region, country or country code names this city's region or country.
    private func isIn(_ qualifier: String) -> Bool {
        region.folded.hasPrefix(qualifier) || country.folded.hasPrefix(qualifier) || countryCode.folded == qualifier
    }

    /// The name with its region and country, leaving out a region that repeats the name, as in "Tokyo, Japan".
    var fullName: String {
        [name, region == name ? "" : region, country].filter { !$0.isEmpty }.joined(separator: ", ")
    }
}

private extension String {
    var folded: String { folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil) }
}
