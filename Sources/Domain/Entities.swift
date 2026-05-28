// Sources/Domain/Entities.swift
import Foundation

/// Канал вещания
public struct Channel: Decodable, Identifiable, Equatable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let country: String?
    public let languages: [String]
    public let categories: [String]
    public let logo: String?
    public let website: String?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case country
        case languages
        case categories
        case logo
        case website
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(String.self, forKey: .id)
        self.name = try container.decode(String.self, forKey: .name)
        self.country = try container.decodeIfPresent(String.self, forKey: .country)
        self.languages = (try container.decodeIfPresent([String].self, forKey: .languages)) ?? []
        self.categories = (try container.decodeIfPresent([String].self, forKey: .categories)) ?? []
        self.logo = try container.decodeIfPresent(String.self, forKey: .logo)
        self.website = try container.decodeIfPresent(String.self, forKey: .website)
    }
    
    public init(id: String, name: String, country: String?, languages: [String], categories: [String], logo: String?, website: String?) {
        self.id = id
        self.name = name
        self.country = country
        self.languages = languages
        self.categories = categories
        self.logo = logo
        self.website = website
    }
}

/// Стриминговый поток для канала
public struct Stream: Decodable, Equatable, Hashable, Sendable {
    public let channel: String
    public let urlString: String
    public let status: String?
    public let timeshift: Int?
    public let httpReferrer: String?

    public var url: URL? {
        if let encoded = urlString.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
            return URL(string: encoded)
        }
        return URL(string: urlString)
    }

    /// URL string with masked sensitive information (credentials, query parameters) for UI display
    public var maskedUrlString: String {
        guard var components = URLComponents(string: urlString) else {
            return urlString
        }

        // Mask user credentials
        if components.user != nil || components.password != nil {
            components.user = "****"
            if components.password != nil {
                components.password = "****"
            }
        }

        // Mask query parameter values to protect session tokens/keys
        if let queryItems = components.queryItems {
            components.queryItems = queryItems.map { URLQueryItem(name: $0.name, value: "****") }
        }

        return components.string ?? urlString
    }

    enum CodingKeys: String, CodingKey {
        case channel
        case url
        case status
        case timeshift
        case httpReferrer = "http_referrer"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.channel = try container.decode(String.self, forKey: .channel)
        self.urlString = try container.decode(String.self, forKey: .url)
        self.status = try container.decodeIfPresent(String.self, forKey: .status)
        self.timeshift = try container.decodeIfPresent(Int.self, forKey: .timeshift)
        self.httpReferrer = try container.decodeIfPresent(String.self, forKey: .httpReferrer)
    }
    
    public init(channel: String, urlString: String, status: String?, timeshift: Int?, httpReferrer: String?) {
        self.channel = channel
        self.urlString = urlString
        self.status = status
        self.timeshift = timeshift
        self.httpReferrer = httpReferrer
    }
}

/// Категория каналов
public struct Category: Decodable, Identifiable, Hashable, Sendable {
    public var id: String { name.lowercased() }
    public let name: String
}

/// Страна
public struct Country: Decodable, Identifiable, Hashable, Sendable {
    public var id: String { code }
    public let code: String
    public let name: String
    public let languages: [String]
    public let flag: String?
    
    enum CodingKeys: String, CodingKey {
        case code
        case name
        case languages
        case flag
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.code = try container.decode(String.self, forKey: .code)
        self.name = try container.decode(String.self, forKey: .name)
        self.languages = (try container.decodeIfPresent([String].self, forKey: .languages)) ?? []
        self.flag = try container.decodeIfPresent(String.self, forKey: .flag)
    }
    
    public init(code: String, name: String, languages: [String], flag: String?) {
        self.code = code
        self.name = name
        self.languages = languages
        self.flag = flag
    }
}

/// Язык вещания
public struct Language: Decodable, Identifiable, Hashable, Sendable {
    public var id: String { code }
    public let code: String
    public let name: String
}
