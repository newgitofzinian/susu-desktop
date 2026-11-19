import Foundation

final class MockProvider: URLProtocol {
    static var requests: [[String:Any]] = []
    static var code=200
    static var oversized=false
    static var stream=false
    static var streamBody: String?
    override class func canInit(with request:URLRequest)->Bool {true}
    override class func canonicalRequest(for request:URLRequest)->URLRequest {request}
    override func startLoading() {
        var body=request.httpBody ?? Data()
        if body.isEmpty,let stream=request.httpBodyStream {
            stream.open();defer{stream.close()}
            var chunk=[UInt8](repeating:0,count:4096)
            while true {let n=stream.read(&chunk,maxLength:chunk.count);if n<=0{break};body.append(contentsOf:chunk.prefix(n))}
        }
        let payload=(try! JSONSerialization.jsonObject(with:body)) as! [String:Any]
        Self.requests.append(payload)
        let response=HTTPURLResponse(url:request.url!,statusCode:Self.code,httpVersion:nil,headerFields:["Content-Type":Self.stream ? "text/event-stream" : "application/json"])!
        client?.urlProtocol(self,didReceive:response,cacheStoragePolicy:.notAllowed)
        if Self.oversized {client?.urlProtocol(self,didLoad:Data(repeating:65,count:1_000_001));client?.urlProtocolDidFinishLoading(self);return}
        if Self.stream {
            let body = Self.streamBody ?? "data: {\"choices\":[{\"delta\":{\"content\":\"我记\"}}]}\r\n\r\ndata: {\"choices\":[{\"delta\":{\"content\":\"得啦。\"}}]}\n\ndata: [DONE]\n\n"
            let bytes = Array(body.utf8)
            for index in stride(from: 0, to: bytes.count, by: 7) {
                client?.urlProtocol(self, didLoad: Data(bytes[index..<min(bytes.count, index + 7)]))
            }
        } else { client?.urlProtocol(self,didLoad:Data("{\"choices\":[{\"message\":{\"content\":\"我记得啦。\"}}]}".utf8)) }
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
let config=URLSessionConfiguration.ephemeral;config.protocolClasses=[MockProvider.self]
let client=ChatClient(configuration:config,credential:{_ in nil})
precondition(ChatClient.normalizedEndpoint("https://model.example")=="https://model.example/v1/chat/completions")
precondition(ChatClient.normalizedEndpoint("https://model.example/v1")=="https://model.example/v1/chat/completions")
precondition(ChatClient.normalizedEndpoint("model.example")=="https://model.example/v1/chat/completions")
precondition(ChatClient.normalizedEndpoint("https://model.example/custom/chat")=="https://model.example/custom/chat")
precondition(LocalChat.reply(to:"你好").content.contains("溯溯"))
precondition(LocalChat.reply(to:"你好").source == .local)
precondition(LocalChat.reply(to:"今天天气怎么样？").content.contains("实时天气"))
var state=ChatState();state.endpoint="https://model.example/v1/chat/completions";state.model="test-model";state.memories=["我喜欢湖绿色围巾"]
func request(_ text:String)->ChatMessage {
    var result:Result<ChatMessage,Error>?
    _=client.send(state:state,text:text){result=$0}
    let deadline=Date().addingTimeInterval(3)
    while result==nil && Date()<deadline {RunLoop.current.run(until:Date().addingTimeInterval(0.01))}
    return try! result!.get()
}
let reply1=request("你好")
state.history=[ChatMessage(role:"user",content:"你好"),reply1]
let reply2=request("你还记得什么？")
precondition(reply2.content=="我记得啦。")
let second=MockProvider.requests[1]["messages"] as! [[String:String]]
precondition(second.count==4 && second.filter{$0["content"]=="你还记得什么？"}.count==1)
precondition(second[0]["content"]!.contains("湖绿色围巾"))
MockProvider.stream=true
var streamed: [String] = []
var streamedResult:Result<ChatMessage,Error>?
_ = client.send(state:state,text:"流式",onDelta:{streamed.append($0)}){streamedResult=$0}
let streamDeadline=Date().addingTimeInterval(3)
while streamedResult==nil && Date()<streamDeadline {RunLoop.current.run(until:Date().addingTimeInterval(0.01))}
precondition(try! streamedResult!.get().content=="我记得啦。" && streamed==["我记", "我记得啦。"])
precondition(MockProvider.requests[2]["stream"] as? Bool == true)
MockProvider.stream=false
state.memories=[];state.history=[];_ = request("新的开始")
let afterDelete=MockProvider.requests[3]["messages"] as! [[String:String]]
precondition(!afterDelete[0]["content"]!.contains("湖绿色围巾"))
for bad in ["http://public.example/v1/chat/completions","https://name:secret@example.test/chat","file:///tmp/model"] {
    do {_ = try ChatClient.validate(endpoint:bad,model:"m");fatalError("Unsafe endpoint accepted")}catch{}
}
_ = try ChatClient.validate(endpoint:"http://127.0.0.1:1234/v1/chat/completions",model:"local")
do {_ = try ChatClient.parse(Data("{}".utf8));fatalError("Invalid provider response accepted")}catch{}
print("PASS: mock provider two-turn context; no duplicate user message; selected memory included and deleted on new conversation; endpoint and response validation.")

func expectFailure(_ predicate: (Error) -> Bool) {
    var result:Result<ChatMessage,Error>?
    _ = client.send(state:state,text:"测试错误"){result=$0}
    let deadline=Date().addingTimeInterval(3)
    while result==nil && Date()<deadline {RunLoop.current.run(until:Date().addingTimeInterval(0.01))}
    guard case .failure(let error)? = result, predicate(error) else { fatalError("Unexpected provider result: \(String(describing: result))") }
}
MockProvider.code = 401
expectFailure { if case ChatError.http(401) = $0 { return true }; return false }
MockProvider.code = 200; MockProvider.oversized = true
expectFailure { if case ChatError.tooLarge = $0 { return true }; return false }
MockProvider.oversized = false; MockProvider.stream = true
MockProvider.streamBody = "data: {\"choices\":[{\"delta\":{\"content\":\"只有一半\"}}]}\n\n"
expectFailure { if case ChatError.interrupted = $0 { return true }; return false }
MockProvider.streamBody = "event: error\r\ndata: {\"error\":{\"message\":\"test\"}}\r\n\r\n"
expectFailure { if case ChatError.response = $0 { return true }; return false }
MockProvider.streamBody = "data: {\"choices\":[{\"delta\":{\"content\":\"完成\"},\"finish_reason\":\"stop\"}]}\n\n"
precondition(request("服务器也可以用 finish_reason 结束").content == "完成")
print("PASS: fragmented UTF-8 and CRLF SSE, terminal messages, truncated streams, provider errors and response limits.")

state.memories = ["private memory"]
state.history = [ChatMessage(role: "user", content: "private history")]
let taskRequest = try ChatClient.request(state: state, text: "明天交报告", key: nil, systemPrompt: "只回复任务 JSON")
let taskPayload = try JSONSerialization.jsonObject(with: taskRequest.httpBody!) as! [String: Any]
let taskMessages = taskPayload["messages"] as! [[String: String]]
precondition(taskMessages == [["role": "system", "content": "只回复任务 JSON"], ["role": "user", "content": "明天交报告"]])
print("PASS: task interpretation requests exclude chat history and memories.")
