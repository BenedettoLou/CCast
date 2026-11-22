#include "core/searchClipboard.hpp"

#include <cassert>
#include <iostream>
#include <string>
#include <vector>

namespace {

ClipboardItem makeText(const std::string &text) {
  ClipboardItem item;
  item.kind = ClipboardKind::Text;
  item.payload = text;
  return item;
}

ClipboardItem makeImage(const std::string &id, const std::string &title) {
  ClipboardItem item;
  item.kind = ClipboardKind::Image;
  item.payload = id;
  item.title = title;
  item.subtitle = "Image · 100 × 100 · 10 KB";
  return item;
}

ClipboardItem makeFile(const std::string &path, const std::string &name) {
  ClipboardItem item;
  item.kind = ClipboardKind::File;
  item.payload = path;
  item.title = name;
  item.subtitle = "File · " + path;
  return item;
}

void testTextAddPreviewAndDeduplication() {
  SearchClipboard cb(10, 5);

  // empty and whitespace-only rejected
  assert(!cb.add(makeText("")));
  assert(!cb.add(makeText("   \t\n\r  ")));
  assert(cb.size() == 0);

  // collapses whitespace into single-line preview and computes subtitle
  assert(cb.add(makeText("  hello\n\tworld  ")));
  assert(cb.size() == 1);
  auto res = cb.query("");
  assert(res.size() == 1);
  assert(res[0].title == "hello world");
  assert(res[0].payload == "  hello\n\tworld  ");
  assert(res[0].subtitle == "2 lines · 16 chars");

  // deduplication promotes existing entry to the top
  assert(cb.add(makeText("second")));
  assert(cb.add(makeText("  hello\n\tworld  ")));
  assert(cb.size() == 2);
  res = cb.query("");
  assert(res[0].title == "hello world");
  assert(res[1].title == "second");
}

void testSizeLimitsAndUtf8Truncation() {
  SearchClipboard cb(10, 5);

  // text over kMaxTextBytes is rejected
  std::string huge(SearchClipboard::kMaxTextBytes + 1, 'a');
  assert(!cb.add(makeText(huge)));
  assert(cb.size() == 0);

  // UTF-8 safe preview truncation (3-byte euro sign '€' = 0xE2 0x82 0xAC)
  std::string euros;
  for (int i = 0; i < 100; ++i) euros += "\xE2\x82\xAC";   // 300 bytes
  std::string preview = SearchClipboard::makePreview(euros, 10);
  // 10 bytes fits 3 full 3-byte chars = 9 bytes (partial 4th char dropped)
  assert(preview.size() == 9);
  assert(preview == "\xE2\x82\xAC\xE2\x82\xAC\xE2\x82\xAC");
}

void testEvictionAndImageCap() {
  SearchClipboard cb(4, 2);
  std::vector<ClipboardItem> evicted;

  assert(cb.add(makeImage("img1", "Image 10:00:01"), "image", &evicted));
  assert(cb.add(makeImage("img2", "Image 10:00:02"), "image", &evicted));
  assert(evicted.empty());

  // 3rd image evicts oldest image (img1) even though total entries <= 4
  assert(cb.add(makeImage("img3", "Image 10:00:03"), "image", &evicted));
  assert(evicted.size() == 1);
  assert(evicted[0].kind == ClipboardKind::Image);
  assert(evicted[0].payload == "img1");
  assert(cb.size() == 2);

  // fill to maxEntries (4), then push a 5th entry to evict oldest overall (img2)
  evicted.clear();
  assert(cb.add(makeText("t1"), "", &evicted));
  assert(cb.add(makeText("t2"), "", &evicted));
  assert(evicted.empty());
  assert(cb.add(makeText("t3"), "", &evicted));
  assert(evicted.size() == 1);
  assert(evicted[0].payload == "img2");
  assert(cb.size() == 4);
}

void testPromoteRemoveAndFuzzyQuery() {
  SearchClipboard cb(10, 5);

  assert(cb.add(makeText("alpha beta")));
  assert(cb.add(makeFile("/Users/leo/report.pdf", "report.pdf"), "file /Users/leo/report.pdf"));
  assert(cb.add(makeImage("img42", "Image 12:00:00"), "image screenshot png"));

  // extraSearchTerms allow finding images by "screenshot" and files by "file"
  auto imgHits = cb.query("screenshot");
  assert(imgHits.size() == 1);
  assert(imgHits[0].kind == ClipboardKind::Image);

  auto fileHits = cb.query("report");
  assert(fileHits.size() == 1);
  assert(fileHits[0].kind == ClipboardKind::File);

  // promote moves entry to front
  assert(cb.promote(ClipboardKind::Text, "alpha beta"));
  assert(!cb.promote(ClipboardKind::Text, "nonexistent"));
  auto all = cb.query("");
  assert(all[0].payload == "alpha beta");

  // remove deletes matching entry by kind + payload
  assert(!cb.remove(ClipboardKind::File, "alpha beta"));
  assert(cb.remove(ClipboardKind::Text, "alpha beta"));
  assert(cb.size() == 2);
}

} // namespace

int main() {
  testTextAddPreviewAndDeduplication();
  testSizeLimitsAndUtf8Truncation();
  testEvictionAndImageCap();
  testPromoteRemoveAndFuzzyQuery();
  std::cout << "All SearchClipboard tests passed.\n";
  return 0;
}
