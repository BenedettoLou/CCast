#include "searchFile.hpp"
#include "searchUtils.hpp"

#include <algorithm>
#include <cstdlib>
#include <filesystem>
#include <system_error>

namespace fs = std::filesystem;

SearchFile::SearchFile(){
}

bool SearchFile::exists(const std::string &path){
  std::error_code ec;
  return fs::exists(path, ec);
}

bool SearchFile::isDirectory(const std::string &path){
  std::error_code ec;
  return fs::is_directory(path, ec);
}

void SearchFile::splitPath(const std::string &text, std::string &dir, std::string &name){
  const auto slash = text.find_last_of('/');
  dir  = text.substr(0, slash + 1);    // keeps the trailing '/'
  name = text.substr(slash + 1);
}

std::string SearchFile::expand(const std::string &text){
  if (!text.empty() && text[0] == '/') return text;   // absolute

  const char *envHome = std::getenv("HOME");
  const std::string home = envHome ? envHome : "";

  if (text.empty()) return home + "/";
  if (text == "~") return home;
  if (text.compare(0, 2, "~/") == 0) return home + text.substr(1);

  return home + "/" + text;   // relative to home
}

std::vector<AppDetail> SearchFile::query(const std::string &text, std::size_t limit) const {
  std::string dir, name;
  splitPath(expand(text), dir, name);

  if (!isDirectory(dir)) return {};

  const std::string needle = searchUtils::normalize(name);
  const bool showHidden = !name.empty() && name[0] == '.';

  struct Hit { int score; bool isDir; AppDetail file; };
  std::vector<Hit> hits;

  std::error_code ec;
  fs::directory_iterator it(dir, fs::directory_options::skip_permission_denied, ec);
  const fs::directory_iterator end;

  for (; !ec && it != end; it.increment(ec)) {
    const std::string fileName = it->path().filename().string();

    // hidden files (".git", ".zshrc", ...) only if the user types the dot
    if (!showHidden && !fileName.empty() && fileName[0] == '.') continue;

    // empty filter ("/Users/me/") lists the whole directory
    int s = 1;
    if (!needle.empty()) {
      s = searchUtils::score(needle, searchUtils::normalize(fileName));
      if (s == 0) continue;
    }

    std::error_code dirEc;
    const bool isDir = it->is_directory(dirEc);
    hits.push_back({s, isDir, {fileName, (fs::path(dir) / fileName).string()}});
  }

  // best score first, then folders before files, then alphabetical
  std::sort(hits.begin(), hits.end(), [](const Hit &a, const Hit &b) {
    if (a.score != b.score) return a.score > b.score;
    if (a.isDir != b.isDir) return a.isDir;
    return searchUtils::normalize(a.file.name) < searchUtils::normalize(b.file.name);
  });

  if (hits.size() > limit) hits.resize(limit);

  std::vector<AppDetail> results;
  results.reserve(hits.size());
  for (auto &hit : hits) results.push_back(std::move(hit.file));
  return results;
}
