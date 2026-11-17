import AppKit

/// Accessories use the same 192×208 canvas as the fox, so mirroring remains aligned.
enum ScarfRenderer {
    static func overlay(state:StudioState, walking:Bool, frame:Int)->NSImage? {
        guard state.scarf != "none" else { return nil }
        if let pack=state.packs.first(where:{$0.id.uuidString==state.scarf}) {
            let images=walking ? pack.walking : pack.idle
            return NSImage(data:images[frame%images.count])
        }
        return NSImage(size:NSSize(width:192,height:208),flipped:false) { _ in
            let color:NSColor
            switch state.scarf {
            case "amber":color=NSColor(srgbRed:0.91,green:0.57,blue:0.17,alpha:1)
            case "rose":color=NSColor(srgbRed:0.72,green:0.30,blue:0.39,alpha:1)
            default:color=NSColor(srgbRed:0.14,green:0.57,blue:0.57,alpha:1)
            }
            color.setFill()
            if walking {
                let shifts:[CGFloat]=[0,1,0,-1,0,1,0,-1]
                let y:CGFloat=78+shifts[frame%8]
                NSBezierPath(roundedRect:NSRect(x:136,y:y,width:15,height:16),xRadius:4,yRadius:4).fill()
                let ribbon=NSBezierPath()
                ribbon.move(to:NSPoint(x:138,y:y+4));ribbon.line(to:NSPoint(x:127,y:y-22))
                ribbon.line(to:NSPoint(x:140,y:y-18));ribbon.line(to:NSPoint(x:145,y:y+5));ribbon.close();ribbon.fill()
            } else {
                NSBezierPath(roundedRect:NSRect(x:58,y:87,width:53,height:12),xRadius:6,yRadius:6).fill()
                let ribbon=NSBezierPath()
                ribbon.move(to:NSPoint(x:97,y:91));ribbon.line(to:NSPoint(x:102,y:62))
                ribbon.line(to:NSPoint(x:115,y:66));ribbon.line(to:NSPoint(x:108,y:94));ribbon.close();ribbon.fill()
            }
            return true
        }
    }
    static func importPack(at folder:URL)throws->ScarfPack {
        struct Manifest:Decodable {let version:Int;let name:String;let idle:[String];let walking:[String]}
        let metadata=folder.appendingPathComponent("scarf.json")
        guard (try metadata.resourceValues(forKeys:[.fileSizeKey])).fileSize ?? 20001 <= 20000 else{throw error("素材清单过大。")}
        let raw=try Data(contentsOf:metadata)
        guard raw.count<=20000 else{throw error("素材清单过大。")}
        let manifest=try JSONDecoder().decode(Manifest.self,from:raw)
        guard manifest.version==1, !manifest.name.isEmpty, manifest.name.count<=80,
              manifest.idle.count==6,manifest.walking.count==8 else{throw error("需要 6 帧 idle 和 8 帧 walking，清单版本为 1。")}
        let base=folder.resolvingSymlinksInPath().standardizedFileURL.path+"/"
        func load(_ paths:[String])throws->[Data] {
            try paths.map { relative in
                let file=folder.appendingPathComponent(relative).resolvingSymlinksInPath().standardizedFileURL
                guard !relative.hasPrefix("/"),file.path.hasPrefix(base),file.pathExtension.lowercased()=="png" else{throw error("素材路径必须位于所选文件夹内。")}
                let size=(try file.resourceValues(forKeys:[.fileSizeKey])).fileSize ?? 0
                guard size>0,size<=300000 else{throw error("素材缺失或过大：\(relative)")}
                let data=try Data(contentsOf:file)
                guard CompanionStore.validOverlayHeader(data), let bitmap=NSBitmapImageRep(data:data),bitmap.hasAlpha else{throw error("\(relative) 必须是 192×208 的透明 PNG。")}
                let corners=[(0,0),(191,0),(0,207),(191,207)]
                guard corners.allSatisfy({(bitmap.colorAt(x:$0.0,y:$0.1)?.alphaComponent ?? 1)<0.1}) else{throw error("配饰四角应透明，以免遮盖狐狸。")}
                return data
            }
        }
        return ScarfPack(name:manifest.name,idle:try load(manifest.idle),walking:try load(manifest.walking))
    }
    static func exportTemplate(to folder:URL)throws {
        try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
        var paths:[String:[String]]=[:]
        var state=StudioState();state.scarf="teal"
        for (name,count) in [("idle",6),("walking",8)] {
            let directory=folder.appendingPathComponent(name)
            try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
            paths[name]=[]
            for index in 0..<count {
                let file=String(format:"%@/%02d.png",name,index)
                let image=overlay(state:state,walking:name=="walking",frame:index)!
                // Explicit pixel size keeps the template independent of display scaling.
                let bitmap=NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:192,pixelsHigh:208,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0)!
                let context=NSGraphicsContext(bitmapImageRep:bitmap)!
                NSGraphicsContext.saveGraphicsState();NSGraphicsContext.current=context
                context.cgContext.clear(CGRect(x:0,y:0,width:192,height:208))
                image.draw(in:NSRect(x:0,y:0,width:192,height:208))
                NSGraphicsContext.restoreGraphicsState()
                try bitmap.representation(using:.png,properties:[:])!.write(to:folder.appendingPathComponent(file))
                paths[name]?.append(file)
            }
        }
        let manifest:[String:Any]=["version":1,"name":"我的围巾","idle":paths["idle"]!,"walking":paths["walking"]!]
        try JSONSerialization.data(withJSONObject:manifest,options:[.prettyPrinted,.sortedKeys]).write(to:folder.appendingPathComponent("scarf.json"))
    }
    private static func error(_ message:String)->NSError {
        NSError(domain:"SusuScarf",code:1,userInfo:[NSLocalizedDescriptionKey:message])
    }
}
