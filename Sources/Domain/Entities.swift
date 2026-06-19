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

    /// Allowed characters for IPTV URL robust parsing (including # fragment which is NOT in urlQueryAllowed)
    private static let iptvUrlAllowed: CharacterSet = {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.insert("#")
        return allowed
    }()

    public var url: URL? {
        // Try standard parsing first.
        if let url = URL(string: urlString),
           let scheme = url.scheme?.lowercased(),
           scheme == "http" || scheme == "https" {
            return url
        }

        // Robust parsing fallback: IPTV stream URLs often contain unencoded spaces.
        // We encode spaces but MUST preserve query/fragment structure (# and ?) before initializing URL.
        guard let encodedString = urlString.addingPercentEncoding(withAllowedCharacters: Self.iptvUrlAllowed),
              let url = URL(string: encodedString),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            return nil
        }

        return url
    }

    /// URL string with masked sensitive information (credentials, query parameters, fragments) for UI display
    public var maskedUrlString: String {
        Self.mask(urlString)
    }

    /// Masks sensitive information in a single URL string for secure logging and UI display.
    /// Uses a defense-in-depth approach with both URL parser and robust regex fallbacks.
    public static func mask(_ urlString: String) -> String {
        var result = urlString

        // Step 1: Use URLComponents for structured credential masking if possible.
        var components = URLComponents(string: urlString)
        if components == nil, let encoded = urlString.addingPercentEncoding(withAllowedCharacters: Self.iptvUrlAllowed) {
            components = URLComponents(string: encoded)
        }

        if var components = components, components.scheme != nil {
            if components.user != nil || components.password != nil {
                components.user = "****"
                if components.password != nil { components.password = "****" }
                result = components.string ?? urlString
            }
        } else {
            // Regex fallback for credentials in malformed URLs
            result = result.replacingOccurrences(
                of: #"://[^/@\s]+(?=@)"#,
                with: "://****:****",
                options: .regularExpression
            )
        }

        // Step 2: Robust regex masking for parameter values.
        // This handles query items, path-based tokens, and fragments with any delimiter (?, &, /, |, ;, #).
        // It preserves the key and masks the value, supporting unencoded spaces.
        result = result.replacingOccurrences(
            of: #"(?<=[?&/|;#])([^?&/|;=\s#]+)=[^?&/|;#]+"#,
            with: "$1=****",
            options: .regularExpression
        )

        // Step 3: Mask simple fragments that don't contain key=value pairs (already handled above).
        if let hashIndex = result.lastIndex(of: "#") {
            let fragment = result[result.index(after: hashIndex)...]
            if !fragment.isEmpty && !fragment.contains("/") && !fragment.contains("=") {
                result = String(result[...hashIndex]) + "****"
            }
        }

        return result
    }

    /// Finds and masks all URLs within a text string to prevent sensitive data leakage in error messages or logs
    public static func maskURLs(in text: String) -> String {
        let pattern = #"https?://[^\s]+"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return text
        }

        var result = text
        let fullRange = NSRange(text.startIndex..<text.endIndex, in: text)
        let matches = regex.matches(in: text, range: fullRange)

        // Iterate backwards to avoid invalidating later ranges as replacements change string length.
        for match in matches.reversed() {
            guard let matchRange = Range(match.range, in: result) else { continue }
            let urlString = String(result[matchRange])
            result.replaceSubrange(matchRange, with: mask(urlString))
        }

        return result
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
