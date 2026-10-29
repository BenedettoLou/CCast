#include "searchEngine.hpp"

#include <algorithm>
#include <cstdlib>
#include <filesystem>
#include <system_error>
#include <unordered_set>

namespace fs = std::filesystem;

namespace {

  // how deep to look inside a search path (e.g. /Applications/Adobe X/Foo.app)
  constexpr int kMaxDepth = 3;

  bool isAppBundle(const fs::path &p) {
    return p.extension() == ".app";
  }

  bool isWordSeparator(char c) {
    return c == ' ' || c == '-' || c == '_' || c == '.' || c == '(';
  }

  std::string trim(const std::string &s) {
    const auto begin = s.find_first_not_of(" \t\r\n");
    if (begin == std::string::npos) return {};
    const auto end = s.find_last_not_of(" \t\r\n");
    return s.substr(begin, end - begin + 1);
  }

} // namespace

SearchEngine::SearchEngine() {
  _searchPaths = {
    "/Applications",
    "/System/Applications",
    "/System/Library/CoreServices/Applications",
    "/System/Library/CoreServices/Finder.app",
  };

  if (const char *home = std::getenv("HOME")) {
    _searchPaths.push_back(std::string(home) + "/Applications");
  }
}

void SearchEngine::setSearchPaths(std::vector<std::string> paths) {
  _searchPaths = std::move(paths);
}

void SearchEngine::setNameResolver(NameResolver resolver) {
  _resolver = std::move(resolver);
}

/*
 * Indexing
 */

void SearchEngine::indexApplications() {
  _database.clear();
  std::unordered_set<std::string> seen;   // canonical paths, avoids duplicates

  auto add = [&](const fs::path &p) {
    std::error_code ec;
    fs::path canonical = fs::weakly_canonical(p, ec);
    const std::string key = ec ? p.string() : canonical.string();
    if (seen.insert(key).second) addApplication(p.string());
  };

  for (const auto &root : _searchPaths) {
    std::error_code ec;
    const fs::path rootPath(root);

    if (!fs::is_directory(rootPath, ec)) continue;

    // the search path is itself an app (e.g. Finder.app)
    if (isAppBundle(rootPath)) { add(rootPath); continue; }

    fs::recursive_directory_iterator it(
      rootPath, fs::directory_options::skip_permission_denied, ec);
    const fs::recursive_directory_iterator end;

    for (; !ec && it != end; it.increment(ec)) {
      std::error_code entryEc;
      if (!it->is_directory(entryEc)) continue;

      if (isAppBundle(it->path())) {
        add(it->path());
        it.disable_recursion_pending();   // never look inside a bundle
      } else if (it.depth() + 1 >= kMaxDepth) {
        it.disable_recursion_pending();
      }
    }
  }

  // stable, predictable order (also used as last tie-breaker)
  std::sort(_database.begin(), _database.end(), [](const Entry &a, const Entry &b) {
    return a.nameKey < b.nameKey;
  });
}

void SearchEngine::addApplication(const std::string &path) {
  const std::string fileName = fs::path(path).stem().string();

  std::string displayName;
  if (_resolver) displayName = trim(_resolver(path));
  if (displayName.empty()) displayName = fileName;

  Entry e;
  e.app.name = displayName;
  e.app.path = path;
  e.nameKey = normalize(displayName);
  e.fileKey = normalize(fileName);
  _database.push_back(std::move(e));
}

/*
 * Matching
 */

// ASCII case folding; non ASCII bytes (UTF-8) are kept as they are
std::string SearchEngine::normalize(const std::string &text) {
  std::string out = trim(text);
  for (char &c : out) {
    if (c >= 'A' && c <= 'Z') c = static_cast<char>(c - 'A' + 'a');
  }
  return out;
}

int SearchEngine::score(const std::string &needle, const std::string &haystack) {
  if (needle.empty() || haystack.empty()) return 0;

  // 1. exact match
  if (haystack == needle) return 1000;

  if (needle.size() <= haystack.size()) {
    const int extra = static_cast<int>(haystack.size() - needle.size());

    // 2. prefix: "saf" -> "safari" (shorter names win)
    if (haystack.compare(0, needle.size(), needle) == 0) {
      return 900 - std::min(extra, 99);
    }

    // 3. substring: at a word start ("code" -> "visual studio code") or anywhere
    int best = 0;
    for (std::size_t pos = haystack.find(needle); pos != std::string::npos;
         pos = haystack.find(needle, pos + 1)) {
      const int p = std::min(static_cast<int>(pos), 99);
      const int s = isWordSeparator(haystack[pos - 1]) ? 700 - p : 500 - p;
      best = std::max(best, s);
    }
    if (best > 0) return best;
  }

  // 4. fuzzy subsequence: "vsc" -> "Visual Studio Code"
  //    bonus for word starts and consecutive characters, penalty for gaps
  int s = 100;
  std::size_t h = 0;
  std::size_t lastMatch = std::string::npos;

  for (char c : needle) {
    if (c == ' ') continue;   // spaces in the query are optional

    while (h < haystack.size() && haystack[h] != c) ++h;
    if (h == haystack.size()) return 0;   // character not found

    if (h == 0 || isWordSeparator(haystack[h - 1])) s += 20;
    if (lastMatch != std::string::npos) {
      if (h == lastMatch + 1) s += 10;
      else s -= static_cast<int>(std::min<std::size_t>(h - lastMatch - 1, 10));
    }

    lastMatch = h++;
  }

  return std::clamp(s, 1, 399);
}

std::vector<AppDetail> SearchEngine::query(const std::string &text, std::size_t limit) const {
  const std::string needle = normalize(text);
  if (needle.empty()) return {};

  struct Hit { int score; const Entry *entry; };
  std::vector<Hit> hits;

  for (const auto &e : _database) {
    const int s = std::max(score(needle, e.nameKey), score(needle, e.fileKey));
    if (s > 0) hits.push_back({s, &e});
  }

  std::stable_sort(hits.begin(), hits.end(), [](const Hit &a, const Hit &b) {
    if (a.score != b.score) return a.score > b.score;
    return a.entry->nameKey.size() < b.entry->nameKey.size();
  });

  if (hits.size() > limit) hits.resize(limit);

  std::vector<AppDetail> results;
  results.reserve(hits.size());
  for (const auto &hit : hits) results.push_back(hit.entry->app);
  return results;
}
