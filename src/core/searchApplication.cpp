#include "searchApplication.hpp"
#include "searchUtils.hpp"

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

} // namespace

SearchApplication::SearchApplication() {
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

void SearchApplication::setSearchPaths(std::vector<std::string> paths) {
  _searchPaths = std::move(paths);
}

void SearchApplication::setNameResolver(NameResolver resolver) {
  _resolver = std::move(resolver);
}

/*
 * Indexing
 */

void SearchApplication::indexApplications() {
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

void SearchApplication::addApplication(const std::string &path) {
  const std::string fileName = fs::path(path).stem().string();

  std::string displayName;
  if (_resolver) displayName = searchUtils::trim(_resolver(path));
  if (displayName.empty()) displayName = fileName;

  Entry e;
  e.app.name = displayName;
  e.app.path = path;
  e.nameKey = searchUtils::normalize(displayName);
  e.fileKey = searchUtils::normalize(fileName);
  _database.push_back(std::move(e));
}

/*
 * Matching
 */

std::vector<AppDetail> SearchApplication::query(const std::string &text, std::size_t limit) const {
  const std::string needle = searchUtils::normalize(text);
  if (needle.empty()) return {};

  struct Hit { int score; const Entry *entry; };
  std::vector<Hit> hits;

  for (const auto &e : _database) {
    const int s = std::max(searchUtils::score(needle, e.nameKey), searchUtils::score(needle, e.fileKey));
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
