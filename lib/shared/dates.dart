/// The two date forms the app writes, in one place.
///
/// The month-name table was already copied into five page files by hand when
/// this was written; this is the sixth caller's refusal to make it six copies.
/// The existing five are debt, not precedent (QUEUE F-19).
library;

const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

const _monthsLong = [
  'January', 'February', 'March', 'April', 'May', 'June',
  'July', 'August', 'September', 'October', 'November', 'December',
];

const _weekdays = [
  'Monday', 'Tuesday', 'Wednesday', 'Thursday',
  'Friday', 'Saturday', 'Sunday',
];

/// `Sep 10` — a row's date column.
String shortDate(int? ms) {
  if (ms == null) return '';
  final d = DateTime.fromMillisecondsSinceEpoch(ms);
  return '${_months[d.month - 1]} ${d.day}';
}

/// `Thursday, September 10` — a letter's own dateline.
String longDate(int? ms) {
  if (ms == null) return '';
  final d = DateTime.fromMillisecondsSinceEpoch(ms);
  return '${_weekdays[d.weekday - 1]}, ${_monthsLong[d.month - 1]} ${d.day}';
}
