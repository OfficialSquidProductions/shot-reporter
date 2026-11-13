import Foundation

public enum MeasurementUnit:String,CaseIterable,Identifiable {
    case feetInches="ft-in",meters="m",centimeters="cm"
    public var id:String {rawValue}
    public var title:String {switch self {case .feetInches:return "Feet / inches";case .meters:return "Meters";case .centimeters:return "Centimeters"}}
    public var symbol:String {self == .feetInches ? "ft / in":rawValue}
    public var example:String {switch self {case .feetInches:return "5 ft 6 in";case .meters:return "1.68 m";case .centimeters:return "168 cm"}}
}
public enum LengthMeasurement {
    private static let number="(?:[0-9]+(?:\\.[0-9]+)?(?: +[0-9]+/[0-9]+)?|[0-9]+/[0-9]+)"
    private static func scalar(_ text:String)->Double? {
        let parts=text.split(separator:" ");var sum=0.0
        for part in parts {let fraction=part.split(separator:"/",omittingEmptySubsequences:false);let value:Double
            if fraction.count==2,let a=Double(fraction[0]),let b=Double(fraction[1]),b>0 {value=a/b}
            else if fraction.count==1,let a=Double(part) {value=a} else {return nil}
            guard value.isFinite,value>=0 else {return nil};sum+=value
        };return sum
    }
    private static func match(_ pattern:String,_ text:String)->[String]? {
        guard let regex=try? NSRegularExpression(pattern:"^"+pattern+"$",options:.caseInsensitive),let result=regex.firstMatch(in:text,range:NSRange(text.startIndex...,in:text)),result.range.length==(text as NSString).length else {return nil}
        return (1..<result.numberOfRanges).map{result.range(at:$0).location == NSNotFound ? "":(text as NSString).substring(with:result.range(at:$0))}
    }
    /// Legacy values without an explicit recognized unit remain ambiguous and are never guessed.
    public static func meters(_ raw:String)->Double? {
        let s=raw.trimmingCharacters(in:.whitespacesAndNewlines).lowercased().replacingOccurrences(of:"’",with:"'").replacingOccurrences(of:"‘",with:"'").replacingOccurrences(of:"′",with:"'").replacingOccurrences(of:"”",with:"\"").replacingOccurrences(of:"“",with:"\"").replacingOccurrences(of:"″",with:"\"")
        var result:Double?
        if let p=match("("+number+")\\s*(?:ft|feet|foot|')\\s*(?:([0-9]+(?:\\.[0-9]+)?(?: +[0-9]+/[0-9]+)?|[0-9]+/[0-9]+)\\s*(?:in|inch|inches|\"))?",s),let feet=scalar(p[0]),let inches=p[1].isEmpty ? 0:scalar(p[1]) {result=feet*0.3048+inches*0.0254}
        else if let p=match("("+number+")\\s*(cm|centimeter|centimeters|m|meter|meters|in|inch|inches|\")",s),let value=scalar(p[0]) {result=value * (["cm","centimeter","centimeters"].contains(p[1]) ? 0.01:["m","meter","meters"].contains(p[1]) ? 1:0.0254)}
        guard let result,result.isFinite,result<=1_000_000_000 else {return nil};return result
    }
    private static func decimal(_ value:Double,_ places:Int)->String {
        var s=String(format:"%.*f",locale:Locale(identifier:"en_US_POSIX"),places,value)
        while s.contains("."),s.hasSuffix("0") {s.removeLast()};if s.hasSuffix(".") {s.removeLast()};return s
    }
    public static func display(_ raw:String,unit:MeasurementUnit)->String {
        guard let value=meters(raw) else {return raw}
        switch unit {
        case .meters:return decimal(value,4)+" m"
        case .centimeters:return decimal(value*100,2)+" cm"
        case .feetInches:
            var feet=floor(value/0.3048),inches=((value/0.0254-feet*12)*1000).rounded()/1000
            if inches>=12 {feet+=1;inches=0};return decimal(feet,0)+" ft "+decimal(max(0,inches),3)+" in"
        }
    }
    /// Only newly edited unqualified numbers assume the selected unit. Existing raw values stay intact.
    public static func edited(_ text:String,unit:MeasurementUnit)->String {
        let s=text.trimmingCharacters(in:.whitespacesAndNewlines)
        if s.isEmpty {return text};if meters(s) != nil {return text}
        if match("("+number+")",s) != nil {
            return s+(unit == .feetInches ? " ft":" "+unit.rawValue)
        }
        return text
    }
}
public enum LightMeterUnit:String,CaseIterable,Identifiable {
    case fStop="f-stop",ev="EV",lux="lux",footCandles="fc"
    public var id:String {rawValue}
    public var title:String {switch self {case .fStop:return "f-stop";case .ev:return "EV";case .lux:return "lux (lx)";case .footCandles:return "foot-candles (fc)"}}
}
public extension Report {
    var measurementUnit:MeasurementUnit {
        get {MeasurementUnit(rawValue:values["measurementUnit",default:""]) ?? .feetInches}
        set {values["measurementUnit"]=newValue.rawValue}
    }
    func displayedValue(_ key:String,in entry:Entry)->String {
        let raw=entry.values[key,default:""]
        if ["height","distance"].contains(key) {return LengthMeasurement.display(raw,unit:measurementUnit)}
        if key=="lightMeterUnit",!entry.values["lightMeter",default:""].isEmpty {return entry.values[key,default:"f-stop"]}
        return raw
    }
    func nextShootingDay()throws->Report {
        let raw=Self.dayLabel(values["day"])
        let day:Int
        if raw.isEmpty {day=1}
        else {guard raw.utf8.allSatisfy({(48...57).contains($0)}),let current=Int(raw),current<Int.max else {throw ReportError.invalid("Enter a whole-number Shooting day in Today before starting the next day.")};day=current+1}
        var next=Report();next.values=values;next.values["day"]=String(day)
        var calendar=Calendar(identifier:.gregorian);calendar.timeZone=TimeZone(secondsFromGMT:0)!
        let formatter=DateFormatter();formatter.locale=Locale(identifier:"en_US_POSIX");formatter.calendar=calendar;formatter.timeZone=calendar.timeZone;formatter.dateFormat="yyyy-MM-dd";formatter.isLenient=false
        if let rawDate=values["date"],let date=formatter.date(from:rawDate),formatter.string(from:date)==rawDate,let tomorrow=calendar.date(byAdding:.day,value:1,to:date) {next.values["date"]=formatter.string(from:tomorrow)}
        else {next.values["date"]=formatter.string(from:Date())}
        next.profile=profile;next.positions=positions;next.namingSettings=namingSettings;next.namingTemplate=namingTemplate;next.defaults=defaults
        for field in Schema.lighting {next.defaults.removeValue(forKey:field.id)}
        next.defaults["load"]=UUID().uuidString;next.defaults["mag"]="";next.defaults.removeValue(forKey:"height");next.defaults.removeValue(forKey:"distance")
        return next
    }
    static func dayLabel(_ value:String?)->String {
        var day=(value ?? "").trimmingCharacters(in:.whitespacesAndNewlines)
        if let prefix=day.range(of:"^day\\s+",options:[.regularExpression,.caseInsensitive]) {day.removeSubrange(prefix);day=day.trimmingCharacters(in:.whitespacesAndNewlines)}
        return day
    }
}
