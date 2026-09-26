// `/landing` is site furniture and lives in `lib/site/` with the sign-in page
// (F-68 / F-44b; Xavier's 2026-09-26 decision that the web reference binds for
// the signed-out pages). This re-export keeps the route table's import where
// it was: a moved import is the only change router.dart would have carried,
// and it would re-date every pair whose item lists that file while no pixel
// of those screens moved.
export '../site/landing_page.dart' show LandingPage;
