/// §11 — the newsletter as a physical page.
///
/// Two forms, and the letter itself decides which (4.50.0, ADR-087):
///
///  * [KitLetterPaper] hosts a body that **brings its own letterhead** BARE.
///    It is the letter that was sent, so it is not framed, not tinted and not
///    re-themed — a reader opening it is looking at the object in their inbox.
///  * [KitLetterSheet] is the frame this client draws for a body that has
///    none, which is every `daily` letter written before 4.50.0 and every
///    readings letter. It is the §11 pattern in full.
///
/// Deciding by the ATTRIBUTE rather than by a version is what lets an archive
/// of both shapes render correctly, in either deploy order.
library;

import 'package:flutter/material.dart' show Icon, IconData, Icons;
import 'package:flutter/widgets.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../theme/app_radius.dart';
import '../../theme/app_shadows.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import 'kit_text.dart';

/// The letter's own colours, frozen.
///
/// The sent letter's palette is **baked light hex** in the backend renderer,
/// because no email client resolves a custom property
/// (`harness/letter_palette_check.py` holds that table to `theme.css`). The
/// ground it sits on has to be frozen with it: a `--surface` page behind a
/// light letter puts a near-black gutter around white paper in dark mode, and
/// a theme-flipping body would be a different object from the one that was
/// sent.
/// A `Color` as the `#RRGGBB` a stylesheet takes.
///
/// The letter's ground is spelled ONCE, in [_Paper], and the document wrapper
/// derives its CSS from it — a second hex here would be a copy that renders
/// right today and does not move when the first one does, which is the whole
/// of what `token_contrast_check.py`'s LITERAL direction is for.
String _cssHex(Color c) =>
    '#${((c.r * 255).round() << 16 | (c.g * 255).round() << 8 | (c.b * 255).round()).toRadixString(16).padLeft(6, '0').toUpperCase()}';

class _Paper {
  // literal-ok: --paper-50, the letter's own page. It does not flip, for the
  // same reason the letter's inlined colours do not (ADR-087).
  static const ground = Color(0xFFFAFAF7);
}

/// A complete letter, hosted bare on its own paper — **in a web view**.
///
/// Not `flutter_html`, and the reason is the whole point of ADR-087. A sent
/// letter is HTML **mail**: its layout is nested tables, because tables are the
/// only box model mail clients agree on. flutter_html renders no table without
/// an extension and, with one, the letter's own baseline-aligned cells reach
/// `RenderBox.size accessed in RenderParagraph.computeDryLayout` — it cannot
/// lay this document out. The alternative was to rewrite the letter's HTML
/// until the renderer could take it, which is exactly what a client hosting the
/// letter BARE may not do: the reader would then be looking at something nobody
/// was sent.
///
/// So the letter is handed to the engine that mail clients use. Nothing about
/// it is themed, styled or wrapped here — this widget's whole job is to give it
/// a width and the height it asks for.
class KitLetterPaper extends StatefulWidget {
  final String html;

  const KitLetterPaper(this.html, {super.key});

  /// The letter, wrapped in the minimum a document needs and **nothing else**.
  ///
  /// No stylesheet of ours: every colour, face and metric in a letter is inline
  /// (ADR-087 forbids a `<style>` block in the body for a second reason — the
  /// plain-text part is a naive tag strip that a `<style>` block survives). The
  /// viewport meta and the two resets are what make a 640px mail sheet fit a
  /// phone instead of scrolling sideways.
  @visibleForTesting
  static String documentFor(String body) => '''
<!doctype html><html><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<style>html,body{margin:0;padding:0;background:${_cssHex(_Paper.ground)};-webkit-text-size-adjust:100%}
img{max-width:100%;height:auto}table{max-width:100%}</style>
</head><body>$body</body></html>''';

  @override
  State<KitLetterPaper> createState() => _KitLetterPaperState();
}

class _KitLetterPaperState extends State<KitLetterPaper> {
  late final WebViewController _controller;

  /// The letter's own height, **measured**, never assumed. Until the page
  /// reports one there is no honest number, so the view holds a minimum rather
  /// than guessing a letter's length.
  double? _height;

  static const _minHeight = 420.0;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      // The letter's ground, frozen light, behind the document itself — so the
      // moment before it paints is paper rather than a flash of white or of
      // the app's dark surface.
      ..setBackgroundColor(_Paper.ground)
      // The one channel this page has, and it carries one number: how tall the
      // letter turned out to be.
      ..addJavaScriptChannel('LetterHeight',
          onMessageReceived: (m) {
            final h = double.tryParse(m.message);
            if (h != null && h > 0 && mounted) setState(() => _height = h);
          })
      ..setNavigationDelegate(NavigationDelegate(
        // A letter is a document, not a browser. Its own body is the only
        // thing this view ever loads; every link in it — the reader links
        // INV-21 puts on each card, the unsubscribe footer — is a navigation
        // AWAY, and it is refused here rather than replacing the letter with a
        // web page inside the app.
        onNavigationRequest: (r) => r.url.startsWith('about:')
            ? NavigationDecision.navigate
            : NavigationDecision.prevent,
        onPageFinished: (_) => _measure(),
      ))
      ..loadHtmlString(KitLetterPaper.documentFor(widget.html));
  }

  /// Ask the page how tall it is. Called when it finishes loading, and again
  /// after a beat: web fonts and the seal land after `onPageFinished` and each
  /// changes the answer.
  void _measure() {
    for (final ms in [0, 250, 1000]) {
      Future<void>.delayed(Duration(milliseconds: ms), () {
        if (mounted) _controller.runJavaScript(_measureJs);
      });
    }
  }

  /// Fit the letter to the screen the way a phone mail client does, and
  /// report how tall it ends up.
  ///
  /// A sent letter is a **640px sheet** — that is the width mail is designed
  /// at, and it is not going to change for a phone. `width=device-width` does
  /// not rescue it either: the sheet's cells carry 56px of padding each side,
  /// so its min-content width is wider than a phone and `max-width:100%` has
  /// nothing left to give. It simply hangs off the right edge, which is how
  /// the first render of this looked.
  ///
  /// So the page is laid out at **its own measured width** and scaled down to
  /// the screen — exactly what mobile Safari and Mail do with a desktop-width
  /// message. The width is read from the document rather than hardcoded from
  /// the renderer: a letter that changes width keeps fitting, and no number
  /// from the backend is copied into this client to go stale.
  ///
  /// The height comes back pre-scaled, because the widget is sized in device
  /// pixels and the page is now measuring itself in its own.
  static const _measureJs = '''(function(){
  var dw = window.__nlDeviceWidth || (window.__nlDeviceWidth = window.innerWidth);
  var need = Math.max(document.documentElement.scrollWidth, dw);
  if (need > dw) {
    document.querySelector('meta[name=viewport]')
      .setAttribute('content', 'width=' + need);
  }
  var scale = Math.min(1, dw / need);
  LetterHeight.postMessage(
    String(Math.ceil(document.body.scrollHeight * scale)));
})();''';


  @override
  Widget build(BuildContext context) {
    return Container(
      color: _Paper.ground,
      width: double.infinity,
      height: _height ?? _minHeight,
      // The letter scrolls with the screen, not inside itself: it sits in the
      // page's own scroll container at its measured height, so there is one
      // scroll and the actions bar above it stays reachable.
      child: WebViewWidget(
        controller: _controller,
        gestureRecognizers: const {},
      ),
    );
  }
}

/// The §11 letter sheet: the frame this client draws around a **frame-less**
/// body.
///
/// Required parts, in order — checkered page ground · centred paper · masthead
/// (title + issue marker) closed by a `--border-strong` rule · standfirst ·
/// body · seal footer above a `--border` top rule. The **actions bar sits
/// outside the sheet** and is therefore not part of this widget.
class KitLetterSheet extends StatelessWidget {
  /// The masthead's title. Set in the versal lockup the letter uses: uppercase
  /// serif with the opening capitals raised.
  final String title;

  /// The trailing issue marker — a subject, a date, a number.
  final String? marker;

  /// The italic serif standfirst under the masthead rule.
  final String? standfirst;

  /// The body, already composed: [RuledSectionLabel]s, [KitLetterProse] and
  /// [KitLetterAttribution] rows.
  final List<Widget> children;

  /// The seal footer's line. Italic serif, beside the mark.
  final String sealText;

  const KitLetterSheet({
    super.key,
    required this.title,
    this.marker,
    this.standfirst,
    this.children = const [],
    required this.sealText,
  });

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final compact = MediaQuery.sizeOf(context).width < AppSpacing.compactWidth;
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints:
            const BoxConstraints(maxWidth: AppSpacing.frameSheet),
        child: Container(
          margin: EdgeInsets.symmetric(
              horizontal: compact
                  ? AppSpacing.frameGutterCompact
                  : AppSpacing.frameGutter),
          padding: EdgeInsets.fromLTRB(
            compact ? AppSpacing.s5 : AppSpacing.s16,
            compact ? AppSpacing.s8 : AppSpacing.s12 + AppSpacing.s2,
            compact ? AppSpacing.s5 : AppSpacing.s16,
            compact ? AppSpacing.s8 : AppSpacing.s16,
          ),
          decoration: BoxDecoration(
            color: t.surface,
            borderRadius: AppRadius.mdR,
            boxShadow: AppShadows.s2,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── masthead, closed by the strong rule ──────────────────
              Container(
                padding: const EdgeInsets.only(bottom: AppSpacing.s3),
                decoration: BoxDecoration(
                  border: Border(
                      bottom: BorderSide(color: t.borderStrong)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(child: KitVersal(title)),
                    if (marker != null && marker!.isNotEmpty) ...[
                      const SizedBox(width: AppSpacing.s3),
                      Flexible(
                        child: Text(
                          marker!.toUpperCase(),
                          textAlign: TextAlign.end,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: KitText.capsLabel(context,
                              fontSize: 11, letterSpacing: 0.1),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 22),
              if (standfirst != null && standfirst!.isNotEmpty) ...[
                Lede(standfirst!, maxWidth: double.infinity),
                const SizedBox(height: AppSpacing.s8 - 4),
              ],
              ...children,
              // ── seal footer ─────────────────────────────────────────
              Container(
                margin: const EdgeInsets.only(top: AppSpacing.s8),
                padding: const EdgeInsets.only(top: AppSpacing.s6),
                decoration: BoxDecoration(
                  border: Border(top: BorderSide(color: t.border)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(_sealMark, size: 22, color: t.seal),
                    const SizedBox(width: AppSpacing.s2 + 2),
                    Expanded(
                      child: Text(sealText,
                          style: KitText.lede(context,
                              fontSize: 13, height: 19)),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The masthead lockup: uppercase serif with the opening capital of each word
/// raised. `A Letter.` sets as `A LETTER.` with the A and the L a fifth larger
/// — the versal the app and the sent letter share.
///
/// **Which letters rise is not a detail.** The sent letter raised the O and the
/// L for a whole release, so every letter read `NOteLETTER` (4.50.1).
class KitVersal extends StatelessWidget {
  final String text;
  final double fontSize;

  const KitVersal(this.text, {super.key, this.fontSize = 36});

  @override
  Widget build(BuildContext context) {
    final base = AppTheme.serif(
      fontSize: fontSize,
      height: 1,
      fontWeight: FontWeight.w700,
      letterSpacing: 0.08 * fontSize,
      color: Tokens.of(context).fg,
    );
    final spans = <TextSpan>[];
    var atWordStart = true;
    for (final ch in text.toUpperCase().split('')) {
      final isLetter = RegExp(r'[A-Z]').hasMatch(ch);
      spans.add(TextSpan(
        text: ch,
        style: (atWordStart && isLetter)
            ? base.copyWith(fontSize: fontSize * 1.2, fontWeight: FontWeight.w600)
            : null,
      ));
      if (isLetter) atWordStart = false;
      if (ch == ' ') atWordStart = true;
    }
    return Text.rich(TextSpan(style: base, children: spans),
        maxLines: 2, overflow: TextOverflow.ellipsis);
  }
}

/// A frame-less letter body, rendered inside [KitLetterSheet].
///
/// Themed, unlike [KitLetterPaper]: this body carries no colours of its own —
/// it is the card list a pre-4.50.0 build wrote — so it takes the app's, and
/// flips with the theme like the sheet around it.
class KitLetterBody extends StatelessWidget {
  final String html;

  const KitLetterBody(this.html, {super.key});

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return Html(
      data: html,
      extensions: AppTheme.htmlExtensions,
      style: {
        ...AppTheme.htmlStyles(t),
        'body': Style(
          margin: Margins.zero,
          padding: HtmlPaddings.zero,
          fontFamily: AppTheme.fontSerif,
          fontSize: FontSize(17),
          lineHeight: LineHeight(28 / 17),
          color: t.fg,
        ),
        // §11 — marked text in a letter is a SOLID fill, stronger than the
        // reader's `--highlight` wash, deliberately. Both halves are frozen
        // steps because the pair has to hold in both themes, and the letter's
        // own mark is this exact pair.
        'mark': Style(
          // literal-ok: --brick-500, §11's letter mark fill
          backgroundColor: const Color(0xFF9D352D),
          // literal-ok: --paper-50, the label on that fill
          color: const Color(0xFFFAFAF7),
        ),
        'blockquote': Style(
          margin: Margins.only(left: 0, bottom: 12),
          padding: HtmlPaddings.only(left: 14),
          border: Border(left: BorderSide(color: t.accent, width: 2)),
        ),
        'a': Style(color: t.link),
        'img': Style(width: Width(100, Unit.percent)),
      },
    );
  }
}

/// A paragraph of the letter's body — serif 17/28, the reading size the sheet
/// sets. `child` rather than a string so a passage can carry marked text and
/// §17 markers.
class KitLetterProse extends StatelessWidget {
  final Widget child;

  const KitLetterProse({super.key, required this.child});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.s3),
        child: DefaultTextStyle(
          style: AppTheme.serif(
            fontSize: 17,
            height: 28 / 17,
            color: Tokens.of(context).fg,
          ),
          child: child,
        ),
      );
}

/// The line under a passage — its source, or the count it is part of.
class KitLetterAttribution extends StatelessWidget {
  final String text;

  const KitLetterAttribution(this.text, {super.key});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.s8 - 4),
        child: Text(text,
            style: TextStyle(
              fontFamily: AppTheme.fontSans,
              fontSize: 12,
              color: Tokens.of(context).fgMuted,
            )),
      );
}

/// The mark in the seal. The same glyph the chrome rail sets as the brand
/// (`sidebar.dart`), so the seal on the letter and the mark on the app are one
/// thing rather than two that drift.
const IconData _sealMark = Icons.edit_note;
