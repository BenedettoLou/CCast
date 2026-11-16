#include "searchClipboard.hpp"
#include "searchUtils.hpp"

#include <algorithm>

SearchClipboard::SearchClipboard(std::size_t maxEntries)
  : _maxEntries(maxEntries) {
}

// collapses newlines and tabs into single spaces for a clean single-line row title
std::string SearchClipboard::makePreview(const std::string &text) {
  std::string out;
  out.reserve(text.size());

  bool inSpace = true;   // skips leading whitespace
  for (char c : text) {
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

  if (!out.empty() && out.back() == ' ') out.pop_back();
  return out;
}

std::string SearchClipboard::add(const std::string &text) {
  return addEntry(makePreview(text), text);
}

std::string SearchClipboard::addEntry(const std::string &name,
                                      const std::string &path,
                                      const std::string &extraSearchTerms) {
  const std::string preview = makePreview(name);
  if (preview.empty()) return {};

  // if already in history, remove the old occurrence so it moves to the top
  auto it = std::find_if(_history.begin(), _history.end(),
                         [&](const Entry &e) { return e.item.path == path; });
  if (it != _history.end()) {
    _history.erase(it);
  }

  Entry e;
  e.item.name = preview;
  e.item.path = path;
  e.searchKey = searchUtils::normalize(
    extraSearchTerms.empty() ? preview : (preview + " " + extraSearchTerms));

  _history.insert(_history.begin(), std::move(e));

  if (_history.size() > _maxEntries) {
    std::string evicted = std::move(_history.back().item.path);
    _history.pop_back();
    return evicted;
  }
  return {};
}

bool SearchClipboard::remove(const std::string &path) {
  auto it = std::find_if(_history.begin(), _history.end(),
                         [&](const Entry &e) { return e.item.path == path; });
  if (it == _history.end()) return false;
  _history.erase(it);
  return true;
}

std::vector<AppDetail> SearchClipboard::query(const std::string &text, std::size_t limit) const {
  const std::string needle = searchUtils::normalize(text);

  // empty query in clipboard mode: show the most recent entries
  if (needle.empty()) {
    const std::size_t count = std::min(_history.size(), limit);
    std::vector<AppDetail> results;
    results.reserve(count);
    for (std::size_t i = 0; i < count; ++i) {
      results.push_back(_history[i].item);
    }
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

  std::vector<AppDetail> results;
  results.reserve(hits.size());
  for (const auto &hit : hits) results.push_back(hit.entry->item);
  return results;
}

