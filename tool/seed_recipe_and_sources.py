"""Seed the three source-shaped documents F-11's frames need.

The canonical emulator seed has no distilled document and no image set, and its
one `file`-shaped document has no bytes in the Storage emulator — so §5.4's
recipe body, §15.1's file view and §15.2's page grid had nothing to render and
could not be photographed at all.

What this writes, and why each one:

  shot-recipe      a `content_form: "recipe"` YouTube document whose ONE chunk
                   is a complete recipe in ordinary extraction vocabulary (no
                   new tag, no new attribute). That is the point of ADR-042 §3:
                   the chunk html IS the recipe, and a client reading none of
                   the `recipe` fields still renders one. The structured field
                   is what buys the checkable list, the step figures and the
                   times. `source_url` is a YouTube watch URL, so the time chips
                   take §Step jump's branch 2 and are LIVE.

  shot-image-set   a three-page `image_set` with the MIDDLE page's bytes
                   deliberately absent, because the state worth photographing is
                   the one §15.2 rule 1 is about: a page that has not landed
                   draws a placeholder at its own index rather than being
                   dropped. Two of three uploaded is the count the toolbar says.

  the pdf seed     the canonical `seed-doc-pdf-complete`'s object, uploaded so
                   `fn_get_raw_document_url` can sign it. Without the bytes the
                   endpoint answers `signed_url: null` — a real state, and not
                   the one §15.1 is for.

Pictures are plain gradients: the subject is the body, not the photograph.

Writes through the emulator REST with `Bearer owner`, which bypasses rules — a
client cannot write /documents directly (INV-04).
"""
import json, os, struct, urllib.parse, urllib.request, zlib

HOST = os.environ.get("FIRESTORE_EMULATOR_HOST", "localhost:8080")
BASE = f"http://{HOST}/v1/projects/noteletter-7a111/databases/(default)/documents"
STORAGE = os.environ.get("STORAGE_EMULATOR_HOST", "http://localhost:9199").rstrip("/")
BUCKET = "noteletter-7a111.firebasestorage.app"
UID = "seed-user-1"


def png(w, h, top, bottom):
    """A vertical gradient, written by hand so this script needs no Pillow."""
    rows = b""
    for y in range(h):
        f = y / max(1, h - 1)
        px = bytes(round(top[i] + (bottom[i] - top[i]) * f) for i in range(3))
        rows += b"\x00" + px * w

    def chunk(tag, data):
        c = tag + data
        return struct.pack(">I", len(data)) + c + struct.pack(">I", zlib.crc32(c))

    return (b"\x89PNG\r\n\x1a\n"
            + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(rows))
            + chunk(b"IEND", b""))


def put_object(path, data, mime):
    url = (f"{STORAGE}/upload/storage/v1/b/{BUCKET}/o?uploadType=media&name="
           + urllib.parse.quote(path, safe=""))
    req = urllib.request.Request(url, data=data,
                                 headers={"Content-Type": mime}, method="POST")
    urllib.request.urlopen(req).read()
    # What a signed URL resolves to under the dev shim — the same bytes.
    return (f"{STORAGE}/storage/v1/b/{BUCKET}/o/"
            + urllib.parse.quote(path, safe="") + "?alt=media")


def put_doc(path, fields):
    req = urllib.request.Request(
        f"{BASE}/{path}", method="PATCH",
        data=json.dumps({"fields": fields}).encode(),
        headers={"Authorization": "Bearer owner",
                 "Content-Type": "application/json"})
    urllib.request.urlopen(req).read()


S = lambda v: {"stringValue": v}                    # noqa: E731
I = lambda v: {"integerValue": str(v)}              # noqa: E731
D = lambda v: {"doubleValue": v}                    # noqa: E731
B = lambda v: {"booleanValue": v}                   # noqa: E731
N = {"nullValue": None}
A = lambda vs: {"arrayValue": {"values": vs}}       # noqa: E731
M = lambda f: {"mapValue": {"fields": f}}           # noqa: E731
TS = {"timestampValue": "2026-09-01T10:00:00Z"}

# ── The recipe's three pictures ──────────────────────────────────────────────
LEAD = put_object("processed/seed-user-1/images/shot-recipe-lead.png",
                  png(320, 200, (214, 158, 96), (150, 76, 40)), "image/png")
STEP = put_object("processed/seed-user-1/images/shot-recipe-step.png",
                  png(320, 200, (226, 216, 188), (168, 156, 120)), "image/png")
CRUMB = put_object("processed/seed-user-1/images/shot-recipe-crumb.png",
                   png(320, 200, (232, 196, 120), (186, 140, 70)), "image/png")

LEAD_ID, STEP_ID, CRUMB_ID = "shot-img-lead", "shot-img-step", "shot-img-crumb"
LEAD_ALT = "A wedge of cornbread in a cast-iron skillet."
STEP_ALT = "Batter just brought together in a bowl."
CRUMB_ALT = "A close crop of the crumb."


def img(url, ident, alt):
    return f'<img src="{url}" alt="{alt}" data-nl-image-id="{ident}">'


HTML = (
    "<h1>Cast-Iron Cornbread</h1>"
    + img(LEAD, LEAD_ID, LEAD_ALT)
    + "<h2>Ingredients</h2>"
    "<ul><li>1 cup coarse yellow cornmeal</li><li>1 cup all-purpose flour</li>"
    "<li>1 tbsp baking powder</li><li>1 tsp fine salt</li></ul>"
    "<h3>To finish</h3>"
    "<ul><li>2 tbsp bacon fat, for the skillet</li>"
    "<li>Honey butter, to serve</li></ul>"
    "<h2>Method</h2>"
    "<ol><li>Put the skillet in the oven and heat it to 220C. The pan goes in "
    "cold and comes out screaming — that is the crust.</li>"
    "<li>Whisk the dry ingredients, then the buttermilk and eggs, and stop the "
    "moment it comes together." + img(STEP, STEP_ID, STEP_ALT) + "</li>"
    "<li>Swirl the bacon fat around the hot pan until it smokes.</li>"
    "<li>Pour the batter in — it should hiss — and bake 25 minutes until the "
    "edges pull away from the iron.</li></ol>"
    "<h2>Notes</h2>"
    "<ul><li>Coarse cornmeal is the whole texture; fine meal makes cake.</li>"
    "<li>Leftovers split and fried in butter are better than the first day."
    "</li></ul>"
    + img(CRUMB, CRUMB_ID, CRUMB_ALT)
)

put_doc("documents/shot-recipe", {
    "user_id": S(UID),
    "title": S("Cast-Iron Cornbread, Two Ways"),
    "type": S("youtube"),
    "mime_type": N,
    "status": S("complete"),
    "gcs_path": N,
    "source_url": S("https://www.youtube.com/watch?v=seedrecipe01"),
    "created_at": TS,
    "processed_at": TS,
    "chunk_count": I(1),
    "word_count": I(96),
    "summary": S("A skillet cornbread recipe from a cooking video."),
    "key_points": A([]),
    "themes": A([S("Cooking")]),
    "tag_ids": A([]),
    "error_message": N,
    "source_priority": D(0.5),
    "view_count": I(0),
    "last_viewed_at": N,
    "source_audio_url": N,
    "content_form": S("recipe"),
    "content_form_source": S("auto"),
    "content_form_override": N,
    # INV-20b — the full pre-distillation text. A durable URL, and the Original
    # panel is the only surface that may offer it.
    "original_content_url": S(put_object(
        "processed/seed-user-1/original/shot-recipe.html",
        b"<p>The complete transcript, before it was reduced to the recipe.</p>",
        "text/html")),
    "recipe": M({
        "title": S("Cast-Iron Cornbread"),
        "yield": S("Serves 8"),
        "prep_time": S("10 min"),
        "cook_time": S("25 min"),
        # Unstated by the source, and therefore ABSENT from the row rather than
        # a dash: a placeholder reads as a measured value.
        "total_time": N,
        "ingredients": A([
            M({"group": N, "items": A([
                S("1 cup coarse yellow cornmeal"),
                S("1 cup all-purpose flour"),
                S("1 tbsp baking powder"),
                S("1 tsp fine salt")])}),
            M({"group": S("To finish"), "items": A([
                S("2 tbsp bacon fat, for the skillet"),
                S("Honey butter, to serve")])}),
        ]),
        "steps": A([
            M({"text": S("Put the skillet in the oven and heat it to 220C. The "
                         "pan goes in cold and comes out screaming — that is "
                         "the crust."),
               "image_id": N, "start": D(42.0)}),
            M({"text": S("Whisk the dry ingredients, then the buttermilk and "
                         "eggs, and stop the moment it comes together."),
               "image_id": S(STEP_ID), "start": D(118.5)}),
            # No time on this one: the source never says when it happens, and
            # INV-20(c) makes the backend refuse to estimate rather than guess.
            M({"text": S("Swirl the bacon fat around the hot pan until it "
                         "smokes."),
               "image_id": N, "start": N}),
            M({"text": S("Pour the batter in — it should hiss — and bake 25 "
                         "minutes until the edges pull away from the iron."),
               "image_id": N, "start": D(305.0)}),
        ]),
        "notes": A([
            S("Coarse cornmeal is the whole texture; fine meal makes cake."),
            S("Leftovers split and fried in butter are better than the first "
              "day."),
        ]),
        "gallery": A([S(LEAD_ID), S(CRUMB_ID)]),
    }),
})

put_doc("chunks/shot-recipe-chunk-0", {
    "user_id": S(UID),
    "document_id": S("shot-recipe"),
    "chunk_index": I(0),
    "text": S("Cast-Iron Cornbread. Ingredients: coarse yellow cornmeal, "
              "all-purpose flour, baking powder, salt, bacon fat, honey "
              "butter. Method: heat the skillet, whisk the batter, swirl the "
              "fat, bake."),
    "html": S(HTML),
    "tag_ids": A([]),
    "source_type": S("youtube"),
    "source_priority": D(0.5),
    "user_edited": B(False),
    "created_at": TS,
    "view_count": I(0),
    "last_viewed_at": N,
})

# ── The image set: three pages, the middle one not yet landed ────────────────
SET_DIR = "raw/seed-user-1/image_set/shot-image-set"
put_object(f"{SET_DIR}/front.jpg", png(240, 320, (226, 176, 176), (150, 200, 170)),
           "image/jpeg")
put_object(f"{SET_DIR}/back.jpg", png(240, 320, (232, 200, 150), (160, 190, 200)),
           "image/jpeg")
# `middle.png` is deliberately NOT uploaded.

put_doc("documents/shot-image-set", {
    "user_id": S(UID),
    "title": S("Kitchen notebook, three pages"),
    "type": S("image_set"),
    "mime_type": S("image/jpeg"),
    "status": S("complete"),
    # A set has NO single gcs_path — which is exactly the value that made
    # `gcs_path != null` file it as a link.
    "gcs_path": N,
    "gcs_paths": A([S(f"{SET_DIR}/front.jpg"),
                    S(f"{SET_DIR}/middle.png"),
                    S(f"{SET_DIR}/back.jpg")]),
    "source_url": N,
    "created_at": TS,
    "processed_at": TS,
    "chunk_count": I(1),
    "word_count": I(12),
    "summary": S("Three photographed notebook pages."),
    "key_points": A([]),
    "themes": A([]),
    "tag_ids": A([]),
    "error_message": N,
    "source_priority": D(0.5),
    "view_count": I(0),
    "last_viewed_at": N,
    "content_form": N,
    "original_content_url": N,
})

put_doc("chunks/shot-image-set-chunk-0", {
    "user_id": S(UID),
    "document_id": S("shot-image-set"),
    "chunk_index": I(0),
    "text": S("Sourdough notes: keep the starter at room temperature."),
    "html": S("<p>Sourdough notes: keep the starter at room temperature.</p>"),
    "tag_ids": A([]),
    "source_type": S("image_set"),
    "source_priority": D(0.5),
    "user_edited": B(False),
    "created_at": TS,
    "view_count": I(0),
    "last_viewed_at": N,
})

# ── The canonical pdf document's bytes, so §15.1 has an object to show ───────
put_object("raw/seed-user-1/pdf/seed-doc-pdf-complete_taxes.pdf",
           b"%PDF-1.4\n% a stand-in for the quarterly tax summary\n",
           "application/pdf")

print("seeded shot-recipe, shot-image-set (2 of 3 pages), and the pdf object")
