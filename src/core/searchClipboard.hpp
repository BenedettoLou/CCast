#pragma once
#include <cstddef>
#include <string>
#include <vector>
#include "appDetail.hpp"

/*
 *
 * Clipboard history + fuzzy search.
 *
 * Entries are kept from most recent to oldest (deduplicated).
 * AppDetail is reused:
 *   - name: single-line preview shown in the results list
 *   - path: full original text copied to the clipboard
 *
 */
class SearchClipboard {

  public:
    explicit SearchClipboard(std::size_t maxEntries = 50);

    // adds or promotes `text` to the top of the clipboard history
    // (ignores empty / whitespace-only strings)
    // returns the `path` of any evicted entry when capacity is exceeded
    std::string add(const std::string &text);

    // adds or promotes a generic entry (e.g. clipboard text, file, or image)
    // deduplicated by `path`; returns the `path` of any evicted entry
    std::string addEntry(const std::string &name,
                         const std::string &path,
                         const std::string &extraSearchTerms = "");

    // removes an entry matching `path`, returning true if found
    bool remove(const std::string &path);

    // matching entries (or the most recent ones when `text` is empty)
    std::vector<AppDetail> query(const std::string &text, std::size_t limit = 20) const;

    void clear() { _history.clear(); }
    std::size_t size() const { return _history.size(); }

  private:
    struct Entry {
      AppDetail item;
      std::string searchKey;   // normalized text for fuzzy matching
    };

    static std::string makePreview(const std::string &text);

    std::size_t _maxEntries;
    std::vector<Entry> _history;

};

