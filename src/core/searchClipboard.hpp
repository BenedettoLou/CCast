#pragma once
#include <cstddef>
#include <string>
#include <vector>

/*
 *
 * Clipboard history + fuzzy search (no Cocoa dependency).
 *
 * Entries are kept from most recent to oldest, deduplicated by kind + payload.
 * Memory is bounded: at most `maxEntries` entries, of which at most `maxImages`
 * images; text larger than kMaxTextBytes is not recorded, and previews /
 * search keys only use the beginning of the text.
 *
 */

enum class ClipboardKind { Text, Image, File };

struct ClipboardItem {
  ClipboardKind kind = ClipboardKind::Text;
  std::string payload;    // Text: full text, File: absolute path, Image: image id (owned by the UI)
  std::string title;      // single-line preview shown in the list (derived from the text if empty)
  std::string subtitle;   // detail line, e.g. "3 lines · 84 chars" (derived for text if empty)
};

class SearchClipboard {

  public:
    static constexpr std::size_t kMaxTextBytes    = 1 << 20;   // bigger copies are ignored
    static constexpr std::size_t kMaxPreviewBytes = 256;       // title length
    static constexpr std::size_t kMaxSearchBytes  = 2048;      // text prefix used for matching

    explicit SearchClipboard(std::size_t maxEntries = 50, std::size_t maxImages = 10);

    // adds `item` on top of the history, or promotes it if already present.
    // Returns false if the item was rejected (empty, or text over kMaxTextBytes).
    // Entries dropped to respect the limits are appended to `evicted` (if given).
    bool add(ClipboardItem item,
             const std::string &extraSearchTerms = "",
             std::vector<ClipboardItem> *evicted = nullptr);

    // moves an existing entry to the top, returns false if not found
    bool promote(ClipboardKind kind, const std::string &payload);

    // removes an entry, returns false if not found
    bool remove(ClipboardKind kind, const std::string &payload);

    // matching entries, best first (or the most recent ones when `text` is empty)
    std::vector<ClipboardItem> query(const std::string &text, std::size_t limit = 20) const;

    void clear() { _history.clear(); }
    std::size_t size() const { return _history.size(); }

    // collapses whitespace runs into single spaces, keeps at most `maxBytes`
    // bytes without splitting a UTF-8 character
    static std::string makePreview(const std::string &text, std::size_t maxBytes);

  private:
    struct Entry {
      ClipboardItem item;
      std::string searchKey;   // normalized text for fuzzy matching
    };

    std::vector<Entry>::iterator find(ClipboardKind kind, const std::string &payload);
    void enforceLimits(std::vector<ClipboardItem> *evicted);

    std::size_t _maxEntries;
    std::size_t _maxImages;
    std::vector<Entry> _history;

};
