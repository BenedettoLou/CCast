#include "searchClipboard.hpp"
#include "searchUtils.hpp"

#include <algorithm>
#include <iterator>

namespace {

  // drops an incomplete UTF-8 sequence left at the end of `s` by a byte cut
  void dropPartialUtf8Tail(std::string &s) {
    std::size_t i = s.size();
    std::size_t back = 0;
    while (i > 0 && back < 4) {
      --i; ++back;
      const auto b = static_cast<unsigned char>(s[i]);
      if ((b & 0xC0) == 0x80) continue;   // continuation byte, keep looking for the lead

      std::size_t len = 1;
      if      ((b >> 5) == 0x06) len = 2;
      else if ((b >> 4) == 0x0E) len = 3;
      else if ((b >> 3) == 0x1E) len = 4;
      if (i + len > s.size()) s.resize(i);
      return;
    }
  }

  // "3 lines · 84 chars" (chars = Unicode code points)
  std::string textSubtitle(const std::string &text) {
    std::size_t lines = 1;
    std::size_t chars = 0;
    for (char c : text) {
      if (c == '\n') ++lines;
      if ((static_cast<unsigned char>(c) & 0xC0) != 0x80) ++chars;
    }
    return std::to_string(lines) + (lines == 1 ? " line" : " lines") + " · " +
           std::to_string(chars) + (chars == 1 ? " char" : " chars");
  }

} // namespace

SearchClipboard::SearchClipboard(std::size_t maxEntries, std::size_t maxImages)
  : _maxEntries(maxEntries), _maxImages(maxImages) {
}

std::string SearchClipboard::makePreview(const std::string &text, std::size_t maxBytes) {
  std::string out;
  out.reserve(std::min(text.size(), maxBytes));

  bool inSpace = true;   // skips leading whitespace
  bool truncated = false;
  for (char c : text) {
    if (out.size() >= maxBytes) { truncated = true; break; }

    if (c == ' ' || c == '\t' || c == '\n' || c == '\r') {
      if (!inSpace) {
        out.push_back(' ');
        inSpace = true;
      }
    } else {
      out.push_back(c);
      inSpace = false;
    }
  }

  if (truncated) dropPartialUtf8Tail(out);
  while (!out.empty() && out.back() == ' ') out.pop_back();
  return out;
}

std::vector<SearchClipboard::Entry>::iterator
SearchClipboard::find(ClipboardKind kind, const std::string &payload) {
  return std::find_if(_history.begin(), _history.end(), [&](const Entry &e) {
    return e.item.kind == kind && e.item.payload == payload;
  });
}

bool SearchClipboard::add(ClipboardItem item,
                          const std::string &extraSearchTerms,
                          std::vector<ClipboardItem> *evicted) {
  if (item.payload.empty()) return false;

  const bool isText = (item.kind == ClipboardKind::Text);
  if (isText && item.payload.size() > kMaxTextBytes) return false;

  item.title = makePreview(item.title.empty() ? item.payload : item.title, kMaxPreviewBytes);
  if (item.title.empty()) return false;   // whitespace-only text
  if (isText && item.subtitle.empty()) item.subtitle = textSubtitle(item.payload);

  Entry e;
  const std::string searchText = isText ? makePreview(item.payload, kMaxSearchBytes) : item.title;
  e.searchKey = searchUtils::normalize(
    extraSearchTerms.empty() ? searchText : searchText + " " + extraSearchTerms);
  e.item = std::move(item);

  // already in history: drop the old occurrence so it moves to the top
  auto it = find(e.item.kind, e.item.payload);
  if (it != _history.end()) _history.erase(it);

  _history.insert(_history.begin(), std::move(e));
  enforceLimits(evicted);
  return true;
}

void SearchClipboard::enforceLimits(std::vector<ClipboardItem> *evicted) {
  auto drop = [&](std::vector<Entry>::iterator it) {
    if (evicted) evicted->push_back(std::move(it->item));
    return _history.erase(it);
  };

  while (_history.size() > _maxEntries) drop(std::prev(_history.end()));

  // images are the heavy entries: keep only the most recent ones
  std::size_t images = 0;
  for (auto it = _history.begin(); it != _history.end();) {
    if (it->item.kind == ClipboardKind::Image && ++images > _maxImages) it = drop(it);
    else ++it;
  }
}

bool SearchClipboard::promote(ClipboardKind kind, const std::string &payload) {
  auto it = find(kind, payload);
  if (it == _history.end()) return false;
  std::rotate(_history.begin(), it, std::next(it));
  return true;
}

bool SearchClipboard::remove(ClipboardKind kind, const std::string &payload) {
  auto it = find(kind, payload);
  if (it == _history.end()) return false;
  _history.erase(it);
  return true;
}

std::vector<ClipboardItem> SearchClipboard::query(const std::string &text, std::size_t limit) const {
  const std::string needle = searchUtils::normalize(text);

  // empty query: the most recent entries
  if (needle.empty()) {
    const std::size_t count = std::min(_history.size(), limit);
    std::vector<ClipboardItem> results;
    results.reserve(count);
    for (std::size_t i = 0; i < count; ++i) results.push_back(_history[i].item);
    return results;
  }

  struct Hit { int score; const Entry *entry; };
  std::vector<Hit> hits;

  for (const auto &e : _history) {
    const int s = searchUtils::score(needle, e.searchKey);
    if (s > 0) hits.push_back({s, &e});
  }

  // best score first; stable_sort keeps more recent entries first on ties
  std::stable_sort(hits.begin(), hits.end(), [](const Hit &a, const Hit &b) {
    return a.score > b.score;
  });

  if (hits.size() > limit) hits.resize(limit);

  std::vector<ClipboardItem> results;
  results.reserve(hits.size());
  for (const auto &hit : hits) results.push_back(hit.entry->item);
  return results;
}
