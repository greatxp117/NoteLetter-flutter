"""Put a recording on the PDF seed document, for the `reader-listen` frame.

No seeded document carries audio, so the Listen section only ever draws its
"No narration yet." empty state, and the player — the subject of the frame —
cannot be photographed (F-43). This uploads a 12-second silent WAV to the
Storage emulator and writes its download URL to `seed-doc-pdf-complete`'s
`audio_url`: the TTS branch, so the eyebrow reads "narration". The reference's
shot (`theme-shots.mjs` `reader-listen`) stages the same thing.

`--remove` takes the field off again. Run it after the shot: every other reader
frame reads the same document.

    FIRESTORE_EMULATOR_HOST=localhost:8580 STORAGE_EMULATOR_HOST=http://localhost:9699 \\
      python3 tool/seed_listen_audio.py [--remove]

Writes with `Bearer owner`, which bypasses rules — a client cannot write
/documents (INV-04).
"""
import json, os, struct, sys, urllib.parse, urllib.request

FS = os.environ.get("FIRESTORE_EMULATOR_HOST", "localhost:8580")
ST = os.environ.get("STORAGE_EMULATOR_HOST", "http://localhost:9699")
BUCKET = os.environ.get("NL_BUCKET", "noteletter-7a111.firebasestorage.app")
DOC = (f"http://{FS}/v1/projects/noteletter-7a111/databases/(default)/documents"
       "/documents/seed-doc-pdf-complete")
OBJ = "audio/seed-user-1/shot-narration.wav"
HEAD = {"Authorization": "Bearer owner"}


def call(url, method, body=None, ctype="application/json"):
    req = urllib.request.Request(url, data=body, method=method,
                                 headers={**HEAD, "Content-Type": ctype})
    with urllib.request.urlopen(req) as r:
        return json.loads(r.read() or b"{}")


def silent_wav(seconds):
    rate, n = 8000, 8000 * seconds
    return (b"RIFF" + struct.pack("<I", 36 + n) + b"WAVEfmt " +
            struct.pack("<IHHIIHH", 16, 1, 1, rate, rate, 1, 8) +
            b"data" + struct.pack("<I", n) + bytes([128]) * n)


def patch(fields):
    call(f"{DOC}?updateMask.fieldPaths=audio_url", "PATCH",
         json.dumps({"fields": fields}).encode())


if "--remove" in sys.argv:
    patch({})
    print("removed audio_url from seed-doc-pdf-complete")
    sys.exit(0)

base = f"{ST}/v0/b/{BUCKET}/o"
enc = urllib.parse.quote(OBJ, safe="")
call(f"{base}?name={enc}&uploadType=media", "POST", silent_wav(12), "audio/wav")
meta = call(f"{base}/{enc}", "PATCH", json.dumps({"contentType": "audio/wav"}).encode())
url = f"{base}/{enc}?alt=media&token={meta['downloadTokens']}"
patch({"audio_url": {"stringValue": url}})
print(f"seed-doc-pdf-complete.audio_url = {url}")
