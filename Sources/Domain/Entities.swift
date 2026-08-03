// Sources/Domain/Entities.swift
// Pure domain models — no Decodable / transport coupling.
import Foundation

/// Канал вещания
public struct Channel: Identifiable, Equatable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let country: String?
    public let languages: [String]
    public let categories: [String]
    public let logo: String?
    public let website: String?

    public init(
        id: String,
        name: String,
        country: String?,
        languages: [String],
        categories: [String],
        logo: String?,
        website: String?
    ) {
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
public struct Stream: Equatable, Hashable, Sendable {
    public let channel: String
    public let urlString: String
    public let status: String?
    public let timeshift: Int?
    public let httpReferrer: String?

    private static let iptvUrlAllowed: CharacterSet = {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.insert("#")
        return allowed
    }()

    public init(channel: String, urlString: String, status: String?, timeshift: Int?, httpReferrer: String?) {
        self.channel = channel
        self.urlString = urlString
        self.status = status
        self.timeshift = timeshift
        self.httpReferrer = httpReferrer
    }

    public var url: URL? {
        if let url = URL(string: urlString),
           let scheme = url.scheme?.lowercased(),
           scheme == "http" || scheme == "https" {
            return url
        }
        guard let encodedString = urlString.addingPercentEncoding(withAllowedCharacters: Self.iptvUrlAllowed),
              let url = URL(string: encodedString),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            return nil
        }
        return url
    }

    public var maskedUrlString: String {
        Self.mask(urlString)
    }

    public static func mask(_ urlString: String) -> String {
        var components = URLComponents(string: urlString)
        if components == nil, let encoded = urlString.addingPercentEncoding(withAllowedCharacters: Self.iptvUrlAllowed) {
            components = URLComponents(string: encoded)
        }

        guard var components = components, components.scheme != nil else {
            return urlString.replacingOccurrences(of: "://[^@]+@", with: "://****@", options: .regularExpression)
        }

        if components.user != nil || components.password != nil {
            components.user = "****"
            if components.password != nil {
                components.password = "****"
            }
        }

        if let queryItems = components.queryItems {
            components.queryItems = queryItems.map { URLQueryItem(name: $0.name, value: "****") }
        }

        if components.queryItems == nil, components.path.contains("=") {
            components.path = components.path
                .split(separator: "/", omittingEmptySubsequences: false)
                .map { segment in
                    guard let equalsIndex = segment.firstIndex(of: "=") else {
                        return String(segment)
                    }
                    return String(segment[...equalsIndex]) + "****"
                }
                .joined(separator: "/")
        }

        if components.fragment != nil {
            components.fragment = "****"
        }

        return components.string ?? urlString
    }

    public static func maskURLs(in text: String) -> String {
        let pattern = #"https?://[^\s]+"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return text
        }

        var result = text
        let fullRange = NSRange(text.startIndex..<text.endIndex, in: text)
        let matches = regex.matches(in: text, range: fullRange)

        for match in matches.reversed() {
            guard let matchRange = Range(match.range, in: result) else { continue }
            let urlString = String(result[matchRange])
            result.replaceSubrange(matchRange, with: mask(urlString))
        }

        return result
    }
}

/// Категория каналов
public struct Category: Identifiable, Hashable, Sendable {
    public var id: String { name.lowercased() }
    public let name: String

    public init(name: String) {
        self.name = name
    }
}

/// Страна
public struct Country: Identifiable, Hashable, Sendable {
    public var id: String { code }
    public let code: String
    public let name: String
    public let languages: [String]
    public let flag: String?

    public init(code: String, name: String, languages: [String], flag: String?) {
        self.code = code
        self.name = name
        self.languages = languages
        self.flag = flag
    }
}

/// Язык вещания
public struct Language: Identifiable, Hashable, Sendable {
    public var id: String { code }
    public let code: String
    public let name: String

    public init(code: String, name: String) {
        self.code = code
        self.name = name
    }
}
