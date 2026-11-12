import Foundation
import CryptoKit

/// Bounded, stored ZIP64 for large project files. No generic path extraction, compression,
/// encryption, links, descriptors, comments or trailing data are accepted.
enum ProjectZIP {
    static let chunkSize=1024*1024
    static let maximumBytes:UInt64=1<<40 // 1 TiB; available storage is checked separately.
    static let maximumEntries=20_000
    static let maximumDirectoryBytes=8*1024*1024
    struct Fingerprint:Equatable {var size:UInt64;var crc:UInt32;var sha256:String}
    struct Input {var name:String;var url:URL;var fingerprint:Fingerprint}
    struct Entry {var name:String;var offset:UInt64;var fingerprint:Fingerprint}
    static let crcTable:[UInt32]=(0..<256).map {n in var c=UInt32(n);for _ in 0..<8 {c=(c>>1) ^ (c&1 == 1 ? 0xedb88320:0)};return c}
    static func checksum(_ data:Data,_ prior:UInt32)->UInt32 {
        var c=prior;data.withUnsafeBytes {raw in for b in raw.bindMemory(to:UInt8.self) {c=(c>>8) ^ crcTable[Int((c ^ UInt32(b))&255)]}};return c
    }
    static func fingerprint(_ url:URL)throws->Fingerprint {
        try regularFile(url)
        let h=try FileHandle(forReadingFrom:url);defer{try? h.close()};return try stream(h,count:nil,destination:nil)
    }
    static func regularFile(_ url:URL)throws {
        let values=try url.resourceValues(forKeys:[.isRegularFileKey,.isSymbolicLinkKey,.isAliasFileKey])
        guard values.isRegularFile == true,values.isSymbolicLink != true,values.isAliasFile != true else {throw ReportError.invalid("Only regular files can be included. Folders, aliases and symbolic links are not followed.")}
    }
    static func add(_ a:UInt64,_ b:UInt64)throws->UInt64 {
        let (n,overflow)=a.addingReportingOverflow(b);guard !overflow,n<=maximumBytes else {throw ReportError.invalid("Project archive exceeds the 1 TiB safety limit.")};return n
    }
    static func stream(_ source:FileHandle,count:UInt64?,destination:FileHandle?)throws->Fingerprint {
        var size:UInt64=0,crc:UInt32=0xffffffff,sha=SHA256()
        while count == nil || size < count! {
            try Task.checkCancellation()
            let wanted=Int(min(UInt64(chunkSize),count.map{$0-size} ?? UInt64(chunkSize)))
            let bytes=try source.read(upToCount:wanted) ?? Data()
            if bytes.isEmpty {if let count,size != count {throw ReportError.invalid("A project file ended unexpectedly.")};break}
            size=try add(size,UInt64(bytes.count));crc=checksum(bytes,crc);sha.update(data:bytes);try destination?.write(contentsOf:bytes)
        }
        return Fingerprint(size:size,crc:crc ^ 0xffffffff,sha256:sha.finalize().map{String(format:"%02x",$0)}.joined())
    }
    static func validName(_ name:String)->Bool {
        if name == "manifest.json" {return true}
        return name.hasPrefix("payloads/") && name.utf8.count == 73 && name.dropFirst(9).utf8.allSatisfy{(48...57).contains($0)||(97...102).contains($0)}
    }
    static func number(_ value:UInt64,_ width:Int)->Data {Data((0..<width).map{UInt8(truncatingIfNeeded:value >> ($0*8))})}
    static func value(_ data:Data,_ offset:Int,_ width:Int)throws->UInt64 {
        guard offset>=0,width>0,width<=8,offset<=data.count-width else {throw ReportError.invalid("Truncated project ZIP metadata.")}
        return (0..<width).reduce(UInt64(0)){$0 | UInt64(data[offset+$1]) << ($1*8)}
    }
    static func packed(_ values:[(UInt64,Int)])->Data {values.reduce(into:Data()){$0.append(number($1.0,$1.1))}}
    static func read(_ handle:FileHandle,_ offset:UInt64,_ count:Int)throws->Data {
        guard count>=0,count<=maximumDirectoryBytes else {throw ReportError.invalid("Project ZIP metadata is too large.")}
        try handle.seek(toOffset:offset);let data=try handle.read(upToCount:count) ?? Data();guard data.count==count else {throw ReportError.invalid("Truncated project ZIP.")};return data
    }
    static func write(_ inputs:[Input],to url:URL)throws {
        guard !inputs.isEmpty,inputs.count<=maximumEntries,Set(inputs.map(\.name)).count==inputs.count,inputs.allSatisfy({validName($0.name)}) else {throw ReportError.invalid("Invalid or duplicate project ZIP members.")}
        var bound:UInt64=98
        for input in inputs {bound=try add(bound,try add(input.fingerprint.size,UInt64(128+input.name.utf8.count*2)))}
        let fm=FileManager.default;guard !fm.fileExists(atPath:url.path),fm.createFile(atPath:url.path,contents:nil,attributes:[.posixPermissions:0o600]) else {throw ReportError.invalid("Choose a new archive destination; existing files are preserved.")}
        var finished=false;defer{if !finished {try? fm.removeItem(at:url)}}
        let output=try FileHandle(forWritingTo:url);defer{try? output.close()};var directory=Data()
        for item in inputs {
            try Task.checkCancellation();try regularFile(item.url)
            let offset=try output.offset(),name=Data(item.name.utf8),f=item.fingerprint
            let extra=packed([(1,2),(16,2),(f.size,8),(f.size,8)])
            let local=packed([(0x04034b50,4),(45,2),(0,2),(0,2),(0,2),(0,2),(UInt64(f.crc),4),(0xffffffff,4),(0xffffffff,4),(UInt64(name.count),2),(UInt64(extra.count),2)])
            _=try add(offset,UInt64(local.count+name.count+extra.count));try output.write(contentsOf:local+name+extra)
            let source=try FileHandle(forReadingFrom:item.url);let actual:Fingerprint
            do {actual=try stream(source,count:nil,destination:output);try source.close()} catch {try? source.close();throw error}
            guard actual==f else {throw ReportError.invalid("A source file changed while archiving. Nothing was published; retry after the file is stable.")}
            let centralExtra=packed([(1,2),(24,2),(f.size,8),(f.size,8),(offset,8)])
            directory += packed([(0x02014b50,4),(0x032d,2),(45,2),(0,2),(0,2),(0,2),(0,2),(UInt64(f.crc),4),(0xffffffff,4),(0xffffffff,4),(UInt64(name.count),2),(UInt64(centralExtra.count),2),(0,2),(0,2),(0,2),(UInt64(0o100600)<<16,4),(0xffffffff,4)])+name+centralExtra
            guard directory.count<=maximumDirectoryBytes else {throw ReportError.invalid("Too many project files.")}
        }
        let centralOffset=try output.offset();try output.write(contentsOf:directory);let zip64Offset=try output.offset(),count=UInt64(inputs.count)
        try output.write(contentsOf:packed([(0x06064b50,4),(44,8),(45,2),(45,2),(0,4),(0,4),(count,8),(count,8),(UInt64(directory.count),8),(centralOffset,8)]))
        try output.write(contentsOf:packed([(0x07064b50,4),(0,4),(zip64Offset,8),(1,4)]))
        try output.write(contentsOf:packed([(0x06054b50,4),(0,2),(0,2),(0xffff,2),(0xffff,2),(0xffffffff,4),(0xffffffff,4),(0,2)]))
        guard try output.offset()<=maximumBytes else {throw ReportError.invalid("Project archive exceeds the 1 TiB safety limit.")}
        try output.synchronize();finished=true
    }
    static func index(_ url:URL)throws->[String:Entry] {
        try regularFile(url);let h=try FileHandle(forReadingFrom:url);defer{try? h.close()};let size=try h.seekToEnd()
        guard size>=98,size<=maximumBytes else {throw ReportError.invalid("Invalid project archive size (1 TiB maximum).")}
        let end=try read(h,size-22,22)
        guard (try value(end,0,4))==0x06054b50,(try value(end,4,2))==0,(try value(end,6,2))==0,(try value(end,8,2))==0xffff,(try value(end,10,2))==0xffff,(try value(end,12,4))==0xffffffff,(try value(end,16,4))==0xffffffff,(try value(end,20,2))==0 else {throw ReportError.invalid("Expected a complete stored ZIP64 project archive.")}
        let locator=try read(h,size-42,20),record=try read(h,size-98,56)
        guard (try value(locator,0,4))==0x07064b50,(try value(locator,4,4))==0,(try value(locator,8,8))==size-98,(try value(locator,16,4))==1,(try value(record,0,4))==0x06064b50,(try value(record,4,8))==44,(try value(record,12,2))==45,(try value(record,14,2))==45,(try value(record,16,4))==0,(try value(record,20,4))==0 else {throw ReportError.invalid("Invalid ZIP64 footer; no files were imported.")}
        let count=(try value(record,32,8)),directorySize=(try value(record,40,8)),directoryOffset=(try value(record,48,8))
        guard count>0,count<=UInt64(maximumEntries),(try value(record,24,8))==count,directorySize<=UInt64(maximumDirectoryBytes),directoryOffset<=size-98,directorySize==size-98-directoryOffset else {throw ReportError.invalid("Invalid project directory bounds.")}
        let directory=try read(h,directoryOffset,Int(directorySize));var p=0,entries:[String:Entry]=[:],nextOffset:UInt64=0
        for _ in 0..<Int(count) {
            guard (try value(directory,p,4))==0x02014b50,(try value(directory,p+4,2))==0x032d,(try value(directory,p+6,2))==45,(try value(directory,p+8,2))==0,(try value(directory,p+10,2))==0,(try value(directory,p+20,4))==0xffffffff,(try value(directory,p+24,4))==0xffffffff,(try value(directory,p+32,2))==0,(try value(directory,p+34,2))==0,(try value(directory,p+36,2))==0,(try value(directory,p+38,4))==UInt64(0o100600)<<16,(try value(directory,p+42,4))==0xffffffff else {throw ReportError.invalid("Unsupported ZIP member: links, encryption, compression and multi-disk files are refused.")}
            let n=Int((try value(directory,p+28,2))),extra=Int((try value(directory,p+30,2))),start=p+46,end=start+n
            guard n<=128,extra==28,end+extra<=directory.count,let name=String(data:directory.subdata(in:start..<end),encoding:.utf8),validName(name),entries[name]==nil else {throw ReportError.invalid("Unsafe or duplicate project member name.")}
            let x=directory.subdata(in:end..<end+extra)
            guard (try value(x,0,2))==1,(try value(x,2,2))==24,(try value(x,4,8))==(try value(x,12,8)),(try value(x,20,8))==nextOffset else {throw ReportError.invalid("Invalid or overlapping ZIP64 member.")}
            let length=(try value(x,4,8)),offset=(try value(x,20,8)),crc=UInt32((try value(directory,p+16,4)))
            guard offset<=directoryOffset,directoryOffset-offset>=UInt64(30+n+20) else {throw ReportError.invalid("Invalid project member bounds.")}
            let local=try read(h,offset,30+n+20)
            guard (try value(local,0,4))==0x04034b50,(try value(local,4,2))==45,(try value(local,6,2))==0,(try value(local,8,2))==0,(try value(local,14,4))==UInt64(crc),(try value(local,18,4))==0xffffffff,(try value(local,22,4))==0xffffffff,(try value(local,26,2))==UInt64(n),(try value(local,28,2))==20,local.subdata(in:30..<30+n)==Data(name.utf8),(try value(local,30+n,2))==1,(try value(local,32+n,2))==16,(try value(local,34+n,8))==length,(try value(local,42+n,8))==length else {throw ReportError.invalid("Local and central project metadata disagree.")}
            let payload=try add(offset,UInt64(local.count));guard length<=directoryOffset-payload else {throw ReportError.invalid("Project member exceeds archive bounds.")}
            nextOffset=try add(payload,length);entries[name]=Entry(name:name,offset:payload,fingerprint:Fingerprint(size:length,crc:crc,sha256:""));p=end+extra
        }
        guard p==directory.count,nextOffset==directoryOffset,entries["manifest.json"] != nil else {throw ReportError.invalid("Incomplete project directory or hidden trailing payloads.")};return entries
    }
    static func data(_ entry:Entry,from url:URL,limit:Int)throws->Data {
        guard entry.fingerprint.size<=UInt64(limit) else {throw ReportError.invalid("Project metadata exceeds its safety limit.")}
        let h=try FileHandle(forReadingFrom:url);defer{try? h.close()};try h.seek(toOffset:entry.offset)
        let data=try h.read(upToCount:Int(entry.fingerprint.size)) ?? Data()
        guard data.count==Int(entry.fingerprint.size),checksum(data,0xffffffff) ^ 0xffffffff == entry.fingerprint.crc else {throw ReportError.invalid("Project metadata CRC mismatch.")};return data
    }
    static func copy(_ entry:Entry,from archive:URL,to destination:URL,expectedSHA256:String)throws {
        let fm=FileManager.default;guard !fm.fileExists(atPath:destination.path),fm.createFile(atPath:destination.path,contents:nil,attributes:[.posixPermissions:0o600]) else {throw ReportError.invalid("Import requires a fresh destination; existing files are preserved.")}
        var finished=false;defer{if !finished {try? fm.removeItem(at:destination)}}
        let source=try FileHandle(forReadingFrom:archive),output=try FileHandle(forWritingTo:destination);defer{try? source.close();try? output.close()}
        try source.seek(toOffset:entry.offset);let result=try stream(source,count:entry.fingerprint.size,destination:output)
        guard result.crc==entry.fingerprint.crc,result.sha256==expectedSHA256 else {throw ReportError.invalid("A project payload failed its CRC or SHA-256 check; nothing was imported.")}
        try output.synchronize();finished=true
    }
}
