#include "searchUtils.hpp"

#include <algorithm>

namespace searchUtils {

namespace {

bool isWordSeparator(char c) {
  return c == ' ' || c == '-' || c == '_' || c == '.' || c == '(';
}

} // namespace

std::string trim(const std::string &s) {
  const auto begin = s.find_first_not_of(" \t\r\n");
  if (begin == std::string::npos) return {};
  const auto end = s.find_last_not_of(" \t\r\n");
  return s.substr(begin, end - begin + 1);
}

// ASCII case folding; non ASCII bytes (UTF-8) are kept as they are
std::string normalize(const std::string &text) {
  std::string out = trim(text);
  for (char &c : out) {
    if (c >= 'A' && c <= 'Z') c = static_cast<char>(c - 'A' + 'a');
  }
  return out;
}

int score(const std::string &needle, const std::string &haystack) {
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

} // namespace searchUtils
