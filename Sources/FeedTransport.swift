import Foundation

// A single owner serializes feed requests, bounds decompressed data and cancels obsolete work.
final class FeedTransport:NSObject,URLSessionDataDelegate,@unchecked Sendable {
    typealias Completion = (Data?,URLResponse?,Error?)->Void
    private final class Job {
        let url:URL;let scope:String;let completion:Completion
        var data = Data();var response:URLResponse?;var failure:Error?;var task:URLSessionDataTask?
        init(_ url:URL,_ scope:String,_ completion:@escaping Completion){self.url = url;self.scope = scope;self.completion = completion}
    }
    private let queue = DispatchQueue(label:"ru.bushe.stroka.feeds",qos:.utility)
    private let configuration:URLSessionConfiguration
    private let limit:Int;private let concurrency:Int
    private var pending:[Job] = [];private var active:[Int:Job] = [:];private var closed = false
    private(set) var maximumActive = 0
    private lazy var network:URLSession = {
        let delegateQueue = OperationQueue();delegateQueue.maxConcurrentOperationCount = 1;delegateQueue.underlyingQueue = queue
        return URLSession(configuration:configuration,delegate:self,delegateQueue:delegateQueue)
    }()
    init(configuration:URLSessionConfiguration,limit:Int = 5_000_000,concurrency:Int = 4) {
        self.configuration = configuration.copy() as! URLSessionConfiguration;self.limit = limit;self.concurrency = max(1,concurrency)
        super.init()
    }
    func load(_ url:URL,scope:String,completion:@escaping Completion) {
        queue.async {
            guard !self.closed else {completion(nil,nil,URLError(.cancelled));return}
            self.pending.append(Job(url,scope,completion));self.drain()
        }
    }
    func cancel(scope:String) {
        queue.async {
            let removed = self.pending.filter{$0.scope == scope};self.pending.removeAll{$0.scope == scope}
            for job in removed {job.completion(nil,nil,URLError(.cancelled))}
            for job in self.active.values where job.scope == scope {job.task?.cancel()}
        }
    }
    func invalidate() {
        queue.async {
            self.closed = true;let pending = self.pending;self.pending = []
            for job in pending {job.completion(nil,nil,URLError(.cancelled))}
            self.network.invalidateAndCancel()
        }
    }
    private func drain() {
        while !closed && active.count<concurrency && !pending.isEmpty {
            let job = pending.removeFirst()
            guard job.url.scheme?.lowercased() == "https",job.url.host != nil else {job.completion(nil,nil,URLError(.unsupportedURL));continue}
            let task = network.dataTask(with:job.url);job.task = task;active[task.taskIdentifier] = job;maximumActive = max(maximumActive,active.count);task.resume()
        }
    }
    func urlSession(_ session:URLSession,dataTask:URLSessionDataTask,didReceive response:URLResponse,completionHandler:@escaping (URLSession.ResponseDisposition)->Void) {
        guard let job = active[dataTask.taskIdentifier] else {completionHandler(.cancel);return}
        job.response = response
        guard response.url?.scheme?.lowercased() == "https",response.expectedContentLength <= Int64(limit) else {job.failure = URLError(.dataLengthExceedsMaximum);completionHandler(.cancel);return}
        completionHandler(.allow)
    }
    func urlSession(_ session:URLSession,dataTask:URLSessionDataTask,didReceive data:Data) {
        guard let job = active[dataTask.taskIdentifier],job.failure == nil else {return}
        guard data.count <= limit-job.data.count else {job.failure = URLError(.dataLengthExceedsMaximum);job.data.removeAll();dataTask.cancel();return}
        job.data.append(data)
    }
    func urlSession(_ session:URLSession,task:URLSessionTask,willPerformHTTPRedirection response:HTTPURLResponse,newRequest request:URLRequest,completionHandler:@escaping (URLRequest?)->Void) {
        guard request.url?.scheme?.lowercased() == "https" else {active[task.taskIdentifier]?.failure = URLError(.secureConnectionFailed);completionHandler(nil);return}
        completionHandler(request)
    }
    func urlSession(_ session:URLSession,task:URLSessionTask,didCompleteWithError error:Error?) {
        guard let job = active.removeValue(forKey:task.taskIdentifier) else {return}
        let failure = job.failure ?? error
        drain();job.completion(failure == nil ? job.data : nil,job.response,failure)
    }
}

// Status is keyed by URL because the same publisher can appear in several collections.
enum FeedLoadState {
    case loading
    case failed(String)
    case loaded(Date)
}
