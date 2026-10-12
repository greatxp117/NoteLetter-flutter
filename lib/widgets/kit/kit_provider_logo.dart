import 'package:flutter/widgets.dart';
import 'package:path_parsing/path_parsing.dart';

/// The cloud connectors' own marks (F-101) — web `shared/ProviderLogo.jsx`,
/// each vendor's published SVG geometry and colours, unmodified: brand
/// guidelines allow scaling only, so nothing here is redrawn or recoloured.
/// The marks that are black (Notion) are why every TILE holding one is a
/// fixed white plate in both themes (`.connect-card .iconbox`,
/// `.set-row-ico.provider`).
///
/// [size] is the box the mark is fitted into, centred, aspect preserved
/// (`preserveAspectRatio="xMidYMid meet"`). A provider with no mark draws
/// nothing, as web's returns null.
class KitProviderLogo extends StatelessWidget {
  final String provider;
  final double size;

  const KitProviderLogo({super.key, required this.provider, required this.size});

  /// Sentinels for kit widgets that take an [IconData] (as [KitQuill.icon]):
  /// a provider's mark through `KitGlyph`, which ignores the colour it is
  /// handed — the mark carries its own.
  static const _family = 'NoteLetterProviderMark';
  static const IconData googleDrive = IconData(0xF8FA, fontFamily: _family);
  static const IconData oneDrive = IconData(0xF8F9, fontFamily: _family);
  static const IconData dropbox = IconData(0xF8F8, fontFamily: _family);
  static const IconData notion = IconData(0xF8F7, fontFamily: _family);

  static const _byIcon = {
    0xF8FA: 'google_drive',
    0xF8F9: 'onedrive',
    0xF8F8: 'dropbox',
    0xF8F7: 'notion',
  };

  /// The provider an [IconData] sentinel names, or null for any other icon.
  static String? providerOf(IconData icon) =>
      icon.fontFamily == _family ? _byIcon[icon.codePoint] : null;

  static bool has(String provider) => _logos.containsKey(provider);

  // OneDrive's mark is much wider than tall, so fitted to the same box as the
  // squarer marks it reads undersized beside them (web OPTICAL_SCALE).
  static const _opticalScale = {'onedrive': 1.15};

  @override
  Widget build(BuildContext context) {
    final logo = _logos[provider];
    if (logo == null) return SizedBox(width: size, height: size);
    final box = size * (_opticalScale[provider] ?? 1);
    return SizedBox(
      width: size,
      height: size,
      child: OverflowBox(
        maxWidth: box,
        maxHeight: box,
        child: Semantics(
          label: logo.name(provider),
          image: true,
          child: CustomPaint(size: Size(box, box), painter: _LogoPainter(logo)),
        ),
      ),
    );
  }
}

class _Logo {
  final Rect viewBox;
  final List<(Color, String)> paths;
  const _Logo({required this.viewBox, required this.paths});

  String name(String provider) => const {
        'google_drive': 'Google Drive',
        'onedrive': 'OneDrive',
        'dropbox': 'Dropbox',
        'notion': 'Notion',
      }[provider] ??
      provider;
}

class _LogoPainter extends CustomPainter {
  final _Logo logo;
  _LogoPainter(this.logo);

  static final _parsed = <String, Path>{};

  static Path _path(String d) => _parsed.putIfAbsent(d, () {
        final p = Path();
        writeSvgPathDataToPath(d, _Proxy(p));
        return p;
      });

  @override
  void paint(Canvas canvas, Size size) {
    final vb = logo.viewBox;
    final scale = (size.width / vb.width) < (size.height / vb.height)
        ? size.width / vb.width
        : size.height / vb.height;
    canvas.save();
    canvas.translate((size.width - vb.width * scale) / 2,
        (size.height - vb.height * scale) / 2);
    canvas.scale(scale);
    canvas.translate(-vb.left, -vb.top);
    for (final (fill, d) in logo.paths) {
      canvas.drawPath(_path(d), Paint()..color = fill);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_LogoPainter old) => old.logo != logo;
}

class _Proxy extends PathProxy {
  final Path p;
  _Proxy(this.p);
  @override
  void moveTo(double x, double y) => p.moveTo(x, y);
  @override
  void lineTo(double x, double y) => p.lineTo(x, y);
  @override
  void cubicTo(double x1, double y1, double x2, double y2, double x3,
          double y3) =>
      p.cubicTo(x1, y1, x2, y2, x3, y3);
  @override
  void close() => p.close();
}

const _logos = <String, _Logo>{
  'google_drive': _Logo(
    viewBox: Rect.fromLTWH(0.0, 0.0, 256.0, 229.0),
    paths: [
      // literal-ok: google_drive's published brand mark — vendor artwork, never recoloured
      (Color(0xFF0066DA),
          'M19.3542312,196.033928 L30.644172,215.534816 C32.9900287,219.64014 36.3622164,222.86588 40.3210929,225.211737 C51.6602421,210.818376 59.5534225,199.772864 64.000634,192.075201 C68.5137119,184.263529 74.0609657,172.045039 80.6423954,155.41973 C62.9064315,153.085282 49.4659974,151.918058 40.3210929,151.918058 C31.545465,151.918058 18.1051007,153.085282 0,155.41973 C0,159.964996 1.17298825,164.510261 3.51893479,168.615586 L19.3542312,196.033928 Z'),
      // literal-ok: google_drive's published brand mark — vendor artwork, never recoloured
      (Color(0xFFEA4335),
          'M215.681443,225.211737 C219.64032,222.86588 223.012507,219.64014 225.358364,215.534816 L230.050377,207.470615 L252.483511,168.615586 C254.829368,164.510261 256.002446,159.964996 256.002446,155.41973 C237.79254,153.085282 224.376613,151.918058 215.754667,151.918058 C206.488712,151.918058 193.072785,153.085282 175.506888,155.41973 C182.010479,172.136093 187.484394,184.354584 191.928633,192.075201 C196.412073,199.863919 204.329677,210.909431 215.681443,225.211737 Z'),
      // literal-ok: google_drive's published brand mark — vendor artwork, never recoloured
      (Color(0xFF00832D),
          'M128.001268,73.3111515 C141.121182,57.4655263 150.162898,45.2470011 155.126415,36.6555757 C159.123121,29.7376196 163.521739,18.6920726 168.322271,3.51893479 C164.363395,1.1729583 159.818129,0 155.126415,0 L100.876121,0 C96.1841079,0 91.638842,1.31958557 87.6799655,3.51893479 C93.7861943,20.9210065 98.9675428,33.3058067 103.224011,40.6733354 C107.927832,48.8151881 116.186918,59.6944602 128.001268,73.3111515 Z'),
      // literal-ok: google_drive's published brand mark — vendor artwork, never recoloured
      (Color(0xFF2684FC),
          'M175.360141,155.41973 L80.6420959,155.41973 L40.3210929,225.211737 C44.2799694,227.557893 48.8252352,228.730672 53.5172481,228.730672 L202.485288,228.730672 C207.177301,228.730672 211.722567,227.411146 215.681443,225.211737 L175.360141,155.41973 Z'),
      // literal-ok: google_drive's published brand mark — vendor artwork, never recoloured
      (Color(0xFF00AC47),
          'M128.001268,73.3111515 L87.680265,3.51893479 C83.7213885,5.86488134 80.3489013,9.09044179 78.0030446,13.1960654 L3.51893479,142.223575 C1.17298825,146.329198 0,150.874464 0,155.41973 L80.6423954,155.41973 L128.001268,73.3111515 Z'),
      // literal-ok: google_drive's published brand mark — vendor artwork, never recoloured
      (Color(0xFFFFBA00),
          'M215.241501,77.7099697 L177.999492,13.1960654 C175.653635,9.09044179 172.281148,5.86488134 168.322271,3.51893479 L128.001268,73.3111515 L175.360141,155.41973 L255.855999,155.41973 C255.855999,150.874464 254.682921,146.329198 252.337064,142.223575 L215.241501,77.7099697 Z'),
    ],
  ),
  'onedrive': _Logo(
    viewBox: Rect.fromLTWH(0.0, 0.0, 256.0, 165.0),
    paths: [
      // literal-ok: onedrive's published brand mark — vendor artwork, never recoloured
      (Color(0xFF0364B8),
          'M154.66056,110.681557 L207.502052,60.1479482 C196.525811,17.3487078 152.932256,-8.44908883 110.132767,2.52715287 C90.8589801,7.46999082 74.1187452,19.4179992 63.179535,36.0386895 C63.9974594,36.0180612 154.66056,110.681557 154.66056,110.681557 Z'),
      // literal-ok: onedrive's published brand mark — vendor artwork, never recoloured
      (Color(0xFF0078D4),
          'M97.6181022,45.5520619 L97.6156169,45.5607606 C87.5186874,39.307156 75.8741386,36.001658 63.9972108,36.0177537 C63.7228296,36.0177537 63.4531706,36.03521 63.1792865,36.0384409 C27.8517142,36.4761088 -0.432413365,65.4695515 0.00500592252,100.797124 C0.163570414,113.612018 4.16769663,126.083687 11.4981977,136.595916 L90.6631356,126.680913 L151.357298,77.7409022 L97.6181022,45.5520619 Z'),
      // literal-ok: onedrive's published brand mark — vendor artwork, never recoloured
      (Color(0xFF1490DF),
          'M207.502052,60.1481967 C206.340406,60.0706542 205.173043,60.016946 203.992011,60.016946 C196.903085,60.010012 189.887973,61.4579693 183.381112,64.271122 L183.379621,64.2656543 L151.357547,77.7411507 L186.65952,121.347877 L249.770673,136.689364 C263.390071,111.405536 253.93411,79.8683506 228.650281,66.2489531 C222.117076,62.7297161 214.906119,60.6497377 207.502301,60.1484453 L207.502301,60.1481967 L207.502052,60.1481967 Z'),
      // literal-ok: onedrive's published brand mark — vendor artwork, never recoloured
      (Color(0xFF28A8EA),
          'M11.4981977,136.595916 C23.4514253,153.781772 43.063467,164.023845 63.9974594,164.012918 L203.991762,164.012918 C223.115435,164.018377 240.697951,153.524291 249.770425,136.689862 L151.357298,77.7409022 L11.4981977,136.595916 Z'),
    ],
  ),
  'dropbox': _Logo(
    viewBox: Rect.fromLTWH(0.0, 0.0, 256.0, 218.0),
    paths: [
      // literal-ok: dropbox's published brand mark — vendor artwork, never recoloured
      (Color(0xFF0061FF),
          'M63.9945638,0 L0,40.7712563 L63.9945638,81.5425125 L128,40.7712563 Z'),
      // literal-ok: dropbox's published brand mark — vendor artwork, never recoloured
      (Color(0xFF0061FF),
          'M192.000442,0 L128,40.7750015 L192.000442,81.5500031 L256.000885,40.7750015 Z'),
      // literal-ok: dropbox's published brand mark — vendor artwork, never recoloured
      (Color(0xFF0061FF),
          'M0,122.321259 L63.9945638,163.092516 L128,122.321259 L63.9945638,81.5500031 Z'),
      // literal-ok: dropbox's published brand mark — vendor artwork, never recoloured
      (Color(0xFF0061FF),
          'M192,81.5500031 L128,122.324723 L192,163.099442 L256,122.324723 Z'),
      // literal-ok: dropbox's published brand mark — vendor artwork, never recoloured
      (Color(0xFF0061FF),
          'M64,176.771256 L128.005436,217.542513 L192,176.771256 L128.005436,136 Z'),
    ],
  ),
  'notion': _Logo(
    viewBox: Rect.fromLTWH(0.0, 0.0, 24.0, 24.0),
    paths: [
      // literal-ok: notion's published brand mark — vendor artwork, never recoloured
      (Color(0xFF000000),
          'M4.459 4.208c.746.606 1.026.56 2.428.466l13.215-.793c.28 0 .047-.28-.046-.326L17.86 1.968c-.42-.326-.981-.7-2.055-.607L3.01 2.295c-.466.046-.56.28-.374.466zm.793 3.08v13.904c0 .747.373 1.027 1.214.98l14.523-.84c.841-.046.935-.56.935-1.167V6.354c0-.606-.233-.933-.748-.887l-15.177.887c-.56.047-.747.327-.747.933zm14.337.745c.093.42 0 .84-.42.888l-.7.14v10.264c-.608.327-1.168.514-1.635.514-.748 0-.935-.234-1.495-.933l-4.577-7.186v6.952L12.21 19s0 .84-1.168.84l-3.222.186c-.093-.186 0-.653.327-.746l.84-.233V9.854L7.822 9.76c-.094-.42.14-1.026.793-1.073l3.456-.233 4.764 7.279v-6.44l-1.215-.139c-.093-.514.28-.887.747-.933zM1.936 1.035l13.31-.98c1.634-.14 2.055-.047 3.082.7l4.249 2.986c.7.513.934.653.934 1.213v16.378c0 1.026-.373 1.634-1.68 1.726l-15.458.934c-.98.047-1.448-.093-1.962-.747l-3.129-4.06c-.56-.747-.793-1.306-.793-1.96V2.667c0-.839.374-1.54 1.447-1.632z'),
    ],
  ),
};
