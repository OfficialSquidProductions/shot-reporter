import Foundation

public extension Report {
    static let demoScript = #"""
Title: The Last Light

1 EXT. COASTAL ROAD - DAWN

A battered station wagon follows the coast. The lighthouse is a pin of light in the mist.

MAYA
We should have left yesterday.

ELI
And missed all this?

2 INT. STATION WAGON - DAY

Maya unfolds an old map. A red circle marks the lighthouse.

MAYA
That's where he said he'd be.

ELI
Then that's where we go.

3 EXT. LIGHTHOUSE - DAY

The car rolls to a stop. JONAH waits at the foot of the lighthouse, holding a brass key.

JONAH
I wasn't sure you'd come.

MAYA
Neither was I.

4 INT. LIGHTHOUSE STAIRWELL - DAY

Jonah leads Maya up a winding staircase. She runs a hand along the worn stone.

JONAH
One hundred and twelve steps. Your father counted every morning.

MAYA
Of course he did.

5 INT. LANTERN ROOM - DAY

Eli opens a wooden box. Inside: a letter, a photograph, and a compass.

ELI
This has your name on it.

MAYA
Let me see.

6 EXT. LIGHTHOUSE - DUSK

Maya and Jonah sit on the seawall. The tide comes in below them.

MAYA
How long do you think he waited?

JONAH
As long as he needed to.

7 INT. LANTERN ROOM - NIGHT

Maya turns the brass key. The old mechanism wakes with a low, steady hum.

MAYA
There you are.

8 EXT. COASTAL ROAD - NIGHT

Eli closes the car door. They look back. The lighthouse sweeps across the water.

ELI
Ready?

MAYA
Now I am.

"""#
    // Canonical planning fixture shared with Scenic and Production Desk.
    static let demoScriptSHA256 = "84b4bea90b72a1d3d09be8925b07cdf696e9bc579386ed21c3255bb305336f87"
    static let demoShotPlan = #"""
FICTIONAL DEMO · shared shot plan
Only 3A has completed takes; other shots remain planned.

1A · A camera · 24mm · Wide · Tracking
Station wagon follows the coastal road toward the lighthouse.
Planned · 0 takes

1B · B camera · 50mm · Medium · Static
Maya and Eli react to the lighthouse in the mist.
Planned · 0 takes

2A · A camera · 35mm · Medium · Static
Maya unfolds the road map beside Eli.
Planned · 0 takes

2B · B camera · 85mm · Insert · Static
Red circle on the folded road map marks the lighthouse.
Planned · 0 takes

3A · A camera · 24mm · Wide · Static
Station wagon stops at the foot of the lighthouse; Jonah waits.
Done · 3 takes · circle 2

3B · B camera · 85mm · Close-up · Static
Jonah offers the brass key to Maya.
Ready · 0 takes

4A · A camera · 35mm · Medium wide · Tilt
Follow Jonah and Maya ascending the winding stairwell.
Planned · 0 takes

4B · B camera · 85mm · Insert · Static
Maya runs her hand along the worn stone.
Planned · 0 takes

5A · A camera · 50mm · Medium · Static
Eli opens the wooden box as Maya watches.
Planned · 0 takes

5B · B camera · 85mm · Insert · Static
Letter, photograph and compass inside the wooden box.
Planned · 0 takes

6A · A camera · 35mm · Medium wide · Static
Maya and Jonah sit on the seawall above the tide.
Planned · 0 takes

6B · B camera · 85mm · Close-up · Static
Maya listens as Jonah remembers her father.
Planned · 0 takes

7A · A camera · 85mm · Insert · Static
Maya turns the brass key in the lighthouse mechanism.
Planned · 0 takes

7B · B camera · 50mm · Medium · Pan
The lantern wakes; Maya sees the light return.
Planned · 0 takes

8A · A camera · 50mm · Medium · Static
Eli closes the car door; Maya is ready to leave.
Planned · 0 takes

8B · B camera · 24mm · Wide · Pan
The lighthouse beam sweeps the water behind the departing wagon.
Planned · 0 takes

"""#
    static func demo() -> Report {
        var r = Report.fixture()
        r.id = UUID().uuidString; r.entries = []; r.history = []; r.revision = 0
        r.values["title"] = "The Last Light · DEMO"; r.values["date"] = "2026-11-02"
        r.values["day"] = "01"; r.values["demoScript"] = demoScript
        r.values["demoShotPlan"] = demoShotPlan; r.values["demoScriptSHA256"] = demoScriptSHA256
        r.values["director"] = "Demo director (fictional)"; r.values["dp"] = "Demo DP (fictional)"
        r.values["dit"] = "N/A — student covers all duties"
        r.values["cycle"] = "DEMO 01"; r.values["professor"] = "Demo instructor (fictional)"
        r.defaults["roll"] = "A001"; r.defaults["mag"] = "Demo SSD 01"
        r.defaults["camera"] = "A"; r.defaults["lens"] = "24mm"
        for take in 1...3 {
            let id = r.next(scene:"3A",device:"Built-in demo fixture")
            let i = r.entries.firstIndex{$0.id == id}!
            r.entries[i].values["sharedSceneId"] = "55b74db4-37dc-582c-b730-b0385b83de6c"
            r.entries[i].values["sharedShotId"] = "5cae5786-9218-597d-a7c0-e6bef7af8dcd"
            r.entries[i].values["remarks"] = "FICTIONAL DEMO · 3A · Station wagon stops at the foot of the lighthouse; Jonah waits. Wide, static, tripod."
            r.entries[i].values["continuity"] = "Jonah holds the brass key while Maya approaches. Match the handover in planned shot 3B."
            r.entries[i].values["dpNotes"] = take == 2 ? "Circle 2 — same fictional select as Production Desk and Scenic." : "Preserve soft coastal light; fictional camera settings only."
            r.entries[i].values["sound"] = "DEMO-S001 / 3A-take-\(take)"
            r.entries[i].reviewed = true
            if take == 2 { r.entries[i].flags.insert("Circle") }
        }
        r.record("Created fictional The Last Light report from shared fixture revision 1.",device:"Built-in demo fixture")
        return r
    }
}
