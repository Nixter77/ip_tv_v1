// Sources/Data/DTOs/PlaylistDTOs.swift
// Transport models for iptv-org JSON — mapped to Domain entities.
import Foundation

struct ChannelDTO: Decodable {
    let id: String
    let name: String
    let country: String?
    let languages: [String]?
    let categories: [String]?
    let logo: String?
    let website: String?

    func toDomain() -> Channel {
        Channel(
            id: id,
            name: name,
            country: country,
            languages: languages ?? [],
            categories: categories ?? [],
            logo: logo,
            website: website
        )
    }
}

struct StreamDTO: Decodable {
    let channel: String
    let url: String
    let status: String?
    let timeshift: Int?
    let httpReferrer: String?

    enum CodingKeys: String, CodingKey {
        case channel
        case url
        case status
        case timeshift
        case httpReferrer = "http_referrer"
    }

    func toDomain() -> Stream {
        Stream(
            channel: channel,
            urlString: url,
            status: status,
            timeshift: timeshift,
            httpReferrer: httpReferrer
        )
    }
}

struct CategoryDTO: Decodable {
    let name: String

    func toDomain() -> Category {
        Category(name: name)
    }
}

struct CountryDTO: Decodable {
    let code: String
    let name: String
    let languages: [String]?
    let flag: String?

    func toDomain() -> Country {
        Country(code: code, name: name, languages: languages ?? [], flag: flag)
    }
}

struct LanguageDTO: Decodable {
    let code: String
    let name: String

    func toDomain() -> Language {
        Language(code: code, name: name)
    }
}
