import Foundation

/// The reminder lines (`WorkoutBanter`). All original. The rules they follow
/// are checked on every line by the tests (`WorkoutBanterGuard`):
///
/// - The joke is on the barbell, the plates, the plan or the app itself,
///   never on the person. Nothing about bodies, body weight, food or looks;
///   no guilt, shame or "should"; nothing about training through illness or pain.
/// - Every number comes from a slot, so nothing is said that the data doesn't hold.
/// - A line's id never changes once shipped (the history is kept by id); new
///   lines get new ids, and a retired line's id is not reused.
/// - `plain` lines carry the Plain tone and every caution state, where the
///   reminder must not push to train.
///
/// Funny is a matter of taste, not evidence: these were written to the
/// owner's brief (see docs/research/funny-nudges-2026-11.md) and are meant to
/// be edited after real use.
public enum WorkoutBanterLibrary {
    typealias L = WorkoutBanter.Line

    public static let all: [WorkoutBanter.Line] =
        planned + shortOption + nearRecord + stuckLift + comeback + longBreak + weekStart + weekProgress + lastOfWeek
        + weeksInARow + neglectedMuscle + afterRecord + afterVolume + deload + highRecovery
        + morning + evening + monday + friday + weekend + lastCall + plain + caution

    /// The lines with a comic register (everything but `plain`).
    public static var playful: [WorkoutBanter.Line] { all.filter { $0.register != .plain } }

    // MARK: A planned session (always fits)

    static let planned: [L] = [
        L("pl01", .planned, .deadpan, "{session} in {lead} minutes. The barbell has cleared its schedule."),
        L("pl02", .planned, .deadpan, "{session} starts in {lead} minutes. The plates have been told to act natural."),
        L("pl03", .planned, .deadpan, "{session}, {minutes} minutes, starting soon. The rack has no other plans. It never does."),
        L("pl04", .planned, .deadpan, "{session} in {lead} minutes. The dumbbells are pretending they haven't been waiting."),
        L("pl05", .planned, .deadpan, "Your {weekday} {session} is in {lead} minutes. The gym floor has been briefed."),
        L("pl06", .planned, .deadpan, "{session} is {lead} minutes away. The chalk is nervous. It gets like this."),
        L("pl07", .planned, .deadpan, "The barbell asked whether {session} is still on. I said I'd check. This is me checking."),
        L("pl08", .planned, .deadpan, "{session} in {lead} minutes. The bench is saving you a spot, which is easy, because it's a bench."),
        L("pl09", .planned, .absurd, "{session} in {lead} minutes. A kettlebell has started a rumour that you're coming. Awkward if it's wrong."),
        L("pl10", .planned, .absurd, "The plates held a meeting about {session}. The vote was unanimous. Plates only have one opinion."),
        L("pl11", .planned, .absurd, "{session} in {lead} minutes. Somewhere a barbell is practising looking heavy."),
        L("pl12", .planned, .absurd, "Gravity is still switched on. {session} in {lead} minutes is a chance to test it."),
        L("pl13", .planned, .absurd, "{session} in {lead} minutes. The dumbbells have lined up by size to impress you. They do this every day."),
        L("pl14", .planned, .absurd, "Breaking: local barbell 'cautiously optimistic' about {session} in {lead} minutes."),
        L("pl15", .planned, .absurd, "{session} soon. The cable machine has been untangling itself, emotionally, since yesterday."),
        L("pl16", .planned, .absurd, "The gym playlist has picked a song for your opening set of {session}. It won't say which. {lead} minutes."),
        L("pl17", .planned, .mockHeroic, "In {lead} minutes, {session}. Bards will sing of it. Short songs, mostly about sets and rest timers."),
        L("pl18", .planned, .mockHeroic, "The prophecy speaks of {session}, {lead} minutes hence. The prophecy is your weekly plan. Still counts."),
        L("pl19", .planned, .mockHeroic, "Hero, {session} awaits in {lead} minutes. Your quest: pick things up. Your side quest: put them down."),
        L("pl20", .planned, .mockHeroic, "{weekday}. {session}. {minutes} minutes. History will record it, because you log everything."),
        L("pl21", .planned, .mockHeroic, "The iron summons you to {session} in {lead} minutes. It summons politely. It's iron, not a monster."),
        L("pl22", .planned, .mockHeroic, "Sound the horns: {session} in {lead} minutes. There are no horns. I checked the settings."),
        L("pl23", .planned, .selfAware, "I'm an app reminding you about {session} in {lead} minutes. We both know how this works. I'll be brief."),
        L("pl24", .planned, .selfAware, "This is your {session} reminder. I was asked to be funny about it. No pressure on either of us."),
        L("pl25", .planned, .selfAware, "{session} in {lead} minutes. I'd come along, but I'm a notification, and my whole career is this sentence."),
        L("pl26", .planned, .selfAware, "Reminder: {session}, {lead} minutes. I wrote several jokes for this and was told to pick one. This was it."),
        L("pl27", .planned, .selfAware, "{session} in {lead} minutes. I have no arms, so the lifting part is yours. I'll handle the counting."),
        L("pl28", .planned, .selfAware, "Me again. {session}, {lead} minutes. I only get to say this once today, so I chose my words carefully. These were them."),
        L("pl29", .planned, .selfAware, "{session} in {lead} minutes. If you go, I get to draw a chart. I love drawing charts. That's not a hint. It's a small hint."),
        L("pl30", .planned, .selfAware, "Your phone buzzed for {session}. That was me. Hello. {lead} minutes."),
        L("pl31", .planned, .gymBro, "{session} in {lead} minutes. LET'S GO. (Indoor voice: let's go, when convenient.)"),
        L("pl32", .planned, .gymBro, "Bro. {session}. {lead} minutes. The barbell says it's 'literally so ready'. Its words."),
        L("pl33", .planned, .gymBro, "{session} in {lead} minutes. Full send. Or a sensible send. A send of your choosing."),
        L("pl34", .planned, .gymBro, "It's {session} o'clock in {lead} minutes, bro. The plan has picked the numbers; you just bring the hands."),
        L("pl35", .planned, .gymBro, "{session}, {lead} minutes. Certified send-it window. Chalk optional, enthusiasm optional, showing up counts."),
        L("pl36", .planned, .gymBro, "Big {weekday} energy: {session} in {lead} minutes. The barbell already did its warm-up. Show-off."),
        L("pl37", .planned, .understatement, "{session} in {lead} minutes. It'll be fine. Possibly even good."),
        L("pl38", .planned, .understatement, "{session} soon. Reviews of previous sessions: 'not bad', 'would lift again'."),
        L("pl39", .planned, .understatement, "{session} has your name on it in {lead} minutes. Small event. Short guest list. Mostly barbells."),
        L("pl40", .planned, .understatement, "{session}, {minutes} minutes. As plans go, it's a decent one."),
        L("pl41", .planned, .understatement, "{session} in {lead} minutes. Nothing dramatic. Just you, some iron and mild heroics."),
        L("pl42", .planned, .bureaucratic, "Notice: {session} is scheduled in {lead} minutes. Attendance is optional. The barbell has filed its paperwork."),
        L("pl43", .planned, .bureaucratic, "Per your own weekly plan, section {weekday}: {session}, {minutes} minutes. Signed, you, earlier this week."),
        L("pl44", .planned, .bureaucratic, "A courtesy call from the Department of {session}: your appointment is in {lead} minutes. No forms."),
        L("pl45", .planned, .bureaucratic, "Agenda for {weekday}: item A, {session}. Item B, feeling pleased about item A. Starts in {lead} minutes."),
        L("pl46", .planned, .bureaucratic, "The committee (you, on planning day) approved {session} for today. Motion carries in {lead} minutes."),
        L("pl47", .planned, .natureDoc, "In {lead} minutes, the lifter approaches the rack. The barbell, sensing {session}, holds perfectly still."),
        L("pl48", .planned, .natureDoc, "Here we observe a {weekday} {session} in its natural habitat: {lead} minutes from now, near the squat rack."),
        L("pl49", .planned, .natureDoc, "The dumbbells gather at the watering hole. In {lead} minutes, {session} begins. Nature is extraordinary."),
        L("pl50", .planned, .natureDoc, "Rarely seen in the wild: a plan followed on a {weekday}. A sighting is expected in {lead} minutes. {session}."),
        // No slots: these fit any day, so there is always a line to send.
        L("pl51", .planned, .deadpan, "Your session starts soon. The barbell has been informed and is taking it well."),
        L("pl52", .planned, .selfAware, "Session soon. I'd say more, but I'm a notification and brevity is the job."),
        L("pl53", .planned, .absurd, "The plates are stacked, the rack is ready, and somewhere a kettlebell believes in you. Session soon."),
    ]

    // MARK: The short version

    static let shortOption: [L] = [
        L("so01", .shortOption, .deadpan, "{session} in {lead} minutes. There's a {short}-minute version too. The barbell won't notice. It can't tell time."),
        L("so02", .shortOption, .understatement, "{session} soon. Full version: {minutes} minutes. Short version: {short}. Both end with you having trained."),
        L("so03", .shortOption, .selfAware, "{session} in {lead} minutes. If today's a mess, the {short}-minute version exists. I'm allowed to call that a workout."),
        L("so04", .shortOption, .absurd, "The {short}-minute version of {session} has asked me to mention it exists. It feels overlooked. {lead} minutes."),
        L("so05", .shortOption, .gymBro, "{session} in {lead} minutes. Not feeling the full {minutes}? {short} minutes. Speedrun. Still counts, bro."),
        L("so06", .shortOption, .bureaucratic, "Per the small print of your plan, {session} may be completed in {short} minutes. Offer opens in {lead} minutes."),
        L("so07", .shortOption, .mockHeroic, "{session} in {lead} minutes. Choose your quest: the {minutes}-minute saga, or the {short}-minute short story."),
        L("so08", .shortOption, .natureDoc, "The {short}-minute session: small, quick, often underestimated. It appears in {lead} minutes, beside the full {session}."),
        L("so09", .shortOption, .deadpan, "{session}, {lead} minutes. {minutes} minutes if the day is kind, {short} if it isn't. The plan allows both."),
        L("so10", .shortOption, .understatement, "The {short}-minute {session} is still {session}. That's not motivation, just arithmetic. Starts in {lead} minutes."),
    ]

    // MARK: A lift within reach of a new best

    static let nearRecord: [L] = [
        L("nr01", .nearRecord, .deadpan, "Your {lift} did {last} last time. {next} is right there, looking at you. It's not blinking."),
        L("nr02", .nearRecord, .absurd, "Last time: {lift}, {last}. The {next} plates have been rehearsing their big scene."),
        L("nr03", .nearRecord, .mockHeroic, "{Lift}: {last} last time. Beyond it lies {next}, a land no log of yours has charted."),
        L("nr04", .nearRecord, .gymBro, "{Lift}: {last} last time. Next stop {next}, bro. The barbell's already writing its speech."),
        L("nr05", .nearRecord, .understatement, "Your {lift} is a small step from a new best: {last} last time, {next} next. No big deal. Slightly big deal."),
        L("nr06", .nearRecord, .selfAware, "I ran the numbers. {Lift}: {last} last time; {next} would be new. I don't get excited. I'm a little excited."),
        L("nr07", .nearRecord, .bureaucratic, "Records office: your {lift} file shows {last}. An update to {next} can be processed in person, at the bar."),
        L("nr08", .nearRecord, .natureDoc, "The lifter last moved {last} on the {lift}. Observers believe {next} is close. We watch from a respectful distance."),
        L("nr09", .nearRecord, .deadpan, "{Lift}, {last}. Then {next}. That's the whole plan. Good plans are boring."),
        L("nr10", .nearRecord, .absurd, "{next} on the {lift} has been waiting so long it's started a podcast. You did {last} last time. Go be a guest."),
    ]

    // MARK: A lift that has sat at one weight

    static let stuckLift: [L] = [
        L("st01", .stuckLift, .absurd, "Your {lift} has been at {lastWeight} for {stuckWeeks} weeks. It's started telling people it's a personality trait."),
        L("st02", .stuckLift, .deadpan, "{Lift}: {lastWeight}, {stuckWeeks} weeks running. By now the plates know each other's birthdays."),
        L("st03", .stuckLift, .absurd, "Your {lift} has stayed at {lastWeight} for {stuckWeeks} weeks. The bar is thinking of putting up shelves."),
        L("st04", .stuckLift, .understatement, "{stuckWeeks} weeks at {lastWeight} on the {lift}. Consistent. Extremely consistent. A rep more would also be fine."),
        L("st05", .stuckLift, .mockHeroic, "For {stuckWeeks} weeks the {lift} has held the line at {lastWeight}. A noble stalemate. Today, perhaps, a rep more."),
        L("st06", .stuckLift, .selfAware, "My chart of your {lift} is a flat line at {lastWeight}, {stuckWeeks} weeks long. No judgement. I'd just like to draw a new bit."),
        L("st07", .stuckLift, .gymBro, "{Lift} at {lastWeight} for {stuckWeeks} weeks. Plateaus are just flat records, bro. Add a rep and we ride."),
        L("st08", .stuckLift, .bureaucratic, "Your {lift} has been resident at {lastWeight} for {stuckWeeks} weeks and now qualifies for a postal address."),
        L("st09", .stuckLift, .natureDoc, "The {lift} has rested at {lastWeight} for {stuckWeeks} weeks. Plateaus are common in this habitat. They pass."),
        L("st10", .stuckLift, .deadpan, "{stuckWeeks} weeks of {lastWeight} on the {lift}. The plates and the bar are on first-name terms. An extra rep would make it awkward. Good."),
    ]

    // MARK: Back after a few days (4–14: the number is said, never as a reproach)

    static let comeback: [L] = [
        L("cb01", .comeback, .deadpan, "It's been {days} days. The barbell hasn't moved. To be fair, that's its whole thing."),
        L("cb02", .comeback, .absurd, "{days} days since your last session. The dumbbells have started a book club. They'd drop it for you."),
        L("cb03", .comeback, .selfAware, "{days} days since we logged anything. I've been practising this notification. How was it? {session} in {lead} minutes."),
        // Little is lost in a break this short (Mujika & Padilla, Sports Med 2000, via behaviour-change.md).
        L("cb04", .comeback, .understatement, "{days} days off. Fitness doesn't evaporate that fast. {session} in {lead} minutes, if today suits."),
        L("cb05", .comeback, .mockHeroic, "After {days} days, the hero returns. Or doesn't. Heroes get days off too. {session} in {lead} minutes."),
        L("cb06", .comeback, .gymBro, "{days} days of rest, bro. You're basically fully charged. {session} in {lead} minutes."),
        L("cb07", .comeback, .bureaucratic, "Your {days}-day leave has been approved retroactively. {session} resumes in {lead} minutes, at your discretion."),
        L("cb08", .comeback, .natureDoc, "After {days} days away, the lifter may return to the rack. The barbell, a patient creature, has not moved."),
        L("cb09", .comeback, .deadpan, "{days} days. The gym is where you left it. {session} in {lead} minutes."),
        L("cb10", .comeback, .absurd, "In the {days} days since your last session, a kettlebell tried to learn your job. It can't lift itself. {session}, {lead} minutes."),
    ]

    // MARK: Back after a long break (15+ days: no number, no reproach)

    static let longBreak: [L] = [
        L("lb01", .longBreak, .understatement, "It's been a while. The plan still works. {session} in {lead} minutes, or the short version, or just a look around."),
        L("lb02", .longBreak, .deadpan, "The barbell remembers you. It has an excellent memory and no other hobbies. {session}, {lead} minutes."),
        L("lb03", .longBreak, .selfAware, "I'm not going to mention how long it's been. I'm an app; I'd only get the tone wrong. {session} in {lead} minutes."),
        L("lb04", .longBreak, .absurd, "The gym has kept your spot. It doesn't know how to do anything else. {session} in {lead} minutes."),
        L("lb05", .longBreak, .mockHeroic, "Every saga has a quiet chapter. The next page says {session}, {lead} minutes. Turning it is optional."),
        L("lb06", .longBreak, .bureaucratic, "Your account with the barbell remains in good standing. No fees, no forms. {session} in {lead} minutes."),
        L("lb07", .longBreak, .natureDoc, "After a long season away, the lifter considers a return. There is no wrong moment. {session}, {lead} minutes."),
        L("lb08", .longBreak, .gymBro, "Comebacks are the best arc, bro. Episode {session} airs in {lead} minutes. Start light, credits roll."),
    ]

    // MARK: The week

    static let weekStart: [L] = [
        L("ws01", .weekStart, .deadpan, "First of {planned} this week: {session} in {lead} minutes. The barbell has agreed to go first."),
        L("ws02", .weekStart, .mockHeroic, "The week opens. {planned} sessions stand before you. The first, {session}, falls in {lead} minutes."),
        L("ws03", .weekStart, .bureaucratic, "Weekly ledger: {planned} planned, none logged yet. First entry opens in {lead} minutes: {session}."),
        L("ws04", .weekStart, .gymBro, "New week, {planned} sessions on the board. {session} tips off in {lead} minutes. Opening day, bro."),
        L("ws05", .weekStart, .selfAware, "My weekly chart is empty and I find blank charts unsettling. That's my problem. {session}, {lead} minutes; {planned} planned."),
        L("ws06", .weekStart, .understatement, "{planned} sessions this week. This would be the first. Modest beginnings. {session}, {lead} minutes."),
        L("ws07", .weekStart, .natureDoc, "The week is young. Of {planned} planned sessions, none has yet been seen. The first stirs in {lead} minutes: {session}."),
        L("ws08", .weekStart, .absurd, "This week's {planned} sessions drew straws. {session} goes first, in {lead} minutes. It's being very brave about it."),
    ]

    static let weekProgress: [L] = [
        L("wp01", .weekProgress, .deadpan, "{done} of {planned} done this week. {session} would make it tidier. {lead} minutes."),
        L("wp02", .weekProgress, .understatement, "{done} down, {left} to go this week. Not that anyone's counting. I'm counting. {session} in {lead} minutes."),
        L("wp03", .weekProgress, .mockHeroic, "{done} of {planned} conquered; {left} remain. Next on the field: {session}, in {lead} minutes."),
        L("wp04", .weekProgress, .gymBro, "{done} of {planned} this week. Scoreboard's looking clean, bro. {session} in {lead} minutes."),
        L("wp05", .weekProgress, .selfAware, "You've done {done} of {planned} this week. I keep the tally; it's the only maths I'm trusted with. {session}, {lead} minutes."),
        L("wp06", .weekProgress, .bureaucratic, "Weekly ledger: {done} of {planned} logged, {left} outstanding. Next entry opens in {lead} minutes: {session}."),
        L("wp07", .weekProgress, .natureDoc, "Field notes: {done} of this week's {planned} sessions sighted so far. The next, {session}, is expected in {lead} minutes."),
        L("wp08", .weekProgress, .absurd, "This week's sessions are a set of {planned}. You have {done}. Collectors would call {session} essential. {lead} minutes."),
        L("wp09", .weekProgress, .deadpan, "{done} of {planned}. {session} in {lead} minutes. The maths is on your side."),
        L("wp10", .weekProgress, .understatement, "Week so far: {done} of {planned}. Respectable. {session} in {lead} minutes would make it more so."),
    ]

    static let lastOfWeek: [L] = [
        L("lw01", .lastOfWeek, .mockHeroic, "{done} of {planned} done. A single session stands between you and a finished week: {session}, {lead} minutes."),
        L("lw02", .lastOfWeek, .deadpan, "Last session of the week: {session}, {lead} minutes. After that the plan has nothing left to say."),
        L("lw03", .lastOfWeek, .gymBro, "Final boss of the week: {session}, {lead} minutes. {done} of {planned} already in the bag, bro."),
        L("lw04", .lastOfWeek, .understatement, "{session} would make it {planned} of {planned} this week. That's all of them. Just noting it."),
        L("lw05", .lastOfWeek, .selfAware, "The week's last planned session: {session}, {lead} minutes. After it I get to draw a full row. I'd like that."),
        L("lw06", .lastOfWeek, .bureaucratic, "Final item on this week's agenda: {session}, in {lead} minutes. After that the committee adjourns."),
        L("lw07", .lastOfWeek, .natureDoc, "The week's last session emerges in {lead} minutes: {session}. Then the herd rests."),
        L("lw08", .lastOfWeek, .absurd, "The week has {planned} boxes and {done} ticks. The last box has been eyeing {session} all day. {lead} minutes."),
    ]

    // MARK: Weeks on plan in a row (only while the run stands; never what could be lost)

    static let weeksInARow: [L] = [
        L("wr01", .weeksInARow, .deadpan, "{weeks} weeks in a row on plan. {session} in {lead} minutes. The barbell has stopped being surprised."),
        L("wr02", .weeksInARow, .understatement, "{weeks} weeks on plan in a row. Some would call that a habit. I'd never be so bold. {session}, {lead} minutes."),
        L("wr03", .weeksInARow, .mockHeroic, "{weeks} weeks the plan has held. Scholars are taking notes. {session} in {lead} minutes."),
        L("wr04", .weeksInARow, .gymBro, "{weeks} weeks on plan, bro. That's not a phase, that's a schedule. {session} in {lead} minutes."),
        L("wr05", .weeksInARow, .selfAware, "{weeks} weeks on plan. I'd give you a badge, but this app doesn't do badges. Have a sincere nod. {session}, {lead} minutes."),
        L("wr06", .weeksInARow, .bureaucratic, "For {weeks} consecutive weeks your plan has been filed on time. The office is impressed. {session} in {lead} minutes."),
        L("wr07", .weeksInARow, .natureDoc, "For {weeks} weeks the lifter has returned on schedule. Researchers now set their clocks by it. {session}, {lead} minutes."),
        L("wr08", .weeksInARow, .absurd, "{weeks} weeks on plan. The dumbbells have named a rack after you. It's the same rack. {session} in {lead} minutes."),
    ]

    // MARK: A muscle group without a set for a while (about training, never about looks)

    static let neglectedMuscle: [L] = [
        L("nm01", .neglectedMuscle, .deadpan, "{muscleDays} days since your {muscle} last saw a working set. No alarm. Just a diary entry."),
        L("nm02", .neglectedMuscle, .absurd, "It's been {muscleDays} days since any {muscle} work. Word is, a postcard has been drafted. {session} in {lead} minutes."),
        L("nm03", .neglectedMuscle, .selfAware, "My notes say {muscleDays} days since any {muscle} work. I keep notes. It's most of my personality."),
        L("nm04", .neglectedMuscle, .understatement, "{muscleDays} days without {muscle} work. Not a crisis. A footnote. {session} in {lead} minutes."),
        L("nm05", .neglectedMuscle, .bureaucratic, "Records show no {muscle} sets filed in {muscleDays} days. The department accepts walk-ins. {session}, {lead} minutes."),
        L("nm06", .neglectedMuscle, .natureDoc, "{muscleDays} days have passed since any {muscle} training was observed. Naturalists call this a gap in the schedule."),
        L("nm07", .neglectedMuscle, .mockHeroic, "{muscleDays} days since {muscle} training. The tale isn't over; it's between chapters. {session}, {lead} minutes."),
        L("nm08", .neglectedMuscle, .gymBro, "{muscleDays} days since {muscle} day, bro. No stress. The plan knows. {session} in {lead} minutes."),
    ]

    // MARK: After a record or a big session

    static let afterRecord: [L] = [
        L("ar01", .afterRecord, .deadpan, "Last session you set a new best on the {standoutLift}. The bar is still telling the other bars."),
        L("ar02", .afterRecord, .understatement, "A new {standoutLift} best last time. Quite good. {session} in {lead} minutes, no encore required."),
        L("ar03", .afterRecord, .mockHeroic, "Word of your {standoutLift} record has reached the far racks. {session} in {lead} minutes. The legend may rest or continue."),
        L("ar04", .afterRecord, .gymBro, "New {standoutLift} best last session. Certified moment, bro. {session} in {lead} minutes."),
        L("ar05", .afterRecord, .selfAware, "I logged your {standoutLift} record last time and told no one, because I'm an app. Until now. {session}, {lead} minutes."),
        L("ar06", .afterRecord, .bureaucratic, "Your {standoutLift} record has been entered in the permanent file. Further submissions accepted in {lead} minutes: {session}."),
        L("ar07", .afterRecord, .natureDoc, "Fresh from a record on the {standoutLift}, the lifter approaches {session}. Expectations are, wisely, normal."),
        L("ar08", .afterRecord, .absurd, "Your {standoutLift} record is being very modest about it. The plates are not. {session} in {lead} minutes."),
    ]

    static let afterVolume: [L] = [
        L("av01", .afterVolume, .deadpan, "Last session you moved {volume} in total. The floor has confirmed it all came back down."),
        L("av02", .afterVolume, .absurd, "{volume} lifted last session. That's a lot of something. I didn't check what. {session}, {lead} minutes."),
        L("av03", .afterVolume, .understatement, "{volume} moved last session, your most in a while. A reasonable day's work. {session} in {lead} minutes."),
        L("av04", .afterVolume, .selfAware, "I added up last session: {volume}. Adding up is my cardio. {session} in {lead} minutes."),
        L("av05", .afterVolume, .mockHeroic, "{volume} raised and lowered in a single session. The plates speak of it still. {session}, {lead} minutes."),
        L("av06", .afterVolume, .gymBro, "{volume} total last session, bro. Big day. {session} in {lead} minutes; a normal day is allowed."),
        L("av07", .afterVolume, .bureaucratic, "Freight report: {volume} moved last session, all returned to the rack. Next shipment: {session}, {lead} minutes."),
    ]

    // MARK: Deload week (the joke is about going light, never about going heavy)

    static let deload: [L] = [
        L("dl01", .deload, .deadpan, "Deload week. The plan says light, on purpose. {session} in {lead} minutes. The barbell has been told to calm down."),
        L("dl02", .deload, .understatement, "It's a lighter week by design. {session} in {lead} minutes. Leave some in the tank; that's the assignment."),
        L("dl03", .deload, .gymBro, "Deload week, bro. Light is the mission. The hardest part is not adding plates. {session}, {lead} minutes."),
        L("dl04", .deload, .mockHeroic, "Even legends have a quiet week. This is it. {session} in {lead} minutes, at a dignified, lighter pace."),
        L("dl05", .deload, .selfAware, "Deload week: I'm under instructions not to hype you up. {session} in {lead} minutes. Go gently. Woo, quietly."),
        L("dl06", .deload, .bureaucratic, "By order of the plan, this week's loads are reduced. {session} in {lead} minutes. Heroics are postponed."),
        L("dl07", .deload, .natureDoc, "In the deload week the lifter moves lighter loads and conserves energy. A wise adaptation. {session}, {lead} minutes."),
        L("dl08", .deload, .absurd, "Deload week. The heavy plates have the week off and are being smug about it. {session} in {lead} minutes."),
    ]

    // MARK: High recovery (the app's own estimate, so no number and no promise)

    static let highRecovery: [L] = [
        L("hr01", .highRecovery, .deadpan, "Recovery is high today. {session} in {lead} minutes. Convenient timing, that."),
        L("hr02", .highRecovery, .gymBro, "Recovery's high, bro. Green lights everywhere. {session} in {lead} minutes."),
        L("hr03", .highRecovery, .understatement, "Recovery came in high. Could be a decent day for {session}. {lead} minutes."),
        L("hr04", .highRecovery, .selfAware, "Your recovery is high. I don't have feelings about data, officially. {session} in {lead} minutes."),
        L("hr05", .highRecovery, .mockHeroic, "The omens are good: recovery is high. {session} in {lead} minutes. The omens are a sensor on your wrist."),
        L("hr06", .highRecovery, .natureDoc, "Well rested, by the numbers, the lifter greets the day. Recovery reads high. {session} approaches in {lead} minutes."),
        L("hr07", .highRecovery, .absurd, "High recovery today. The barbell heard and has gone a bit quiet. {session} in {lead} minutes."),
    ]

    // MARK: Time of day and day of the week

    static let morning: [L] = [
        L("mo01", .morning, .deadpan, "{session} in {lead} minutes. The gym is quiet this early. Even the barbells are whispering."),
        L("mo02", .morning, .absurd, "Morning. The dumbbells are up. They don't sleep; it's a whole thing. {session} in {lead} minutes."),
        L("mo03", .morning, .selfAware, "It's early and I'm a notification, so we're both doing our best. {session} in {lead} minutes."),
        L("mo04", .morning, .mockHeroic, "Dawn. The rack stands ready. {session} in {lead} minutes. Yawning is permitted."),
        L("mo05", .morning, .understatement, "A morning {session}. Bold. {lead} minutes."),
        L("mo06", .morning, .gymBro, "Early session, bro. Sun's barely clocked in. {session} in {lead} minutes."),
    ]

    static let evening: [L] = [
        L("ev01", .evening, .deadpan, "{session} in {lead} minutes. The day had its turn. This part's yours."),
        L("ev02", .evening, .absurd, "Evening. The barbell has had all day to think and has thought of nothing. {session} in {lead} minutes."),
        L("ev03", .evening, .understatement, "An evening {session}. A calm end to the day, with barbells. {lead} minutes."),
        L("ev04", .evening, .mockHeroic, "As the sun sets, {session} rises. {lead} minutes. Very cinematic. Bring a towel."),
        L("ev05", .evening, .selfAware, "Last thing from me today: {session} in {lead} minutes. After that I go back to being an icon."),
        L("ev06", .evening, .natureDoc, "At dusk the lifter emerges. In {lead} minutes, {session}. The rack is lit and waiting."),
    ]

    static let monday: [L] = [
        L("mn01", .monday, .deadpan, "Monday. {session} in {lead} minutes. The week has to start somewhere; the rack volunteered."),
        L("mn02", .monday, .absurd, "It's Monday and the plates have that fresh-week look. {session} in {lead} minutes."),
        L("mn03", .monday, .gymBro, "Monday, bro. Week's wide open. {session} in {lead} minutes."),
        L("mn04", .monday, .bureaucratic, "The week is now in session. First order of business: {session}, {lead} minutes."),
        L("mn05", .monday, .understatement, "Mondays have a reputation. {session} in {lead} minutes could do something about that."),
    ]

    static let friday: [L] = [
        L("fr01", .friday, .deadpan, "Friday. {session} in {lead} minutes. Then the weekend, which the barbell doesn't get."),
        L("fr02", .friday, .gymBro, "Friday {session}, {lead} minutes. Send the week off properly, bro."),
        L("fr03", .friday, .mockHeroic, "Friday: the week's final act. Enter {session}, in {lead} minutes. Exit, pursued by a weekend."),
        L("fr04", .friday, .selfAware, "It's Friday and I'm still on shift. {session} in {lead} minutes. Then we both clock off."),
        L("fr05", .friday, .absurd, "The dumbbells have Friday plans. The plans are you. {session} in {lead} minutes."),
    ]

    static let weekend: [L] = [
        L("we01", .weekend, .deadpan, "A weekend {session}. No rush hour at the rack. {lead} minutes."),
        L("we02", .weekend, .understatement, "{session} on a {weekday}. Relaxed dress code. {lead} minutes."),
        L("we03", .weekend, .natureDoc, "On weekends the gym grows quiet and the lifter roams freely. {session} in {lead} minutes."),
        L("we04", .weekend, .selfAware, "Yes, I work weekends. I'm a notification; it's this or nothing. {session} in {lead} minutes."),
        L("we05", .weekend, .absurd, "{weekday}. The kettlebells are having a lie-in. They always are. {session} in {lead} minutes."),
    ]

    // MARK: The last call (said once, kindly; then reminders go quiet)

    static let lastCall: [L] = [
        L("lc01", .lastCall, .selfAware, "After this one I'll go quiet for a bit. Train or open the app and I'm back. {session}, {lead} minutes."),
        L("lc02", .lastCall, .deadpan, "I'll take the hint after this one and go quiet. No hard feelings; the barbell doesn't have any either. Train or open the app and I'm back."),
        L("lc03", .lastCall, .understatement, "This is my last nudge for now. I'll be back when you train or open the app. {session} in {lead} minutes, if you fancy."),
        L("lc04", .lastCall, .bureaucratic, "Notice: reminders pause after this one. To reinstate, train or open the app. No forms. {session} in {lead} minutes."),
        L("lc05", .lastCall, .mockHeroic, "The herald speaks a final time, then rests. Train or open the app and it returns. {session}, {lead} minutes."),
        L("lc06", .lastCall, .absurd, "After this I'm going quiet, like a barbell at night. Train or open the app and I'm back. {session}, {lead} minutes."),
        L("lc07", .lastCall, .gymBro, "Last one from me for now, bro. Quiet mode. Train or open the app and we're back on. {session}, {lead} minutes."),
        L("lc08", .lastCall, .natureDoc, "After this call the reminder falls silent for a season. It returns when the lifter trains or opens the app. {session}, {lead} minutes."),
    ]

    // MARK: Plain tone

    static let plain: [L] = [
        L("pp01", .planned, .plain, "Your planned session is in {lead} minutes."),
        L("pp02", .planned, .plain, "{session} in {lead} minutes."),
        L("pp03", .planned, .plain, "{session}, {minutes} minutes, starts in {lead} minutes."),
        L("pp04", .planned, .plain, "{session} is planned for today. It starts in {lead} minutes."),
        L("pp05", .planned, .plain, "Planned for {weekday}: {session}. It starts in {lead} minutes."),
        L("pp06", .planned, .plain, "Your planned session is coming up."),
        L("ps01", .shortOption, .plain, "{session} in {lead} minutes. The {short}-minute version counts too."),
        L("ps02", .shortOption, .plain, "{session} starts in {lead} minutes: {minutes} minutes, or {short} if the day is tight."),
        L("ps03", .shortOption, .plain, "{session} in {lead} minutes. The full session or the {short}-minute version, your choice."),
        L("pw01", .weekProgress, .plain, "{done} of {planned} sessions done this week. {session} in {lead} minutes."),
        L("pw02", .weekProgress, .plain, "{session} in {lead} minutes. {left} sessions to go this week."),
        L("pw03", .lastOfWeek, .plain, "{session} in {lead} minutes. It's the last planned session this week."),
        L("pw04", .lastOfWeek, .plain, "The last planned session this week: {session}, in {lead} minutes."),
        L("pw05", .weekStart, .plain, "{session} in {lead} minutes, the first of {planned} this week."),
        L("pd01", .deload, .plain, "Deload week: {session} in {lead} minutes, lighter on purpose."),
        L("pd02", .deload, .plain, "{session} in {lead} minutes. Lighter loads this week, as planned."),
        L("pc01", .comeback, .plain, "{session} in {lead} minutes. It's {days} days since your last session; start where it feels right."),
        L("pc02", .comeback, .plain, "{session} in {lead} minutes. Ease back in; the short version counts too."),
        L("pc03", .longBreak, .plain, "{session} in {lead} minutes. Start light; the plan picks up from here."),
        L("pc04", .longBreak, .plain, "{session} in {lead} minutes. A short, light session is a good way back in."),
        L("pq01", .lastCall, .plain, "This is the last workout reminder for now. They come back when you train or open the app."),
        L("pq02", .lastCall, .plain, "Reminders pause after this one. Train or open the app to bring them back. {session} in {lead} minutes."),
        L("pq03", .lastCall, .plain, "{session} in {lead} minutes. After this, reminders stay quiet until you train or open the app."),
    ]

    // MARK: Caution states (plain and kind; never a push to train)

    static let caution: [L] = [
        // Low recovery: an easy day, not a lost one (HRV-guided training: Javaloyes et al., IJSPP 2019, as in `CoachCheckIns`).
        L("cr01", .lowRecovery, .plain, "Recovery is low today. {session} can be the easy version, the {short}-minute version, or moved. Each one follows the plan."),
        L("cr02", .lowRecovery, .plain, "Recovery is low today. An easy version of {session}, or another day, are both good calls."),
        L("cr03", .lowRecovery, .plain, "Low recovery today. If you train, keep {session} easy. Resting is fine too."),
        L("cr04", .lowRecovery, .plain, "Recovery is low today. Going easy or resting are both fine choices."),
        L("ci01", .illness, .plain, "Illness signs are flagged today. Rest is the right call; {session} can wait."),
        L("ci02", .illness, .plain, "Illness is flagged today. No training is needed; {session} will keep until you're well."),
        L("ci03", .illness, .plain, "Signs of illness today. Rest and sleep come first. {session} can wait until you're well."),
        L("ci04", .illness, .plain, "Illness is flagged today. Rest comes first; training can wait until you're well."),
        // The same rule as `PainGuard.ruleText`; the planner already swaps the lifts that load the area.
        L("cp01", .pain, .plain, "Pain is logged for your {pain}. Leave out or swap what aggravates it; {session} can also wait."),
        L("cp02", .pain, .plain, "With {pain} pain logged, there's no rush on {session}. A lighter session or rest both work."),
        L("cp03", .pain, .plain, "Pain is logged. If you train, the plan swaps the lifts that load the area. Rest is fine too."),
        L("cp04", .pain, .plain, "Pain is logged. Train around it or rest; both are fine. Stop a lift if the pain climbs."),
        L("cm01", .restMode, .plain, "Rest mode is on. No session today; reminders return when it ends."),
        L("cm02", .restMode, .plain, "Rest mode is on. Nothing to do today but rest."),
        L("cm03", .restMode, .plain, "You're in rest mode. Training reminders are off until it ends."),
        L("cd01", .restDay, .plain, "Nothing is planned today. Rest is part of the plan."),
        L("cd02", .restDay, .plain, "Rest day. The next session is on your plan when you're ready for it."),
        L("cd03", .restDay, .plain, "No session is planned today. Enjoy the day off."),
        // Keep plain (`Caution.keepPlain`): the session stands, without a joke and without saying why
        // (the reason is private and a reminder shows on the Lock Screen). Rest stays an option.
        L("ck01", .keepPlain, .plain, "{session} starts in {lead} minutes. Any version counts today, and so does a rest."),
        L("ck02", .keepPlain, .plain, "{session} is planned for today. Go as easy as you like; the short version is fine."),
        L("ck03", .keepPlain, .plain, "Your planned session is coming up. An easy one is fine, and so is resting."),
        L("ck04", .keepPlain, .plain, "{session} in {lead} minutes. Take it at whatever pace suits today, or rest."),
    ]
}
