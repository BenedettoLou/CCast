#pragma once
#include <cstddef>
#include <string>
#include <vector>
#include "appDetail.hpp"

/*
 *
 * Searching files with path submitted
 *
 * The typed path is first expanded (see expand), then split at the last '/':
 *   "~/Doc"  ->  directory "/Users/me/"  +  name filter "Doc"
 * the entries of the directory are matched against the filter
 * (same scoring as the application search).
 *
 */

class SearchFile{

  public:
    SearchFile();

    // entries of the directory being typed, best match first
    // (AppDetail is reused: name = file name, path = absolute path)
    std::vector<AppDetail> query(const std::string &text, std::size_t limit) const;

    // typed path -> absolute path
    //   ""        -> "$HOME/"
    //   "~/bin"   -> "$HOME/bin"
    //   "/usr"    -> "/usr"          (already absolute)
    //   "Desktop" -> "$HOME/Desktop" (relative paths start from home)
    static std::string expand(const std::string &text);

    // true if `path` exists on disk (file or directory), path already expanded
    static bool exists(const std::string &path);
    static bool isDirectory(const std::string &path);

  private:
    // splits "/a/b/c" into "/a/b/" and "c"
    static void splitPath(const std::string &text, std::string &dir, std::string &name);

};
