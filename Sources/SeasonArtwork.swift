import AppKit

/// Complete character poses, with outfit perspective and contact painted into each frame.
final class SeasonArtwork {
    struct Poses {
        let idle:[NSImage],walking:[NSImage]
        let idlePixels:[NSBitmapImageRep],walkingPixels:[NSBitmapImageRep]
        let safetyCore:NSRect
        func image(walking:Bool,frame:Int)->NSImage {
            let sequence=walking ? self.walking : idle
            return sequence[frame % sequence.count]
        }
        func pixels(walking:Bool,frame:Int)->NSBitmapImageRep {
            let sequence=walking ? walkingPixels : idlePixels
            return sequence[frame % sequence.count]
        }
    }
    private var poses:[PetSeason:Poses]=[:]
    let dressing: SeasonDressing
    subscript(_ season:PetSeason)->Poses {poses[season]!}
    init(resources:URL)throws {
        let root=resources.appendingPathComponent("seasons")
        dressing = try SeasonDressing(root: root)
        let metadata=try JSONDecoder().decode([String:[String:Double]].self,from:Data(contentsOf:root.appendingPathComponent("visibility.json")))
        for season in PetSeason.allCases {
            func sequence(_ name:String,_ count:Int)throws->([NSImage],[NSBitmapImageRep]) {
                var images:[NSImage]=[],pixels:[NSBitmapImageRep]=[]
                for i in 0..<count {
                    let url=root.appendingPathComponent(String(format:"%@/%@/%02d.png",season.rawValue,name,i))
                    let data=try Data(contentsOf:url)
                    guard let image=NSImage(data:data),let bitmap=NSBitmapImageRep(data:data),bitmap.hasAlpha,bitmap.pixelsWide==192,bitmap.pixelsHigh==208 else {
                        throw NSError(domain:"SusuSeason",code:1,userInfo:[NSLocalizedDescriptionKey:"季节动作素材无效：\(season.title)"])
                    }
                    images.append(image);pixels.append(bitmap)
                }
                return (images,pixels)
            }
            let (idle,idlePixels)=try sequence("idle",6)
            let (walk,walkPixels)=try sequence("walking",8)
            guard let info=metadata[season.rawValue],let x=info["x"],let y=info["y"],let w=info["width"],let h=info["height"],
                  [x,y,w,h].allSatisfy({$0.isFinite}),x>=0,y>=0,w>0,h>0,x+w<=1,y+h<=1 else {
                throw NSError(domain:"SusuSeason",code:2,userInfo:[NSLocalizedDescriptionKey:"季节外观缺少可见区域信息。"])
            }
            poses[season]=Poses(idle:idle,walking:walk,idlePixels:idlePixels,walkingPixels:walkPixels,safetyCore:NSRect(x:x,y:y,width:w,height:h))
        }
    }
}
