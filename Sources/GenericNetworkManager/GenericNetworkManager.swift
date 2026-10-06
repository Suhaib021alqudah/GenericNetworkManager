import Foundation

public enum HTTPMethod: String {
    case get = "GET"
    case post = "POST"
    case put = "PUT"
    case patch = "PATCH"
    case delete = "DELETE"
}

public struct Endpoint {
    public let url: URL
    public let method: HTTPMethod
    public let headers: [String: String]

    public init(url: URL, method: HTTPMethod, headers: [String: String] = [:]) {
        self.url = url
        self.method = method
        self.headers = headers
    }

    public var request: URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method.rawValue
        headers.forEach { key, value in
            request.setValue(value, forHTTPHeaderField: key)
        }
        return request
    }
}

public enum NetworkError: LocalizedError {
    case invalidURL
    case invalidResponse
    case badRequest
    case unauthorized
    case forbidden
    case notFound
    case validationFailed
    case serverError
    case badStatusCode(Int)
    case decodingFailed(Error)
    case noInternet
    case timeout
    case cancelled
    case unknown(Error)
    case serverMessage(String)

    public var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "The URL is invalid."
        case .invalidResponse:
            return "Invalid server response."
        case .badRequest:
            return "The request is invalid."
        case .unauthorized:
            return "Your session has expired. Please log in again."
        case .forbidden:
            return "You do not have permission to perform this action."
        case .notFound:
            return "The requested resource was not found."
        case .validationFailed:
            return "Some of the provided information is invalid."
        case .serverError:
            return "The server is currently unavailable. Please try again later."
        case .badStatusCode(let code):
            return "Server returned status code \(code)."
        case .decodingFailed:
            return "Failed to process the server response."
        case .noInternet:
            return "No internet connection."
        case .timeout:
            return "The request timed out."
        case .cancelled:
            return "The request was cancelled."
        case .unknown:
            return "An unknown error occurred."
        case .serverMessage(let message):
            return message
        }
    }
}

public protocol NetworkManagerProtocol {
    func request<T: Decodable>(
        request: URLRequest,
        responseType: T.Type,
        decoder: JSONDecoder
    ) async throws -> T
}

public struct APIErrorResponse: Decodable {
    public let message: String?
}

public final class NetworkManager: NetworkManagerProtocol, @unchecked Sendable {
    public static let shared = NetworkManager()
    private init() {}

    public func request<T: Decodable>(
        request: URLRequest,
        responseType: T.Type,
        decoder: JSONDecoder = JSONDecoder()
    ) async throws -> T {
        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw NetworkError.invalidResponse
            }
            let apiError = try? decoder.decode(APIErrorResponse.self, from: data)

            switch httpResponse.statusCode {
            case 200...299:
                break
            case 400:
                throw NetworkError.badRequest
            case 401:
                throw NetworkError.unauthorized
            case 403:
                throw NetworkError.forbidden
            case 404:
                throw NetworkError.notFound
            case 422:
                if let message = apiError?.message {
                    throw NetworkError.serverMessage(message)
                }
                throw NetworkError.validationFailed
            case 500...599:
                throw NetworkError.serverError
            default:
                throw NetworkError.badStatusCode(httpResponse.statusCode)
            }

            do {
                return try decoder.decode(responseType, from: data)
            } catch {
                throw NetworkError.decodingFailed(error)
            }
        } catch is CancellationError {
            throw NetworkError.cancelled
        } catch let urlError as URLError {
            switch urlError.code {
            case .notConnectedToInternet:
                throw NetworkError.noInternet
            case .timedOut:
                throw NetworkError.timeout
            case .cancelled:
                throw NetworkError.cancelled
            default:
                throw NetworkError.unknown(urlError)
            }
        } catch let networkError as NetworkError {
            throw networkError
        } catch {
            throw NetworkError.unknown(error)
        }
    }
}
