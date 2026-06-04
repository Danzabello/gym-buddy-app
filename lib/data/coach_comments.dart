// lib/data/coach_comments.dart
//
// Coach Max comment bank for completed workout cards.
// Add new entries to any list here — the widget picks them automatically.
// Placeholders: {partner} {planned} {type}

class CoachComments {
  const CoachComments._();

  // ── Co-op: both completed, met or exceeded goal ─────────────
  static const List<String> coopCrushed = [
    "You and {partner} both showed up. That's the whole game — keep repeating it.",
    "Two people, one commitment. {partner} held up their end. So did you.",
    "Co-op done. When both people commit, the streak builds itself.",
    "Accountability cuts both ways. Today it paid off for both of you.",
    "Neither of you looked for an excuse. That's the habit forming.",
    "You matched {partner}'s energy today. Or they matched yours. Either way it worked.",
    "Sessions like this are why co-op streaks outlast solo ones.",
    "This is what it looks like when the system works. You and {partner}, showing up.",
    "Mutual effort, mutual benefit. The streak grows when both people commit.",
    "You didn't let {partner} down. They didn't let you down. Stack these.",
  ];

  // ── Co-op: both completed, went over the plan ───────────────
  static const List<String> coopOver = [
    "You planned {planned} and both went longer. That's momentum, not coincidence.",
    "Over the goal, together. You pushed past the plan without even discussing it.",
    "{partner} didn't stop at {planned}m. Neither did you. Good session.",
    "Planned {planned}m, gave more. Both of you. That's a strong day.",
    "When your co-op partner keeps going, it pulls you forward. You both felt it.",
    "Went beyond the target together. That's the compounding effect of a good partner.",
  ];

  // ── Co-op: both completed, significantly under plan ─────────
  static const List<String> coopShort = [
    "Shorter than planned, but both of you made it. The streak survives.",
    "Not the full session. Still completed. {partner} showed up, so did you.",
    "Under the goal, but neither of you bailed. That counts.",
    "A partial session beats a skipped one. Both of you know that.",
    "Less than planned — but you still closed the ring. That matters more than you think.",
    "Not every session hits the mark. The important thing is you both still came.",
  ];

  // ── Solo: completed, met or close to goal ───────────────────
  static const List<String> soloCrushed = [
    "No partner today. Didn't need one. You handled it alone.",
    "Solo session, full effort. The discipline is entirely yours.",
    "Just you and the work. You showed up when no one was watching.",
    "You didn't wait for anyone to push you. That's a good sign.",
    "Self-accountability on display. No partner, no problem.",
    "No one else was keeping score. You kept it anyway.",
    "The streak doesn't care how many showed up. It cares that you did.",
    "Flying solo and still made it happen. That's the foundation of consistency.",
    "You built this one without a net. That's worth something.",
    "Solo wins build a different kind of confidence than co-op ones. File this one.",
    "The hardest sessions to show up for are the solo ones. You showed up.",
    "You're not relying on anyone else to keep this going. Good.",
  ];

  // ── Solo: exceeded goal ──────────────────────────────────────
  static const List<String> soloOver = [
    "You said {planned}m. You gave more. Nobody pushed you to. That's internal drive.",
    "Over the goal and no partner in sight. You didn't need one.",
    "Exceeded the plan on your own. That's the version of you worth chasing.",
    "Planned {planned}m, went longer, solo. That tells me something about where you are right now.",
    "When you go over the goal alone, that's a signal. Remember this feeling.",
  ];

  // ── Solo: cut short ──────────────────────────────────────────
  static const List<String> soloShort = [
    "Short session. Still better than skipping. Come back with more tomorrow.",
    "The full {planned} minutes didn't happen, but you showed up. That's non-zero.",
    "Progress over perfection. You moved today, and that keeps the streak alive.",
    "Shorter than expected. It happens. Don't let it set the tone for tomorrow.",
    "Didn't finish the plan. Finished the session. That's still a win.",
    "Less than planned. More than nothing. The streak continues.",
  ];

  // ── Buddy bailed ─────────────────────────────────────────────
  static const List<String> buddyBailed = [
    "{partner} didn't make it. But you did. Sometimes that's the whole lesson.",
    "You showed up even when your co-op partner didn't. The streak is yours to protect.",
    "Not ideal when the buddy bails, but you still laced up. Respect.",
    "You can't control what {partner} does. You showed up anyway. That's character.",
    "{partner} sat this one out. You didn't. That difference compounds over time.",
    "Solo by circumstance, committed by choice. Well done.",
    "When the buddy bails, the streak falls on you. You carried it.",
    "One person showed up today. You. Don't let {partner} make a habit of this.",
  ];

  // ── Strength specific ────────────────────────────────────────
  static const List<String> strengthSpecific = [
    "Strength sessions are deposits in an account that pays out slowly but reliably.",
    "Every strength session rewires the body a little. Today counted.",
    "The weight doesn't move itself. You know that better than anyone.",
    "Strength training is the slowest, most reliable path. You're on it.",
  ];

  // ── Cardio specific ──────────────────────────────────────────
  static const List<String> cardioSpecific = [
    "Cardio done. Heart rate up, streak intact. Simple math.",
    "You ran it, biked it, rowed it — doesn't matter. You showed up.",
    "Cardio isn't always glamorous but it always counts towards the goal.",
    "The cardiovascular system adapts to whatever you ask of it. Keep asking.",
  ];

  // ── HIIT specific ────────────────────────────────────────────
  static const List<String> hiitSpecific = [
    "HIIT doesn't forgive slacking. You didn't slack. Session done.",
    "High intensity. Completed. Those two words together say a lot.",
    "You picked the hard option and finished it. That's a meaningful choice.",
    "HIIT is the kind of session people skip. You didn't. File that.",
  ];

  // ── Yoga specific ────────────────────────────────────────────
  static const List<String> yogaSpecific = [
    "Not every session has to be brutal. Yoga counts, and you showed up for it.",
    "Flexibility and consistency. You're working both at once.",
    "The mat was out. You got on it. Streak protected.",
    "Recovery and mobility work gets skipped more than it should. You didn't skip it.",
  ];

  // ── Morning sessions ─────────────────────────────────────────
  static const List<String> morning = [
    "Morning session locked. Most people haven't started the day yet. You're already done.",
    "Early mover. That {type} session sets the tone for everything that follows.",
    "Up before most, workout done before most. The day starts differently now.",
    "There's no version of this where training before 9am doesn't pay off.",
  ];

  // ── Late night sessions ──────────────────────────────────────
  static const List<String> lateNight = [
    "Late night {type} session. Not the easy choice. You made it anyway.",
    "Ending the day with a workout instead of an excuse. That's the standard.",
    "Most people wind down at this hour. You trained instead. Remember that.",
    "The late session is the one most people skip. You're not most people.",
  ];
}