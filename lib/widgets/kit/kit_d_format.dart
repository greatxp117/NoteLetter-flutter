// Direction D's small sentences and figures, shared by every D page (web
// `src/kit/d/format.js` and `shared/plural.js`; the prototype's `window.NlHome`
// helpers). Pure functions: no widget, no read.

const List<String> _num = [
  'no', 'one', 'two', 'three', 'four', 'five', 'six', 'seven', 'eight', //
  'nine', 'ten', 'eleven', 'twelve',
];

/// Thousands separators, as web's `toLocaleString('en-US')`: `1,200`.
String kitThousands(num n) {
  final neg = n < 0;
  final s = n.abs().round().toString();
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
    b.write(s[i]);
  }
  return neg ? '-$b' : b.toString();
}

/// A small count in words (*three passages*), a large one in figures (web `say`).
String kitSay(int n) => n >= 0 && n < _num.length ? _num[n] : kitThousands(n);

/// The first letter capitalised (web `cap`).
String kitCap(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

/// A count and its noun, agreeing in number: *1 passage*, *1,200 passages*
/// (web `counted`).
String kitCounted(int n, String one, [String? many]) =>
    '${kitThousands(n)} ${n == 1 ? one : (many ?? '${one}s')}';

const List<String> _weekdays = [
  'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday',
];
const List<String> _months = [
  'January', 'February', 'March', 'April', 'May', 'June', //
  'July', 'August', 'September', 'October', 'November', 'December',
];

/// *Thursday, October 30* (web `fmt.longDay`), on this device's calendar.
String kitLongDay(int ms) {
  final d = DateTime.fromMillisecondsSinceEpoch(ms);
  return '${_weekdays[d.weekday - 1]}, ${_months[d.month - 1]} ${d.day}';
}

/// *Thu, Oct 30* (web `fmt.shortDay`).
String kitShortDay(int ms) {
  final d = DateTime.fromMillisecondsSinceEpoch(ms);
  return '${_weekdays[d.weekday - 1].substring(0, 3)}, '
      '${_months[d.month - 1].substring(0, 3)} ${d.day}';
}

/// *October 2026* — the register's month head (web `groupSources`).
String kitMonthYear(int ms) {
  final d = DateTime.fromMillisecondsSinceEpoch(ms);
  return '${_months[d.month - 1]} ${d.year}';
}

/// Built on the viewer's calendar day — the clock the folio's date is printed
/// from (screens/library.md §The letter, ADR-132).
bool kitIsToday(int? ms, [DateTime? now]) {
  if (ms == null) return false;
  final d = DateTime.fromMillisecondsSinceEpoch(ms);
  final n = now ?? DateTime.now();
  return d.year == n.year && d.month == n.month && d.day == n.day;
}

/// *Good morning* before 12:00, *Good afternoon* before 18:00, else *Good
/// evening* (web `greeting`).
String kitGreeting([DateTime? now]) {
  final h = (now ?? DateTime.now()).hour;
  return h < 12
      ? 'Good morning'
      : h < 18
          ? 'Good afternoon'
          : 'Good evening';
}

final RegExp _hhmm = RegExp(r'^(\d{1,2}):(\d{2})$');

/// `08:00` → *8:00 AM*; anything else → null (web `clock`).
String? kitClock(String? hhmm) {
  final m = _hhmm.firstMatch(hhmm ?? '');
  if (m == null) return null;
  final h = int.parse(m.group(1)!);
  return '${h % 12 == 0 ? 12 : h % 12}:${m.group(2)} ${h >= 12 ? 'PM' : 'AM'}';
}

/// Which days a schedule delivers on — the orchestrator's own rule
/// (area_letter.py: `weekdays` skips Saturday and Sunday, `weekly` is Monday).
/// [d] is Dart's weekday, 1 = Monday … 7 = Sunday.
bool _delivers(String frequency, int d) => switch (frequency) {
      'weekdays' => d >= 1 && d <= 5,
      'weekly' => d == 1,
      _ => true,
    };

/// The next delivery of a schedule: *Today, 8:00 AM*, *Tomorrow, 8:00 AM* or
/// *Monday, 8:00 AM* (web `nextAt`), read on this device's clock and the
/// schedule's own days, so a weekday letter on a Friday evening says Monday.
/// An unknown frequency reads as daily (the backend's default).
///
/// Web reads the wall clock in the schedule's `timezone`; this client has no
/// zone database, and the zone it stores is the device's own (LetterQuick
/// writes `deviceTimezone`), so the device clock is the same clock in every
/// case a reader can reach from here.
String? kitNextAt(String? hhmm, {String frequency = 'daily', DateTime? now}) {
  final m = _hhmm.firstMatch(hhmm ?? '');
  if (m == null) return null;
  final at = int.parse(m.group(1)!) * 60 + int.parse(m.group(2)!);
  final n = now ?? DateTime.now();
  final cur = n.hour * 60 + n.minute;
  for (var i = 0; i < 8; i++) {
    final d = (n.weekday - 1 + i) % 7 + 1;
    if (!_delivers(frequency, d) || (i == 0 && cur >= at)) continue;
    final day = i == 0
        ? 'Today'
        : i == 1
            ? 'Tomorrow'
            : _weekdays[d - 1];
    return '$day, ${kitClock(hhmm)}';
  }
  return null;
}

/// Reading time for a letter of [n] passages — the Letters card's own
/// arithmetic: about a minute a passage, plus one (web `minutes`).
int kitMinutes(int n) => n + 1;
