// Sources/Domain/RemoteURLPolicy.swift
// Single allowlist for untrusted catalog URLs, redirects, and HTTP header tokens.
import Foundation
#if canImport(Darwin)
import Darwin
#endif

/// What the URL will be used for. Streams may target a LAN encoder; logos must not.
public enum RemoteResourceKind: Sendable, Equatable {
    /// Logos, Referer, decorative fetches: public http(s), no credentials.
    case remoteAsset
    /// Playback: http(s) including loopback / RFC1918 (local IPTV).
    case mediaStream
}

/// Policy for URLs and header values that originate outside the process.
public enum RemoteURLPolicy: Sendable {
    public static let maxLogoBytes = 512 * 1024
    public static let maxPlaylistBytes = 64 * 1024 * 1024
    public static let maxSearchQueryLength = 200
    public static let maxPersistedIDLength = 128
    public static let maxPersistedNameLength = 200

    private static let iptvURLAllowed: CharacterSet = {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.insert("#")
        return allowed
    }()

    /// Parses `http`/`https` only. Rejects `file`, `data`, CTL injection, and (for assets) LAN/userinfo.
    public static func validatedURL(from raw: String?, kind: RemoteResourceKind) -> URL? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if containsHeaderInjection(trimmed) { return nil }

        if let url = parseHTTPURL(trimmed) {
            return accept(url, kind: kind)
        }
        guard let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: iptvURLAllowed),
              let url = parseHTTPURL(encoded) else {
            return nil
        }
        return accept(url, kind: kind)
    }

    public static func shouldFollowRedirect(to url: URL, kind: RemoteResourceKind) -> Bool {
        validatedURL(from: url.absoluteString, kind: kind) != nil
    }

    /// Drops CR/LF/NUL/other CTL so persisted ETag / Referer cannot inject headers.
    public static func sanitizedHTTPHeaderValue(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if containsHeaderInjection(trimmed) { return nil }
        return trimmed
    }

    public static func isRestrictedHost(_ host: String) -> Bool {
        var normalized = host.lowercased()
        if normalized.hasPrefix("[") && normalized.hasSuffix("]") {
            normalized = String(normalized.dropFirst().dropLast())
        }
        if normalized.hasSuffix(".") {
            normalized = String(normalized.dropLast())
        }
        guard !normalized.isEmpty else { return true }

        if normalized == "localhost"
            || normalized.hasSuffix(".localhost")
            || normalized.hasSuffix(".local")
            || normalized.hasSuffix(".internal")
            || normalized.hasSuffix(".lan")
            || normalized.hasSuffix(".home")
            || normalized == "metadata.google.internal" {
            return true
        }

        // 1. Check standard IPv4 / IPv6 parsing via inet_pton
        var addr4 = in_addr()
        if inet_pton(AF_INET, normalized, &addr4) == 1 {
            let ip = UInt32(bigEndian: addr4.s_addr)
            return isRestrictedIPv4(ip)
        }

        var addr6 = in6_addr()
        if inet_pton(AF_INET6, normalized, &addr6) == 1 {
            return isRestrictedIPv6Address(addr6)
        }

        // 2. Custom parser for forms inet_pton rejects (e.g. dword 2130706433, shorthand 127.1)
        if let ipv4 = parseIPv4(normalized) {
            return isRestrictedIPv4(ipv4)
        }
        if normalized.contains(":") {
            return isRestrictedIPv6(normalized)
        }
        return false
    }

    public static func isLiteralIPAddress(_ host: String) -> Bool {
        var normalized = host.lowercased()
        if normalized.hasPrefix("[") && normalized.hasSuffix("]") {
            normalized = String(normalized.dropFirst().dropLast())
        }
        var addr4 = in_addr()
        if inet_pton(AF_INET, normalized, &addr4) == 1 { return true }
        var addr6 = in6_addr()
        if inet_pton(AF_INET6, normalized, &addr6) == 1 { return true }
        return parseIPv4(normalized) != nil || normalized.contains(":")
    }

    /// Fail-closed DNS check to reduce DNS-rebinding against loopback/LAN.
    public static func resolvesOnlyToPublicAddresses(host: String) async -> Bool {
        if isRestrictedHost(host) { return false }
        if isLiteralIPAddress(host) {
            return !isRestrictedHost(host)
        }
        return await Task.detached(priority: .utility) {
            Self.resolvesOnlyToPublicAddressesSync(host: host)
        }.value
    }

    // MARK: - Parse

    private static func containsHeaderInjection(_ value: String) -> Bool {
        if value.unicodeScalars.contains(where: { $0.value < 0x20 || $0.value == 0x7F }) {
            return true
        }
        let lowered = value.lowercased()
        return lowered.contains("%0d") || lowered.contains("%0a") || lowered.contains("%00")
    }

    private static func parseHTTPURL(_ raw: String) -> URL? {
        guard let url = URL(string: raw),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              !url.isFileURL,
              let host = url.host, !host.isEmpty else {
            return nil
        }
        return url
    }

    private static func accept(_ url: URL, kind: RemoteResourceKind) -> URL? {
        guard let host = url.host else { return nil }
        if containsHeaderInjection(url.absoluteString) { return nil }
        switch kind {
        case .remoteAsset:
            if url.user != nil || url.password != nil { return nil }
            if isRestrictedHost(host) { return nil }
            return url
        case .mediaStream:
            return url
        }
    }

    /// Dotted, abbreviated (`127.1`), or dword (`2130706433`) IPv4.
    private static func parseIPv4(_ host: String) -> UInt32? {
        if host.unicodeScalars.allSatisfy({ $0 >= "0" && $0 <= "9" }), let dword = UInt32(host) {
            return dword
        }
        let parts = host.split(separator: ".", omittingEmptySubsequences: false)
        guard (1...4).contains(parts.count) else { return nil }
        var nums: [UInt32] = []
        nums.reserveCapacity(parts.count)
        for part in parts {
            guard let n = UInt32(part), String(n) == part || part == "0" else { return nil }
            nums.append(n)
        }
        switch nums.count {
        case 1:
            return nums[0]
        case 2:
            guard nums[0] <= 255, nums[1] <= 0x00FF_FFFF else { return nil }
            return (nums[0] << 24) | nums[1]
        case 3:
            guard nums[0] <= 255, nums[1] <= 255, nums[2] <= 0xFFFF else { return nil }
            return (nums[0] << 24) | (nums[1] << 16) | nums[2]
        case 4:
            guard nums.allSatisfy({ $0 <= 255 }) else { return nil }
            return (nums[0] << 24) | (nums[1] << 16) | (nums[2] << 8) | nums[3]
        default:
            return nil
        }
    }

    private static func isRestrictedIPv4(_ ip: UInt32) -> Bool {
        let a = ip >> 24
        let top16 = ip >> 16
        if a == 0 || a == 10 || a == 127 { return true }
        if top16 == 0xA9FE { return true } // 169.254/16
        if top16 == 0xC0A8 { return true } // 192.168/16
        if ip >> 20 == 0xAC1 { return true } // 172.16/12
        if ip >> 22 == 0x191 { return true } // 100.64/10 CGNAT
        if a >= 224 { return true }
        return false
    }

    private static func isRestrictedIPv6Address(_ addr: in6_addr) -> Bool {
        var a = addr
        // 16 bytes array
        return withUnsafeBytes(of: &a) { raw -> Bool in
            let bytes = raw.bindMemory(to: UInt8.self)
            guard bytes.count == 16 else { return true }

            // Loopback ::1: 15 zeros followed by 1
            let isLoopback = (0..<15).allSatisfy { bytes[$0] == 0 } && bytes[15] == 1
            // Unspecified :: : all 16 zeros
            let isUnspecified = (0..<16).allSatisfy { bytes[$0] == 0 }
            if isLoopback || isUnspecified { return true }

            // IPv4-mapped IPv6 address (::ffff:w.x.y.z): first 10 bytes 0, bytes 10-11 are 0xff
            let isIPv4Mapped = (0..<10).allSatisfy { bytes[$0] == 0 } && bytes[10] == 0xFF && bytes[11] == 0xFF
            // IPv4-compatible (deprecated): first 12 bytes 0, followed by non-loopback IPv4
            let isIPv4Compatible = (0..<12).allSatisfy { bytes[$0] == 0 } && (bytes[12] != 0 || bytes[13] != 0 || bytes[14] != 0 || bytes[15] > 1)

            if isIPv4Mapped || isIPv4Compatible {
                let ip4 = (UInt32(bytes[12]) << 24) | (UInt32(bytes[13]) << 16) | (UInt32(bytes[14]) << 8) | UInt32(bytes[15])
                return isRestrictedIPv4(ip4)
            }

            // Unique Local Address (fc00::/7): first byte has high 7 bits as 1111110 (0xFC or 0xFD)
            let b0 = bytes[0]
            if (b0 & 0xFE) == 0xFC { return true }

            // Link-Local (fe80::/10): first byte 0xFE, second byte high 2 bits are 10 (0x80..0xBF)
            if b0 == 0xFE && (bytes[1] & 0xC0) == 0x80 { return true }

            return false
        }
    }

    private static func isRestrictedIPv6(_ host: String) -> Bool {
        var addr6 = in6_addr()
        if inet_pton(AF_INET6, host, &addr6) == 1 {
            return isRestrictedIPv6Address(addr6)
        }
        if host == "::1" || host == "::" || host == "0:0:0:0:0:0:0:1" {
            return true
        }
        if let mapped = ipv4Mapped(from: host) {
            return isRestrictedIPv4(mapped)
        }
        let head = host.split(separator: ":", omittingEmptySubsequences: false)
            .first.map(String.init)?.lowercased() ?? ""
        if head.hasPrefix("fc") || head.hasPrefix("fd") { return true }
        if head.hasPrefix("fe8") || head.hasPrefix("fe9") || head.hasPrefix("fea") || head.hasPrefix("feb") {
            return true
        }
        return false
    }

    private static func ipv4Mapped(from host: String) -> UInt32? {
        guard let range = host.range(of: ":ffff:", options: .caseInsensitive) else { return nil }
        return parseIPv4(String(host[range.upperBound...]))
    }

    private static func resolvesOnlyToPublicAddressesSync(host: String) -> Bool {
        var hints = addrinfo()
        hints.ai_socktype = SOCK_STREAM
        hints.ai_family = AF_UNSPEC
        var result: UnsafeMutablePointer<addrinfo>?
        let status = getaddrinfo(host, nil, &hints, &result)
        defer { if let result { freeaddrinfo(result) } }
        guard status == 0, let first = result else { return false }

        var pointer: UnsafeMutablePointer<addrinfo>? = first
        var sawAddress = false
        while let info = pointer {
            sawAddress = true
            if let addr = info.pointee.ai_addr, isRestrictedSockaddr(addr) {
                return false
            }
            pointer = info.pointee.ai_next
        }
        return sawAddress
    }

    private static func isRestrictedSockaddr(_ addr: UnsafePointer<sockaddr>) -> Bool {
        switch Int32(addr.pointee.sa_family) {
        case AF_INET:
            return addr.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { pointer in
                let ip = UInt32(bigEndian: pointer.pointee.sin_addr.s_addr)
                return isRestrictedIPv4(ip)
            }
        case AF_INET6:
            return addr.withMemoryRebound(to: sockaddr_in6.self, capacity: 1) { pointer in
                isRestrictedIPv6Address(pointer.pointee.sin6_addr)
            }
        default:
            return true
        }
    }
}
