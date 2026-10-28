# Route-to-wristband navigation plan

Saved October 17, 2026. This records the agreed navigation behavior and tracks
which parts are implemented versus still planned.

## Resume here

The user resumed navigation implementation on October 27, 2026, and selected a
foreground field-trial slice: map maneuvers to existing vibration commands and
send the action cue near each supported turn. The first field run found slow
progress updates and that guidance paused after a missed cue. The working tree
now requests location updates at a 1 m distance filter, tolerates longer gaps
using fix timing and reported speed, and requests a reroute after three usable
off-route fixes spanning five seconds. Passing a turn point alone no longer
pauses guidance. The next field run was reported as "very very good," with cues
possibly a few steps early. Treat that as a cue-distance tuning observation, not
a reason to move the cue to the exact intersection. Rerouting was exercised in
the field; background operation, repeated tests, and cue-distance tuning remain
pending. Do not assume other deferred behavior is implemented.

Completed prerequisite work:

- Independent left/right connections using one Bluetooth central manager.
- Separate connection, test, and stop controls; Left / Right / Both manual tests.
- A `wristband-right` PlatformIO build advertising `PathPulse-Right`, with the
  default build continuing to advertise `PathPulse-Left`.
- Existing commands 0–8 and motor patterns preserved.
- iOS simulator build passed. After installing Rosetta to run the installed
  Intel ESP32 compiler, left, right, and vibration-test firmware builds passed.
- Physical two-wristband testing remains pending; the right band was unavailable.

Before implementation, inspect current code and git status again. Do not assume
the prerequisite changes have been committed or pushed.

## Agreed user experience

- The iPhone tracks route progress; wristbands only play commands.
- A distinct advance cue announces an upcoming maneuver; existing directional
  patterns cue the maneuver near its location.
- Confirmed departure from the route triggers automatic rerouting.
- Guidance must work while the phone is locked in a pocket.
- Both compatible wristbands are required. Losing either pauses directional cues.
- Unsupported maneuvers pause guidance and require explicit user action to resume.
- Waiting near a turn is not a missed turn. Uncertain positioning must not be
  treated as completed or missed.

## Maneuver mapping

Preserve raw API values and explicitly classify all documented Google maneuvers.
Never turn an unknown value into a straight instruction.

| API maneuver | Behavior |
|---|---|
| `TURN_LEFT/RIGHT` | Command 1 on the corresponding wrist |
| `TURN_SLIGHT_LEFT/RIGHT`, `FORK_LEFT/RIGHT` | Command 2 on the corresponding wrist |
| `TURN_SHARP_LEFT/RIGHT` | Command 5 on the corresponding wrist |
| `STRAIGHT` | Command 3 on both wrists at explicit straight maneuvers |
| `DEPART` | Establish movement along the initial segment; no immediate directional cue |
| `NAME_CHANGE` | Track progress without a vibration |
| `UTURN_LEFT/RIGHT` | Unsupported initially; command 6 stays manual-test-only |
| `RAMP_LEFT/RIGHT`, `MERGE`, `ROUNDABOUT_LEFT/RIGHT`, `FERRY`, `FERRY_TRAIN`, `MANEUVER_UNSPECIFIED`, unknown values | Unsupported initially |

Add command **9**, one **200 ms pulse**, for advance notice on the corresponding
wrist (both for an explicit straight maneuver). Validate perceptual distinction
from the existing 400 ms slight-turn pulse on mounted wristbands.

Arrival is command 4 on both wrists after confirmed endpoint progress, not an
API maneuver mapping. Retain command 8 obstacle priority and command 0 stop.

Add a readable protocol-version characteristic so the app can reject firmware
without command 9 support. Update firmware validation, testing controls, and the
protocol documentation together. The exact characteristic UUID/version encoding
still needs to be fixed during implementation preparation; it was not selected
in this discussion.

Reference: https://googleapis.dev/python/routing/latest/_modules/google/maps/routing_v2/types/maneuver.html

## Progress tracker

Keep a testable tracker separate from UI, location acquisition, and Bluetooth.

- Associate a maneuver with the **start of its step**; the step geometry is its
  outgoing path.
- Match fixes against nearby segments in route order, considering position,
  accuracy, recent movement, and continuity. Avoid jumping to distant later
  sections at route crossings or loops.
- Measure remaining distance along the route, not straight-line distance through
  corners or buildings.
- Phone orientation alone does not establish that the wearer turned. Movement
  along the outgoing route is the principal completion evidence.

| State | Evidence |
|---|---|
| Upcoming | Approaching along the expected incoming path |
| At maneuver | Within the action zone with unambiguous enough positioning |
| Completed | Sustained progress onto the expected outgoing path |
| Missed/off-route | Sustained movement inconsistent with the expected route |
| Uncertain | Location cannot distinguish the expected path from alternatives |

Initial configurable outdoor-trial defaults, not validated accuracy guarantees:

- Advance cue once at 25 m; action cue at 10 m.
- Repeat action cues at most once every 8 seconds while confidently at the maneuver.
- Directional decisions require fixes at most 5 seconds old and horizontal
  accuracy at most 10 m. These gates alone do not establish confidence.
- Completion requires at least three fixes spanning three seconds, outgoing
  progress greater than `max(10 m, horizontal accuracy)`, and no similarly
  plausible competing segment.
- Off-route confirmation requires at least three usable fixes spanning five
  seconds outside a corridor of `max(15 m, 2 × horizontal accuracy)` around the
  locally expected route.
- Arrival requires three usable fixes on the final segment within 10 m of the
  route endpoint.
- Omit advance notice when entering directly into the action zone. Do not stack
  delayed cues. Closely spaced or ambiguous turns pause rather than being skipped.

## Session and recovery

- Add an app-owned navigation session shared with Bluetooth and navigation views.
- Introduce typed maneuver dispositions, haptic commands, wrist recipients,
  progress states, and configurable thresholds.
- Reuse the new dual-wrist Bluetooth service. Provide identification vibrations
  and prevent one peripheral from being assigned to both wrists. The implemented
  prerequisite currently assigns wrists by exact advertised name.
- Serialize writes per wrist and discard obsolete pending cues. A GATT response
  confirms transport receipt, not motor playback. Disable manual tests during
  active guidance.
- On disconnection, stop directional playback on the remaining wrist, send
  command 7 (guidance unavailable), and attempt reconnection to the assigned band.
  Resume only after both connections and current route position are validated.
- On uncertain location, pause and signal unavailable once. Resume after
  consistent usable fixes.
- On confirmed off-route movement, invalidate old cues and route from the current
  location. Allow one request at a time with a minimum ten-second retry interval.
  Stay paused on failure. Receiving a new route alone must not trigger a U-turn.
- Display unsupported maneuvers before starting. Pause and send command 7 when
  approaching one. An explicit “Resume guidance” action requests a fresh route
  from the current position instead of blindly skipping the step.
- Ending navigation cancels routing requests, clears cues, stops motors, and ends
  continuous location updates.
- Replace the current coordinate-driven route reload behavior: continuous fixes
  update progress, rather than requesting a new route on every fix.
- Add session-based background location and `bluetooth-central` support.
  App termination ends guidance; restarting requires an explicit new session.

Apple references:

- https://developer.apple.com/documentation/corelocation/handling-location-updates-in-the-background
- https://developer.apple.com/library/archive/documentation/NetworkingInternetWeb/Conceptual/CoreBluetooth_concepts/CoreBluetoothBackgroundProcessingForIOSApps/PerformingTasksWhileYourAppIsInTheBackground.html

## Validation and boundaries

Automated scenarios: all maneuver mappings, successful and missed turns,
stationary users, GPS drift, stale fixes, closely spaced turns, route crossings,
arrival, rerouting failures, disconnections, and stale command cancellation.

Physical scenarios: wrist identity, bilateral delivery, advance-pulse recognition,
locked-phone updates and cues, reconnection, turns, missed turns, crossing waits,
unsupported-step recovery, stop behavior, and obstacle interruption.

Initial orientation requires walking enough to establish travel direction. No new
obstacle sensing is included; preserve existing obstacle priority. Describe the
system as providing navigation cues and obstacle warnings. Follow AGENTS.md,
including documentation immediately above every new or modified function.
