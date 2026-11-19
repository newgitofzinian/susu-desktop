import Foundation
import Security

struct ChatMessage: Codable, Identifiable {
    enum Source: String, Codable { case local, model }
    var id = UUID()
    let role: String
    let content: String
    let source: Source?
    init(id: UUID = UUID(), role: String, content: String, source: Source? = nil) {
        self.id=id; self.role=role; self.content=content; self.source=source
    }
}
struct ChatState: Codable {
    var endpoint = ""
    var model = ""
    var memories: [String] = []
    var history: [ChatMessage] = []
    var prefersLocal: Bool? = nil
}
enum LocalChat {
    static func reply(to text: String) -> ChatMessage {
        let normalized = text.lowercased()
        let words = normalized.split { !$0.isLetter }
        func mentions(_ phrases: [String]) -> Bool {
            phrases.contains { normalized.contains($0) }
        }

        let content: String
        if mentions(["好累", "很累", "有点累", "太累", "难过", "压力", "烦", "疲惫"]) {
            content = "辛苦啦。我在这儿陪你。要不要先放下手里的事，喝口水、歇一小会儿？"
        } else if mentions(["休息", "睡觉", "晚安", "下班"]) {
            content = "好呀。给自己留一点安静的时间吧，我在桌边陪着你。"
        } else if mentions(["喝水", "口渴"]) {
            content = "先喝几口水吧。想让我定时提醒，可以在「工作与提醒」里打开喝水提醒。"
        } else if mentions(["天气"]) {
            content = "要出门了吗？我这里看不到实时天气。出门前可以看一眼窗外，再决定带不带伞。"
        } else if mentions(["记得", "记住", "记忆"]) {
            content = "想留一句话给以后的溯溯的话，可以点「记忆」，选中这条消息再保存。"
        } else if mentions(["谢谢", "感谢"]) {
            content = "不客气呀，我很高兴能陪到你。"
        } else if mentions(["玩耍", "陪我玩", "散步", "伸懒腰"]) {
            content = "走呀！你可以在桌面上右键点我，从「玩耍与行动」里选个动作。"
        } else if mentions(["你好", "嗨", "哈喽", "早安", "早上好"]) || words.contains("hello") || words.contains("hi") {
            content = "你好呀！我是溯溯，今天也会陪着你。"
        } else {
            content = "我在桌边听着呢。你可以跟我打个招呼，或者告诉我想休息一会儿。"
        }
        return ChatMessage(role: "assistant", content: content, source: .local)
    }
}
enum ChatError: LocalizedError {
    case configuration(String), http(Int), response, interrupted, timeout, tooLarge, keychain(Int32)
    var errorDescription: String? {
        switch self {
        case .configuration(let message):return message
        case .http(let code):return "模型服务返回 HTTP \(code)。请检查地址、模型名称和凭据；重定向地址请填写最终接口。"
        case .response:return "服务响应中没有可读取的回复文本。"
        case .interrupted:return "连接在回复结束前中断。本次回复未保存，可以再试一次。"
        case .timeout:return "等待模型服务超时。可以重试或切换模型。"
        case .tooLarge:return "回复超过大小限制，请缩短问题或更换模型设置。"
        case .keychain(let code):return "无法访问钥匙串（\(code)），请检查系统授权。"
        }
    }
}
final class ChatKeychain {
    private let service = "local.zinian.susu.chat"
    private func query(_ origin: String) -> [String:Any] {
        [kSecClass as String:kSecClassGenericPassword,kSecAttrService as String:service,kSecAttrAccount as String:origin]
    }
    func set(_ key: String, origin: String) throws {
        let base = query(origin)
        if key.isEmpty {
            let result=SecItemDelete(base as CFDictionary)
            guard result==errSecSuccess || result==errSecItemNotFound else{throw ChatError.keychain(result)}
            return
        }
        let attributes=[kSecValueData as String:Data(key.utf8)]
        let updated=SecItemUpdate(base as CFDictionary,attributes as CFDictionary)
        if updated==errSecSuccess{return}
        guard updated==errSecItemNotFound else{throw ChatError.keychain(updated)}
        var item=base;item[kSecValueData as String]=Data(key.utf8)
        item[kSecAttrAccessible as String]=kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let result=SecItemAdd(item as CFDictionary,nil)
        guard result==errSecSuccess else{throw ChatError.keychain(result)}
    }
    func get(origin: String) throws -> String? {
        var request=query(origin);request[kSecReturnData as String]=true;request[kSecMatchLimit as String]=kSecMatchLimitOne
        var result:CFTypeRef?
        let code=SecItemCopyMatching(request as CFDictionary,&result)
        if code==errSecItemNotFound{return nil}
        guard code==errSecSuccess,let data=result as? Data else{throw ChatError.keychain(code)}
        return String(data:data,encoding:.utf8)
    }
}
final class ChatClient {
    static let contextHistoryLimit = 30
    static let idleTimeout: TimeInterval = 120
    static let totalTimeout: TimeInterval = 600
    static let maxResponseBytes = 1_000_000
    static let maxReplyCharacters = 30_000
    let keychain = ChatKeychain()
    private let configuration: URLSessionConfiguration
    private let credential: ((String)throws->String?)?
    init(configuration: URLSessionConfiguration = .ephemeral, credential: ((String)throws->String?)? = nil) {
        self.configuration=configuration;self.credential=credential
    }
    static func validate(endpoint: String, model: String) throws -> URL {
        guard let url=URL(string:endpoint.trimmingCharacters(in:.whitespacesAndNewlines)),
              let host=url.host,!host.isEmpty,url.user==nil,url.password==nil,url.fragment==nil,
              url.scheme=="https" || (url.scheme=="http" && ["localhost","127.0.0.1","[::1]","::1"].contains(host)) else {
            throw ChatError.configuration("请填写完整 HTTPS 聊天接口。运行在本机的服务也支持回环 HTTP 地址。")
        }
        guard !model.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty else{throw ChatError.configuration("请填写模型名称。")}
        return url
    }
    static func normalizedEndpoint(_ input: String) -> String {
        let raw = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return raw }
        let withScheme = raw.contains("://") ? raw : "https://" + raw
        guard var components = URLComponents(string: withScheme), components.host != nil else { return raw }
        switch components.percentEncodedPath {
        case "", "/": components.path = "/v1/chat/completions"
        case "/v1", "/v1/": components.path = "/v1/chat/completions"
        default: break
        }
        return components.url?.absoluteString ?? raw
    }
    static func origin(_ url: URL) -> String {
        "\(url.scheme!)://\(url.host!.lowercased()):\(url.port ?? (url.scheme=="https" ? 443 : 80))"
    }
    static func request(state: ChatState, text: String, key: String?, systemPrompt: String? = nil) throws -> URLRequest {
        let url=try validate(endpoint:state.endpoint,model:state.model)
        var request=URLRequest(url:url,timeoutInterval:idleTimeout)
        request.httpMethod="POST"
        request.setValue("application/json",forHTTPHeaderField:"Content-Type")
        request.setValue("text/event-stream, application/json", forHTTPHeaderField: "Accept")
        if let key,!key.isEmpty{request.setValue("Bearer "+key,forHTTPHeaderField:"Authorization")}
        var system = systemPrompt ?? "你是桌面狐狸溯溯，使用简洁自然的中文陪伴主人。"
        if systemPrompt == nil && !state.memories.isEmpty {
            system += "\n以下是主人明确选择保留的记忆，作为事实参考：\n"+state.memories.joined(separator:"\n")
        }
        let history=(systemPrompt == nil ? state.history.suffix(contextHistoryLimit) : []).map{["role":$0.role,"content":$0.content]}
        let messages=[["role":"system","content":system]]+history+[["role":"user","content":text]]
        request.httpBody=try JSONSerialization.data(withJSONObject:["model":state.model,"messages":messages,"stream":true])
        return request
    }
    static func parse(_ data: Data) throws -> ChatMessage {
        guard data.count<=maxResponseBytes else{throw ChatError.tooLarge}
        let object=try JSONSerialization.jsonObject(with:data) as? [String:Any]
        let message=((object?["choices"] as? [[String:Any]])?.first?["message"] as? [String:Any])
        guard let content=message?["content"] as? String,!content.isEmpty else{throw ChatError.response}
        guard content.count <= maxReplyCharacters else { throw ChatError.tooLarge }
        return ChatMessage(role:"assistant",content:content)
    }
    func send(state: ChatState, text: String, systemPrompt: String? = nil, onDelta: ((String)->Void)? = nil, completion: @escaping(Result<ChatMessage,Error>)->Void) -> URLSessionDataTask? {
        do {
            let url=try Self.validate(endpoint:state.endpoint,model:state.model)
            let key:String?
            if let credential {key=try credential(Self.origin(url))} else {key=try keychain.get(origin:Self.origin(url))}
            let request=try Self.request(state:state,text:text,key:key,systemPrompt:systemPrompt)
            let config=configuration.copy() as! URLSessionConfiguration
            config.timeoutIntervalForRequest=Self.idleTimeout; config.timeoutIntervalForResource=Self.totalTimeout
            config.urlCache=nil;config.httpCookieStorage=nil;config.urlCredentialStorage=nil;config.httpShouldSetCookies=false
            let transport=ChatTransport(onDelta:onDelta, completion:completion)
            let queue=OperationQueue();queue.maxConcurrentOperationCount=1
            let session=URLSession(configuration:config,delegate:transport,delegateQueue:queue)
            transport.session=session
            let task=session.dataTask(with:request);task.resume();return task
        } catch {
            DispatchQueue.main.async{completion(.failure(error))};return nil
        }
    }
}
private final class ChatTransport: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    var session: URLSession?
    private let completion:(Result<ChatMessage,Error>)->Void
    private let onDelta:((String)->Void)?
    private var received=Data()
    private var lineBytes = Data()
    private var eventLines: [String] = []
    private var previousWasCR = false
    private var streamedText=""
    private var isStreaming=false
    private var networkBytes=0
    private var finished=false
    init(onDelta:((String)->Void)?, completion:@escaping(Result<ChatMessage,Error>)->Void){self.onDelta=onDelta;self.completion=completion}
    private func finish(_ result:Result<ChatMessage,Error>) {
        guard !finished else{return};finished=true
        session?.invalidateAndCancel();session=nil
        DispatchQueue.main.async{self.completion(result)}
    }
    func urlSession(_ session:URLSession,task:URLSessionTask,willPerformHTTPRedirection response:HTTPURLResponse,newRequest request:URLRequest,completionHandler:@escaping(URLRequest?)->Void) {completionHandler(nil)}
    func urlSession(_ session:URLSession,dataTask:URLSessionDataTask,didReceive response:URLResponse,completionHandler:@escaping(URLSession.ResponseDisposition)->Void) {
        guard let response=response as? HTTPURLResponse else{finish(.failure(ChatError.response));completionHandler(.cancel);return}
        guard (200..<300).contains(response.statusCode) else{finish(.failure(ChatError.http(response.statusCode)));completionHandler(.cancel);return}
        guard response.expectedContentLength <= Int64(ChatClient.maxResponseBytes) else {
            finish(.failure(ChatError.tooLarge)); completionHandler(.cancel); return
        }
        isStreaming=response.value(forHTTPHeaderField:"Content-Type")?.lowercased().contains("text/event-stream") == true
        completionHandler(.allow)
    }
    func urlSession(_ session:URLSession,dataTask:URLSessionDataTask,didReceive data:Data) {
        guard !finished else{return}
        networkBytes += data.count
        guard networkBytes <= ChatClient.maxResponseBytes else { finish(.failure(ChatError.tooLarge)); return }
        if isStreaming { consumeLines(data) }
        else { received.append(data) }
    }
    func urlSession(_ session:URLSession,task:URLSessionTask,didCompleteWithError error:Error?) {
        guard !finished else{return}
        if let error {
            let code = (error as? URLError)?.code
            if code == .timedOut { finish(.failure(ChatError.timeout)) }
            else if code != .cancelled && isStreaming && !streamedText.isEmpty { finish(.failure(ChatError.interrupted)) }
            else { finish(.failure(error)) }
            return
        }
        if isStreaming {
            // Some compatible endpoints close after a terminal line without a blank delimiter.
            if !lineBytes.isEmpty { consumeLine() }
            if !finished { consumeEvent() }
            if !finished { finish(.failure(ChatError.interrupted)) }
            return
        }
        do{finish(.success(try ChatClient.parse(received)))}catch{finish(.failure(error))}
    }

    private func consumeLines(_ data: Data) {
        for byte in data {
            guard !finished else { return }
            if byte == 10 && previousWasCR {
                previousWasCR = false
                continue
            }
            previousWasCR = byte == 13
            if byte == 10 || byte == 13 { consumeLine() }
            else { lineBytes.append(byte) }
        }
    }

    private func consumeLine() {
        if lineBytes.isEmpty { consumeEvent(); return }
        let line = String(decoding: lineBytes, as: UTF8.self)
        lineBytes.removeAll(keepingCapacity: true)
        guard line.hasPrefix("data:") else { return }
        let value = line.dropFirst(5)
        eventLines.append(String(value.first == " " ? value.dropFirst() : value))
    }

    private func consumeEvent() {
        guard !eventLines.isEmpty else { return }
        let payload = eventLines.joined(separator: "\n")
        eventLines.removeAll(keepingCapacity: true)
        if payload == "[DONE]" { finishReply(); return }
        guard let object = try? JSONSerialization.jsonObject(with: Data(payload.utf8)) as? [String: Any] else {
            finish(.failure(ChatError.response)); return
        }
        if object["error"] != nil { finish(.failure(ChatError.response)); return }
        guard let choice = (object["choices"] as? [[String: Any]])?.first else { return }
        if let delta = choice["delta"] as? [String: Any], let content = delta["content"] as? String, !content.isEmpty {
            streamedText.append(content)
            guard streamedText.count <= ChatClient.maxReplyCharacters else { finish(.failure(ChatError.tooLarge)); return }
            if let onDelta {
                let snapshot = streamedText
                DispatchQueue.main.async { onDelta(snapshot) }
            }
        }
        if let reason = choice["finish_reason"] as? String, !reason.isEmpty { finishReply() }
    }

    private func finishReply() {
        guard !streamedText.isEmpty else { finish(.failure(ChatError.response)); return }
        finish(.success(ChatMessage(role: "assistant", content: streamedText)))
    }
}
