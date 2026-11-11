// tool/share_body_check.sh — what the Share extension sends (F-197).

import Foundation

func expect(_ ok: Bool, _ what: String) {
    if !ok { print("FAIL: \(what)"); exit(1) }
    print("ok: \(what)")
}

@MainActor func run() async {
    let vm = UploadViewModel()
    let item = UploadItem(data: Data([1, 2, 3]), filename: "a.pdf", mimeType: "application/pdf")

    _ = await vm.uploadSingleFile(item, tagIds: [])
    let plain = APIClient.sent.last!
    expect(plain.path == "fn_create_upload_session", "a single file opens fn_create_upload_session")
    expect(plain.body["origin"] as? String == "share_sheet", "it says where it came from: origin share_sheet")
    expect(plain.body["filename"] as? String == "a.pdf" && plain.body["mimeType"] as? String == "application/pdf"
           && plain.body["size"] as? Int == 3, "filename, mimeType and size as before")
    expect(plain.body["tagIds"] == nil, "no shelves chosen: no tagIds key")
    expect(Set(plain.body.keys) == ["filename", "mimeType", "size", "origin"], "a closed key set")

    _ = await vm.uploadSingleFile(item, tagIds: ["t1"])
    let shelved = APIClient.sent.last!
    expect(shelved.body["origin"] as? String == "share_sheet", "with shelves: origin still sent")
    expect(shelved.body["tagIds"] as? [String] == ["t1"], "with shelves: tagIds beside it")

    _ = await vm.uploadImageSet([item], title: nil, tagIds: [])
    let set = APIClient.sent.last!
    expect(set.path == "fn_create_multi_image_session", "an image set opens fn_create_multi_image_session")
    expect(set.body["origin"] == nil, "an image set carries no origin, by contract")
}

await run()
print("PASS")
