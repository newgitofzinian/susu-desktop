import Foundation

final class MockProvider: URLProtocol {
    static var requests: [[String:Any]] = []
    static var code=200
    static var oversized=false
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
        let response=HTTPURLResponse(url:request.url!,statusCode:Self.code,httpVersion:nil,headerFields:["Content-Type":"application/json"])!
        client?.urlProtocol(self,didReceive:response,cacheStoragePolicy:.notAllowed)
        if Self.oversized {client?.urlProtocol(self,didLoad:Data(repeating:65,count:1_000_001));client?.urlProtocolDidFinishLoading(self);return}
        client?.urlProtocol(self,didLoad:Data("{\"choices\":[{\"message\":{\"content\":\"我记得啦。\"}}]}".utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
let config=URLSessionConfiguration.ephemeral;config.protocolClasses=[MockProvider.self]
let client=ChatClient(configuration:config,credential:{_ in nil})
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
state.memories=[];state.history=[];_ = request("新的开始")
let afterDelete=MockProvider.requests[2]["messages"] as! [[String:String]]
precondition(!afterDelete[0]["content"]!.contains("湖绿色围巾"))
for bad in ["http://public.example/v1/chat/completions","https://name:secret@example.test/chat","file:///tmp/model"] {
    do {_ = try ChatClient.validate(endpoint:bad,model:"m");fatalError("Unsafe endpoint accepted")}catch{}
}
_ = try ChatClient.validate(endpoint:"http://127.0.0.1:1234/v1/chat/completions",model:"local")
do {_ = try ChatClient.parse(Data("{}".utf8));fatalError("Invalid provider response accepted")}catch{}
print("PASS: mock provider two-turn context; no duplicate user message; selected memory included and deleted on new conversation; endpoint and response validation.")

func expectFailure() {
    var result:Result<ChatMessage,Error>?
    _ = client.send(state:state,text:"测试错误"){result=$0}
    let deadline=Date().addingTimeInterval(3)
    while result==nil && Date()<deadline {RunLoop.current.run(until:Date().addingTimeInterval(0.01))}
    guard case .failure?=result else{fatalError("Provider error was not surfaced")}
}
MockProvider.code=401;expectFailure()
MockProvider.code=200;MockProvider.oversized=true;expectFailure()
print("PASS: provider HTTP failure and oversized reply are surfaced safely.")
