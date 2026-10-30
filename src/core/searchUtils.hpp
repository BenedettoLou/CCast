#pragma once
#include <string>

/*
 *
 * Search utilities: string normalization and scoring functions
 *
 */

namespace searchUtils {

// Trims leading and trailing whitespace
std::string trim(const std::string &s);

// ASCII case folding; non ASCII bytes (UTF-8) are kept as they are
std::string normalize(const std::string &text);

// Relevance of `needle` inside `haystack` (both already normalized),
// 0 = no match.
int score(const std::string &needle, const std::string &haystack);

} // namespace searchUtils

namespace SearchUtils = searchUtils;
