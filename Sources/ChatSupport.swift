import Foundation
import Security

struct ChatMessage: Codable, Identifiable {
    var id = UUID()
    let role: String
    let content: String
}
struct ChatState: Codable {
    var endpoint = ""
    var model = ""
    var memories: [String] = []
    var history: [ChatMessage] = []
}
enum ChatError: LocalizedError {
    case configuration(String), http(Int), response, tooLarge, keychain(Int32)
    var errorDescription: String? {
        switch self {
        case .configuration(let message):return message
        case .http(let code):return "模型服务返回 HTTP \(code)。请检查地址、模型名称和凭据；重定向地址请填写最终接口。"
        case .response:return "服务响应中没有可读取的回复文本。"
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
    static func origin(_ url: URL) -> String {
        "\(url.scheme!)://\(url.host!.lowercased()):\(url.port ?? (url.scheme=="https" ? 443 : 80))"
    }
    static func request(state: ChatState, text: String, key: String?) throws -> URLRequest {
        let url=try validate(endpoint:state.endpoint,model:state.model)
        var request=URLRequest(url:url,timeoutInterval:45)
        request.httpMethod="POST"
        request.setValue("application/json",forHTTPHeaderField:"Content-Type")
        if let key,!key.isEmpty{request.setValue("Bearer "+key,forHTTPHeaderField:"Authorization")}
        var system="你是桌面狐狸溯溯，使用简洁自然的中文陪伴主人。"
        if !state.memories.isEmpty {
            system += "\n以下是主人明确选择保留的记忆，作为事实参考：\n"+state.memories.joined(separator:"\n")
        }
        let history=state.history.suffix(30).map{["role":$0.role,"content":$0.content]}
        let messages=[["role":"system","content":system]]+history+[["role":"user","content":text]]
        request.httpBody=try JSONSerialization.data(withJSONObject:["model":state.model,"messages":messages,"stream":false])
        return request
    }
    static func parse(_ data: Data) throws -> ChatMessage {
        guard data.count<=1_000_000 else{throw ChatError.tooLarge}
        let object=try JSONSerialization.jsonObject(with:data) as? [String:Any]
        let message=((object?["choices"] as? [[String:Any]])?.first?["message"] as? [String:Any])
        guard let content=message?["content"] as? String,!content.isEmpty,content.count<=30000 else{throw ChatError.response}
        return ChatMessage(role:"assistant",content:content)
    }
    func send(state: ChatState, text: String, completion: @escaping(Result<ChatMessage,Error>)->Void) -> URLSessionDataTask? {
        do {
            let url=try Self.validate(endpoint:state.endpoint,model:state.model)
            let key:String?
            if let credential {key=try credential(Self.origin(url))} else {key=try keychain.get(origin:Self.origin(url))}
            let request=try Self.request(state:state,text:text,key:key)
            let config=configuration.copy() as! URLSessionConfiguration
            config.urlCache=nil;config.httpCookieStorage=nil;config.urlCredentialStorage=nil;config.httpShouldSetCookies=false
            let transport=ChatTransport(completion:completion)
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
    private var received=Data()
    private var finished=false
    init(completion:@escaping(Result<ChatMessage,Error>)->Void){self.completion=completion}
    private func finish(_ result:Result<ChatMessage,Error>) {
        guard !finished else{return};finished=true
        session?.finishTasksAndInvalidate();session=nil
        DispatchQueue.main.async{self.completion(result)}
    }
    func urlSession(_ session:URLSession,task:URLSessionTask,willPerformHTTPRedirection response:HTTPURLResponse,newRequest request:URLRequest,completionHandler:@escaping(URLRequest?)->Void) {completionHandler(nil)}
    func urlSession(_ session:URLSession,dataTask:URLSessionDataTask,didReceive response:URLResponse,completionHandler:@escaping(URLSession.ResponseDisposition)->Void) {
        guard let response=response as? HTTPURLResponse else{finish(.failure(ChatError.response));completionHandler(.cancel);return}
        guard (200..<300).contains(response.statusCode) else{finish(.failure(ChatError.http(response.statusCode)));completionHandler(.cancel);return}
        guard response.expectedContentLength<=1_000_000 else{finish(.failure(ChatError.tooLarge));completionHandler(.cancel);return}
        completionHandler(.allow)
    }
    func urlSession(_ session:URLSession,dataTask:URLSessionDataTask,didReceive data:Data) {
        guard !finished else{return}
        guard received.count+data.count<=1_000_000 else{dataTask.cancel();finish(.failure(ChatError.tooLarge));return}
        received.append(data)
    }
    func urlSession(_ session:URLSession,task:URLSessionTask,didCompleteWithError error:Error?) {
        guard !finished else{return}
        if let error{finish(.failure(error));return}
        do{finish(.success(try ChatClient.parse(received)))}catch{finish(.failure(error))}
    }
}
