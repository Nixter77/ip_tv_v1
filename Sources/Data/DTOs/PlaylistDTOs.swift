// Sources/Data/DTOs/PlaylistDTOs.swift
// Transport models for iptv-org JSON — mapped to Domain entities.
import Foundation

struct ChannelDTO: Decodable, Sendable {
    let id: String
    let name: String
    let country: String?
    let languages: [String]?
    let categories: [String]?
    let logo: String?
    let website: String?
    let altNames: [String]?
    let network: String?
    let isNSFW: Bool?
    let closed: String?
    let replacedBy: String?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case country
        case languages
        case categories
        case logo
        case website
        case altNames = "alt_names"
        case network
        case isNSFW = "is_nsfw"
        case closed
        case replacedBy = "replaced_by"
    }
}

struct LogoDTO: Decodable, Sendable {
    let channel: String?
    let url: String?
    let inUse: Bool?

    enum CodingKeys: String, CodingKey {
        case channel
        case url
        case inUse = "in_use"
    }
}

struct FeedDTO: Decodable, Sendable {
    let channel: String?
    let languages: [String]?
}

struct StreamDTO: Decodable, Sendable {
    let channel: String
    let url: String
    let status: String?
    let timeshift: Int?
    let httpReferrer: String?
    let userAgent: String?
    let quality: String?
    let feed: String?
    let title: String?

    enum CodingKeys: String, CodingKey {
        case channel
        case url
        case status
        case timeshift
        case httpReferrer = "http_referrer"
        case referrer
        case userAgent = "user_agent"
        case quality
        case feed
        case title
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let channel = try container.decodeIfPresent(String.self, forKey: .channel) ?? ""
        self.channel = channel
        self.url = try container.decodeIfPresent(String.self, forKey: .url) ?? ""
        self.status = try container.decodeIfPresent(String.self, forKey: .status)
        self.timeshift = try container.decodeIfPresent(Int.self, forKey: .timeshift)
        let referrer = try container.decodeIfPresent(String.self, forKey: .referrer)
        let legacyReferrer = try container.decodeIfPresent(String.self, forKey: .httpReferrer)
        self.httpReferrer = RemoteURLPolicy.sanitizedHTTPHeaderValue(referrer ?? legacyReferrer)
        self.userAgent = RemoteURLPolicy.sanitizedUserAgent(
            try container.decodeIfPresent(String.self, forKey: .userAgent)
        )
        self.quality = try container.decodeIfPresent(String.self, forKey: .quality)
        self.feed = try container.decodeIfPresent(String.self, forKey: .feed)
        self.title = try container.decodeIfPresent(String.self, forKey: .title)
    }

    func toDomain() -> Stream? {
        guard !channel.isEmpty, !url.isEmpty else { return nil }
        return Stream(
            channel: channel,
            urlString: url,
            status: status,
            timeshift: timeshift,
            httpReferrer: httpReferrer,
            userAgent: userAgent,
            quality: quality,
            feed: feed,
            title: title
        )
    }
}

struct CategoryDTO: Decodable, Sendable {
    let id: String?
    let name: String

    func toDomain() -> Category {
        let trimmedID = id?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if trimmedID.isEmpty {
            return Category(name: name)
        }
        return Category(id: trimmedID, name: name)
    }
}

struct CountryDTO: Decodable, Sendable {
    let code: String
    let name: String
    let languages: [String]?
    let flag: String?

    func toDomain() -> Country {
        Country(code: code, name: name, languages: languages ?? [], flag: flag)
    }
}

struct LanguageDTO: Decodable, Sendable {
    let code: String
    let name: String

    func toDomain() -> Language {
        Language(code: code, name: name)
    }
}

enum CatalogAssembler {
    static func channels(
        from rows: [ChannelDTO],
        logos: [LogoDTO],
        feeds: [FeedDTO]
    ) -> [Channel] {
        let logosByChannel = Dictionary(grouping: logos.compactMap { logo -> (String, LogoDTO)? in
            guard let channel = logo.channel, !channel.isEmpty else { return nil }
            return (channel, logo)
        }, by: { $0.0 }).mapValues { pairs in pairs.map(\.1) }

        var languagesByChannel: [String: [String]] = [:]
        for feed in feeds {
            guard let channel = feed.channel, !channel.isEmpty else { continue }
            let codes = feed.languages ?? []
            guard !codes.isEmpty else { continue }
            var existing = languagesByChannel[channel] ?? []
            for code in codes where !existing.contains(code) {
                existing.append(code)
            }
            languagesByChannel[channel] = existing
        }

        return rows.map { row in
            let inlineLanguages = row.languages ?? []
            let languages = inlineLanguages.isEmpty
                ? (languagesByChannel[row.id] ?? [])
                : inlineLanguages
            return Channel(
                id: row.id,
                name: row.name,
                country: row.country,
                languages: languages,
                categories: row.categories ?? [],
                logo: logoURL(inline: row.logo, logos: logosByChannel[row.id] ?? []),
                website: RemoteURLPolicy.validatedURL(from: row.website, kind: .remoteAsset) != nil ? row.website : nil,
                isNSFW: row.isNSFW ?? false,
                closed: row.closed,
                altNames: row.altNames ?? [],
                network: row.network,
                replacedBy: row.replacedBy
            )
        }
    }

    private static func logoURL(inline: String?, logos: [LogoDTO]) -> String? {
        if let inline, RemoteURLPolicy.validatedURL(from: inline, kind: .remoteAsset) != nil {
            return inline
        }
        let ordered = logos.sorted { ($0.inUse == true ? 0 : 1) < ($1.inUse == true ? 0 : 1) }
        for logo in ordered {
            if let url = logo.url, RemoteURLPolicy.validatedURL(from: url, kind: .remoteAsset) != nil {
                return url
            }
        }
        return nil
    }
}
