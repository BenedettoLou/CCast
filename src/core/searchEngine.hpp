#pragma once
#include <cstddef>
#include <functional>
#include <string>
#include <vector>
#include "appDetail.hpp"

/*
 *
 * Pure C++ application index + fuzzy search.
 *
 */
class SearchEngine{
  
  public: 
    // given the absolute path of a .app, returns the name to show
    // (empty string = fall back to the bundle file name)
    using NameResolver = std::function<std::string(const std::string &path)>;

    SearchEngine();

    // directories scanned for .app bundles (a path may also be a single .app)
    void setSearchPaths(std::vector<std::string> paths);
    void setNameResolver(NameResolver resolver);

    // (re)builds the index scanning the search paths
    void indexApplications();

    // collection of appDetail s, best match first
    std::vector<AppDetail> query(const std::string &text, std::size_t limit = 20) const;

    std::size_t size() const { return _database.size(); }

    // relevance of `needle` inside `haystack` (both already normalized),
    // 0 = no match. Exposed for testing.
    static int score(const std::string &needle, const std::string &haystack);
    static std::string normalize(const std::string &text);

  private: 
    struct Entry {
      AppDetail app;
      std::string nameKey;   // normalized display name
      std::string fileKey;   // normalized bundle file name (e.g. "system settings")
    };

    void addApplication(const std::string &path);

    std::vector<std::string> _searchPaths;
    NameResolver _resolver;
    std::vector<Entry> _database;

};
