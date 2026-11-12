import Foundation

/// Schema 2 is a complete open report, with opaque file bytes and recovery copies.
/// The inner report stays schema 1 so local storage and older handoffs remain readable.
public enum ProjectArchive {
    public static let metadataLimit=8*1024*1024
    public struct Resource:Codable,Equatable,Identifiable {
        public var id:String;public var name:String;public var kind:String;public var sha256:String;public var size:UInt64
        public init(name:String,kind:String,sha256:String,size:UInt64,id:String=UUID().uuidString) {self.id=id;self.name=name;self.kind=kind;self.sha256=sha256;self.size=size}
    }
    public struct State:Codable,Equatable {
        public var schema=1
        public var resources:[Resource]=[]
        /// A property-list snapshot retained as data. Only reviewed portable preferences may be applied.
        public var preferences:Data?
        public var preferenceSnapshots:[Data]=[]
        public init() {}
    }
    public struct Snapshot:Equatable {
        public var current:Data;public var previous:Data?;public var state:State
        public init(current:Data,previous:Data?=nil,state:State=State()) {self.current=current;self.previous=previous;self.state=state}
    }
    public struct Blob:Codable,Equatable {public var sha256:String;public var size:UInt64}
    public struct Manifest:Codable,Equatable {
        public var format="org.squidproductions.camreport"
        public var schema=2
        public var scope="complete-open-report"
        public var packageID=UUID().uuidString
        public var device:String
        public var current:String
        public var previous:String?
        public var state:State
        public var blobs:[Blob]
    }
    public struct Prepared:Identifiable {
        public let id=UUID()
        public var folder:URL;public var manifest:Manifest;public var snapshot:Snapshot;public var report:Report
        public var totalBytes:UInt64 {manifest.blobs.reduce(0){$0+$1.size}}
    }
    public static func validHash(_ hash:String)->Bool {hash.utf8.count==64 && hash.utf8.allSatisfy{(48...57).contains($0)||(97...102).contains($0)}}
    public static func blobURL(_ folder:URL,_ hash:String)throws->URL {
        guard validHash(hash) else {throw ReportError.invalid("Invalid project checksum.")};return folder.appendingPathComponent(hash,isDirectory:false)
    }
    public static func validate(_ state:State)throws {
        guard state.schema==1,state.resources.count<19_990,Set(state.resources.map(\.id)).count==state.resources.count else {throw ReportError.invalid("Unsupported project resources or duplicate file identities.")}
        for r in state.resources {
            guard UUID(uuidString:r.id) != nil,["media","attachment","recovery"].contains(r.kind),!r.name.isEmpty,r.name.utf8.count<=1024,!r.name.contains("\0"),validHash(r.sha256),r.size<=ProjectZIP.maximumBytes else {throw ReportError.invalid("Invalid project file metadata.")}
        }
        guard state.preferenceSnapshots.count<=1000 else {throw ReportError.invalid("Too many preference snapshots.")}
        for data in state.preferenceSnapshots + (state.preferences.map{[$0]} ?? []) {
            guard data.count<=metadataLimit,let prefs=try PropertyListSerialization.propertyList(from:data,format:nil) as? [String:Any],PropertyListSerialization.propertyList(prefs,isValidFor:.binary) else {throw ReportError.invalid("Invalid preference snapshot.")}
        }
        guard try Exchange.encoder().encode(state).count<=metadataLimit else {throw ReportError.invalid("Project metadata exceeds 8 MiB.")}
    }
    public static func checkSpace(at directory:URL,bytes:UInt64)throws {
        let attrs=try FileManager.default.attributesOfFileSystem(forPath:directory.path)
        guard let free=attrs[.systemFreeSize] as? NSNumber,free.uint64Value>=bytes,free.uint64Value-bytes>=16*1024*1024 else {throw ReportError.invalid("Not enough free storage for a verified project copy. Free space and retry; existing files are preserved.")}
    }
    /// Copy an explicitly selected regular file into a private immutable, content-addressed store.
    public static func addFile(_ source:URL,kind:String,to folder:URL)throws->Resource {
        guard ["media","attachment","recovery"].contains(kind) else {throw ReportError.invalid("Invalid file category.")}
        try ProjectZIP.regularFile(source)
        let fm=FileManager.default;try fm.createDirectory(at:folder,withIntermediateDirectories:true)
        let temp=folder.appendingPathComponent(".copy-"+UUID().uuidString);defer{try? fm.removeItem(at:temp)}
        let before=try fm.attributesOfItem(atPath:source.path)
        let size=(before[.size] as? NSNumber)?.uint64Value ?? UInt64.max
        guard size<=ProjectZIP.maximumBytes else {throw ReportError.invalid("File exceeds 1 TiB.")};try checkSpace(at:folder,bytes:size)
        guard fm.createFile(atPath:temp.path,contents:nil,attributes:[.posixPermissions:0o600]) else {throw ReportError.invalid("Cannot create a private file copy.")}
        let input=try FileHandle(forReadingFrom:source),output=try FileHandle(forWritingTo:temp);let hash:ProjectZIP.Fingerprint
        do {hash=try ProjectZIP.stream(input,count:nil,destination:output);try output.synchronize();try input.close();try output.close()} catch {try? input.close();try? output.close();throw error}
        let after=try fm.attributesOfItem(atPath:source.path)
        guard hash.size==size,(before[.size] as? NSNumber)==(after[.size] as? NSNumber),(before[.modificationDate] as? Date)==(after[.modificationDate] as? Date),(before[.systemFileNumber] as? NSNumber)==(after[.systemFileNumber] as? NSNumber) else {throw ReportError.invalid("A selected file changed during copying. Wait for recording or editing to finish, then add it again.")}
        let target=try blobURL(folder,hash.sha256)
        if fm.fileExists(atPath:target.path) {guard try ProjectZIP.fingerprint(target)==hash else {throw ReportError.invalid("An existing project file is damaged; no copy was replaced.")}}
        else {try fm.moveItem(at:temp,to:target)}
        return Resource(name:source.lastPathComponent,kind:kind,sha256:hash.sha256,size:hash.size)
    }
    public static func write(_ snapshot:Snapshot,resources:URL,device:String,to destination:URL)throws {
        try validate(snapshot.state);_=try Exchange.read(snapshot.current);if let previous=snapshot.previous {_=try Exchange.read(previous)}
        let fm=FileManager.default,parent=destination.deletingLastPathComponent(),work=parent.appendingPathComponent(".archive-"+UUID().uuidString,isDirectory:true)
        try fm.createDirectory(at:work,withIntermediateDirectories:false);defer{try? fm.removeItem(at:work)}
        var inputs:[String:ProjectZIP.Input]=[:]
        func register(_ url:URL,expected:Resource?=nil)throws->String {
            let f=try ProjectZIP.fingerprint(url)
            if let expected {guard f.sha256==expected.sha256,f.size==expected.size else {throw ReportError.invalid("A saved project file is missing or damaged. Export stopped without omissions.")}}
            inputs[f.sha256]=ProjectZIP.Input(name:"payloads/"+f.sha256,url:url,fingerprint:f);return f.sha256
        }
        func dataBlob(_ bytes:Data)throws->String {let file=work.appendingPathComponent(UUID().uuidString);try bytes.write(to:file,options:.atomic);return try register(file)}
        let current=try dataBlob(snapshot.current),previous=try snapshot.previous.map{try dataBlob($0)}
        var state=snapshot.state
        for (name,hash) in [("Archived report snapshot.camreport",Optional(current)),("Archived previous snapshot.camreport",previous)] {
            if let hash,!state.resources.contains(where:{$0.kind=="recovery" && $0.sha256==hash}) {state.resources.append(Resource(name:name,kind:"recovery",sha256:hash,size:inputs[hash]!.fingerprint.size))}
        }
        try validate(state)
        for resource in state.resources {
            if let registered=inputs[resource.sha256] {guard registered.fingerprint.size==resource.size else {throw ReportError.invalid("Project snapshot/file size metadata disagree.")}}
            else {_=try register(blobURL(resources,resource.sha256),expected:resource)}
        }
        let manifest=Manifest(device:device,current:current,previous:previous,state:state,blobs:inputs.values.map{Blob(sha256:$0.fingerprint.sha256,size:$0.fingerprint.size)}.sorted{$0.sha256<$1.sha256})
        let bytes=try Exchange.encoder().encode(manifest);guard bytes.count<=metadataLimit else {throw ReportError.invalid("Project manifest exceeds 8 MiB.")}
        let metadata=work.appendingPathComponent("manifest.json");try bytes.write(to:metadata,options:.atomic)
        let all=[ProjectZIP.Input(name:"manifest.json",url:metadata,fingerprint:try ProjectZIP.fingerprint(metadata))]+inputs.values.sorted{$0.name<$1.name}
        var total:UInt64=98;for input in all {total=try ProjectZIP.add(total,try ProjectZIP.add(input.fingerprint.size,UInt64(128+input.name.utf8.count*2)))}
        try checkSpace(at:parent,bytes:total);try ProjectZIP.write(all,to:destination)
    }
    /// Verify every byte before returning a preview; destination must be a new private directory.
    public static func read(_ archive:URL,to folder:URL)throws->Prepared {
        let fm=FileManager.default;guard !fm.fileExists(atPath:folder.path) else {throw ReportError.invalid("Import needs a fresh staging folder.")}
        let index=try ProjectZIP.index(archive),data=try ProjectZIP.data(index["manifest.json"]!,from:archive,limit:metadataLimit),manifest=try JSONDecoder().decode(Manifest.self,from:data)
        guard manifest.format=="org.squidproductions.camreport",manifest.schema==2,manifest.scope=="complete-open-report",UUID(uuidString:manifest.packageID) != nil,manifest.device.utf8.count<=1024 else {throw ReportError.invalid("Unsupported complete-report archive. Use a compatible app; nothing was imported.")}
        guard (try JSONSerialization.jsonObject(with:data) as? NSDictionary)==(try JSONSerialization.jsonObject(with:Exchange.encoder().encode(manifest)) as? NSDictionary) else {throw ReportError.invalid("The archive contains unsupported fields; nothing was dropped or imported.")}
        try validate(manifest.state)
        let hashes=Set(manifest.blobs.map(\.sha256));var references=Set(manifest.state.resources.map(\.sha256));references.insert(manifest.current);if let previous=manifest.previous {references.insert(previous)}
        guard hashes.count==manifest.blobs.count,hashes==references,index.count==hashes.count+1 else {throw ReportError.invalid("Missing, duplicate or unreferenced archive payloads.")}
        var total:UInt64=0
        for blob in manifest.blobs {guard validHash(blob.sha256),let entry=index["payloads/"+blob.sha256],entry.fingerprint.size==blob.size else {throw ReportError.invalid("Project payload size/checksum metadata disagree.")};total=try ProjectZIP.add(total,blob.size)}
        for resource in manifest.state.resources {guard manifest.blobs.contains(where:{$0.sha256==resource.sha256 && $0.size==resource.size}) else {throw ReportError.invalid("Project file size metadata disagree.")}}
        try checkSpace(at:folder.deletingLastPathComponent(),bytes:total);try fm.createDirectory(at:folder,withIntermediateDirectories:false,attributes:[.posixPermissions:0o700])
        var finished=false;defer{if !finished {try? fm.removeItem(at:folder)}}
        for blob in manifest.blobs {try ProjectZIP.copy(index["payloads/"+blob.sha256]!,from:archive,to:blobURL(folder,blob.sha256),expectedSHA256:blob.sha256)}
        func snapshotBytes(_ hash:String)throws->Data {let url=try blobURL(folder,hash);guard (try fm.attributesOfItem(atPath:url.path)[.size] as? NSNumber)?.intValue ?? Int.max <= Exchange.limit else {throw ReportError.invalid("A report snapshot exceeds 32 MiB.")};let data=try Data(contentsOf:url);_=try Exchange.read(data);return data}
        let current=try snapshotBytes(manifest.current),previous=try manifest.previous.map{try snapshotBytes($0)},report=try Exchange.read(current).report
        var state=manifest.state
        for (name,bytes) in [("Imported report snapshot.camreport",Optional(current)),("Imported previous snapshot.camreport",previous)] {
            if let bytes {let hash=Exchange.digest(bytes);if !state.resources.contains(where:{$0.kind=="recovery" && $0.sha256==hash}) {state.resources.append(Resource(name:name,kind:"recovery",sha256:hash,size:UInt64(bytes.count)))}}
        }
        try validate(state);finished=true;return Prepared(folder:folder,manifest:manifest,snapshot:Snapshot(current:current,previous:previous,state:state),report:report)
    }
}
