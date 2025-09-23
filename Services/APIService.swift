import Foundation

struct ChatMessage: Codable { let role: String; let content: String }
struct ChatRequest: Codable { let model: String; let messages: [ChatMessage]; let stream: Bool }

struct ChatChunkDelta: Decodable { let content: String?; let reasoning_content: String? }
struct ChatChunkChoice: Decodable { let delta: ChatChunkDelta }
struct ChatChunk: Decodable { let id: String; let choices: [ChatChunkChoice] }

actor DeepSeekChatService {
    enum StreamEvent { case token(String); case reasoning(String); case done; case error(Error) }

    private let tokenProvider: TokenProvider
    private let session: URLSession
    private let baseURL: URL

    init(tokenProvider: TokenProvider, baseURL: URL = URL(string: "https://api.deepseek.com/v1")!, session: URLSession = .shared) {
        self.tokenProvider = tokenProvider
        self.baseURL = baseURL
        self.session = session
    }

    func streamChat(userPrompt: String, systemPrompt: String? = nil, model: String = "deepseek-chat") -> AsyncStream<StreamEvent> {
        let tokenProvider = self.tokenProvider
        let session = self.session
        let url = baseURL.appendingPathComponent("chat/completions")
        return AsyncStream { continuation in
            Task {
                do {
                    let token = try await tokenProvider.getToken()
                    var messages: [ChatMessage] = []
                    if let systemPrompt { messages.append(ChatMessage(role: "system", content: systemPrompt)) }
                    messages.append(ChatMessage(role: "user", content: userPrompt))
                    let body = ChatRequest(model: model, messages: messages, stream: true)
                    var request = URLRequest(url: url)
                    request.httpMethod = "POST"
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                    request.httpBody = try JSONEncoder().encode(body)
                    let (bytes, response) = try await session.bytes(for: request)
                    guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
                        throw APIError.networkError((response as? HTTPURLResponse)?.statusCode ?? -1)
                    }
                    for try await line in bytes.lines {
                        if line.hasPrefix("data: ") {
                            let jsonPart = String(line.dropFirst(6)).trimmingCharacters(in: .whitespacesAndNewlines)
                            if jsonPart == "[DONE]" { continuation.yield(.done); break }
                            if let data = jsonPart.data(using: .utf8) {
                                do {
                                    let chunk = try JSONDecoder().decode(ChatChunk.self, from: data)
                                    if let delta = chunk.choices.first?.delta {
                                        if let reasoning = delta.reasoning_content, !reasoning.isEmpty { continuation.yield(.reasoning(reasoning)) }
                                        if let tokenText = delta.content, !tokenText.isEmpty { continuation.yield(.token(tokenText)) }
                                    }
                                } catch {
                                    // Ignore silently or surface as needed
                                }
                            }
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.yield(.error(error))
                    continuation.finish()
                }
            }
        }
    }
}
