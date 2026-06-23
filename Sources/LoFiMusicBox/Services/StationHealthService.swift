import Foundation

struct StationHealthService {
    var timeout: TimeInterval = AppConstants.StationHealthCheck.requestTimeoutSeconds

    func check(_ station: Station) async -> StationHealth {
        let startedAt = Date()

        do {
            let result: ProbeResult
            switch station.type {
            case .m3u8:
                result = try await checkHLS(station.url)
            case .mp3:
                result = try await checkStream(station.url)
            case .bilibili:
                result = try await checkBilibili(station.url)
            }

            return StationHealth(
                status: result.status,
                checkedAt: Date(),
                responseTimeMilliseconds: Int(Date().timeIntervalSince(startedAt) * 1000),
                statusCode: result.statusCode,
                contentType: result.contentType,
                message: result.message
            )
        } catch {
            return StationHealth(
                status: .unavailable,
                checkedAt: Date(),
                responseTimeMilliseconds: Int(Date().timeIntervalSince(startedAt) * 1000),
                statusCode: nil,
                contentType: nil,
                message: error.localizedDescription
            )
        }
    }

    private func checkStream(_ url: URL) async throws -> ProbeResult {
        do {
            let head = try await request(url, method: AppConstants.StationHealthCheck.httpHeadMethod)
            if head.isSuccessful {
                return ProbeResult(
                    status: head.isAudioLike ? .available : .unstable,
                    statusCode: head.statusCode,
                    contentType: head.contentType,
                    message: head.isAudioLike
                        ? LocalizedStrings.text("station.health.message.audio_ok")
                        : LocalizedStrings.text("station.health.message.content_not_audio")
                )
            }
        } catch {
            // 很多电台服务不支持 HEAD，请求失败时改用小范围 GET 探测。
        }

        let range = try await request(
            url,
            method: AppConstants.StationHealthCheck.httpGetMethod,
            headers: [
                AppConstants.StationHealthCheck.rangedProbeHeaderName:
                    AppConstants.StationHealthCheck.rangedProbeHeaderValue
            ]
        )
        return ProbeResult(
            status: range.isSuccessful ? .available : .unavailable,
            statusCode: range.statusCode,
            contentType: range.contentType,
            message: range.isSuccessful
                ? LocalizedStrings.text("station.health.message.range_ok")
                : LocalizedStrings.text("station.health.message.range_http", range.statusCode)
        )
    }

    private func checkHLS(_ url: URL) async throws -> ProbeResult {
        let response = try await request(url, method: AppConstants.StationHealthCheck.httpGetMethod)
        guard response.isSuccessful else {
            return ProbeResult(
                status: .unavailable,
                statusCode: response.statusCode,
                contentType: response.contentType,
                message: LocalizedStrings.text("station.health.message.hls_http", response.statusCode)
            )
        }

        let manifest = String(decoding: response.data, as: UTF8.self)
        let isManifest = manifest.contains(AppConstants.StationHealthCheck.hlsManifestMarker)
        return ProbeResult(
            status: isManifest ? .available : .unstable,
            statusCode: response.statusCode,
            contentType: response.contentType,
            message: isManifest
                ? LocalizedStrings.text("station.health.message.hls_ok")
                : LocalizedStrings.text("station.health.message.hls_invalid")
        )
    }

    /// 哔哩哔哩直播的"真实可播"检测：不再只看页面是否 200（那会造成"检测正常却没声音"的假阳性），
    /// 而是走与播放完全相同的解析链路——能解析出 HLS 直链才算可用；
    /// 主播未开播则明确标为不可用，其它解析失败也按不可用处理。
    private func checkBilibili(_ url: URL) async throws -> ProbeResult {
        let resolver = BilibiliStreamResolver()
        do {
            _ = try await resolver.resolve(roomEntry: url)
            return ProbeResult(
                status: .available,
                statusCode: 200,
                contentType: "application/vnd.apple.mpegurl",
                message: LocalizedStrings.text("station.health.message.live_hls_ok")
            )
        } catch BilibiliStreamResolver.ResolveError.roomNotLive {
            return ProbeResult(
                status: .unavailable,
                statusCode: nil,
                contentType: nil,
                message: LocalizedStrings.text("station.health.message.live_not_live")
            )
        } catch {
            return ProbeResult(
                status: .unavailable,
                statusCode: nil,
                contentType: nil,
                message: LocalizedStrings.text("station.health.message.live_resolve_failed", error.localizedDescription)
            )
        }
    }

    private func request(
        _ url: URL,
        method: String,
        headers: [String: String] = [:]
    ) async throws -> HTTPProbeResponse {
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.httpMethod = method
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.setValue(
            AppConstants.Identity.userAgent,
            forHTTPHeaderField: AppConstants.StationHealthCheck.userAgentHeaderName
        )
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }

        return HTTPProbeResponse(data: data, response: httpResponse)
    }
}

private struct ProbeResult {
    var status: StationHealthStatus
    var statusCode: Int?
    var contentType: String?
    var message: String?
}

private struct HTTPProbeResponse {
    var data: Data
    var response: HTTPURLResponse

    var statusCode: Int {
        response.statusCode
    }

    var contentType: String? {
        response.value(forHTTPHeaderField: "Content-Type")
    }

    var isSuccessful: Bool {
        AppConstants.StationHealthCheck.successfulStatusCodeRange.contains(statusCode)
    }

    var isAudioLike: Bool {
        guard let contentType = contentType?.lowercased() else { return false }
        return contentType.contains("audio")
            || contentType.contains("mpegurl")
            || contentType.contains("octet-stream")
    }
}
