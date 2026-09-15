/// The hostname a link goes to, `www.` stripped — the one spelling.
///
/// Two surfaces name a host to the reader: the Reader's byline (2.13.0) and an
/// Ask citation's source control (4.63.0, ADR-099), whose whole rule is that
/// the host is NAMED, because a link that does not say where it goes is a link
/// the reader has to click to find out. The reference draws both from
/// `sourceHost()` in `pages/reader/readerPrefs.js`; this is that function.
///
/// Null when there is no parseable host — and a caller renders NO control
/// rather than one labelled with a guess (component-kit §6.4.2 rule 3).
library;

String? sourceHost(String? url) {
  if (url == null) return null;
  final h = Uri.tryParse(url)?.host;
  if (h == null || h.isEmpty) return null;
  return h.startsWith('www.') ? h.substring(4) : h;
}
