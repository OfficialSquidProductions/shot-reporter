import Foundation
#if !SHOT_REPORTER_FIXTURE_TOOL
@testable import CameraStatsCore
#endif

extension Report {
    static func fullHandoffFixture()->Report {
        var r=Report();r.id="61000000-0000-4000-8000-000000000001"
        r.values=["title":"Harbor Lights - Night Unit","date":"2026-11-12","day":"12","director":"Avery Quinn","dp":"Morgan Lee","dit":"Casey Patel","cycle":"N/A - professional unit","professor":"N/A - professional unit","season":"2","episode":"7","productionMode":"movie","productionCompany":"Harbor Unit Pictures (synthetic)","contactNotes":"Night exterior; café entrance / カメラ 🎬","schedule":"Scenes 12B, 14A; pickup window 22:00-23:30"]
        r.profile=Schema.profiles[2];r.positions=["DP / operator","Script / continuity"]
        r.defaults=["camera":"B","mag":"B-SSD-03","load":"62000000-0000-4000-8000-000000000002","roll":"B003","resolution":"3840 x 2160","compression":"ProRes 4444 XQ","aspect":"2.39:1 extraction","playbackRate":"24000/1001","sensorRate":"48000/1001","shutter":"180 degrees","iso":"1280","temperature":"4300K / +3 magenta","filters":"ND 0.6 + diffusion 1/8","look":"LogC4 / AWG4; show LUT v03","lens":"50 mm prime","stop":"T2.8","height":"1.45 m","distance":"3.2 m","customCameraNote":"B camera matched to A; retain verbatim"]
        for i in 0..<6 {
            var v=r.defaults;v["scene"]=i<4 ? "12B":"14A";v["take"]=String(i%3+1);v["camera"]=i%2==0 ? "A":"B";v["mag"]=i%2==0 ? "A-SSD-02":"B-SSD-03"
            v["sensorRate"]=i==3 ? "60000/1001":"24000/1001";v["lens"]=i<3 ? "35 mm prime":"50 mm prime";v["distance"]="\(2+i).2 m";v["originalFilename"]="HL_\(v["camera"]!)_20261112_\(String(format:"%04d",i+1)).mov"
            v["remarks"]="Dolly across wet pavement. Focus lands on café doorway.\nSecond beat: hold on the practical sign; check highlight detail."
            v["dpNotes"]="Keep warm practicals; protect the cyan shop window. Preferred lens/distance recorded per take."
            v["continuity"]="Actor carries umbrella in left hand. Cup at 2/3 full. Dialogue cue: ‘Ready?’\nMatch rain level and coat collar to master."
            v["editorNotes"]="Use entrance after cue; preserve 2-second head and tail. \(i==2 ? "Preferred performance.":"Alternate timing.")"
            v["sound"]="SOUND_012_\(i+1).wav";v["timecode"]="22:14:\(String(format:"%02d",i)):00";v["customTakeField"]="Lens serial synthetic \(i+1)"
            if i==0 {v["lightMeter"]="2.8 + 1/3";v["lightMeterUnit"]="f-stop";v["lightMeterContext"]="Subject face / incident / ISO 800 / 1/48 s"}
            if i==1 {v["lightMeter"]="400";v["lightMeterUnit"]="lux";v["lightMeterContext"]="Doorway key / incident"}
            var e=Entry(values:v);e.id=String(format:"63000000-0000-4000-8000-%012d",i+1);e.created=Date(timeIntervalSinceReferenceDate:815_000_000+Double(i));e.flags=i==2 ? ["Circle","MOS","Tail slate"]:[];e.reviewed=i != 5;e.deleted=i==5;r.entries.append(e)
        }
        r.namingTemplate="{project}_S{season}E{episode}_SC{scene}_TK{take:03}_CAM-{camera}"
        var naming=NamingSettings(legacyTemplate:r.namingTemplate);naming.loadSaved(id:"harbor-unit",name:"Harbor delivery",template:"{project}_{camera}_{original}");naming.setEnabled("episode",false);r.namingSettings=naming
        r.importedPackages=["64000000-0000-4000-8000-000000000001"]
        r.revision=18;r.history=[Change(device:"Synthetic iPhone",summary:"Created full production and six takes"),Change(device:"Synthetic Mac",summary:"Reviewed notes, flags, custom naming and camera settings")]
        for i in r.history.indices {r.history[i].date=Date(timeIntervalSinceReferenceDate:815_000_100+Double(i))};return r
    }
    static func phoneHandoffEdit(_ report:Report)->Report {
        var r=report;r.values["productionMode"]="tv";r.values["schedule"]! += "\nPhone: pickup completed."
        r.entries[0].values["continuity"]! += "\nPhone: reset umbrella before the close-up."
        r.defaults["iso"]="1600";r.record("Phone handoff edit",device:"iPhone Simulator QA");r.history[r.history.count-1].date=Date(timeIntervalSinceReferenceDate:815_000_200);return r
    }
}
