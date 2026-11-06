#ifndef BOOKMARKS_H
#define BOOKMARKS_H
#include <string>
#include <vector>

/// One bookmark. Field set mirrors the Android `Bookmark` model so the same
/// JSON can be read on both platforms.
struct Bookmark {
    std::string id;
    std::string title;
    std::string url;
    std::string glyph;      // 1-2 characters; empty = derive from title
    int colorSeed = -1;     // -1 = derive from URL
    std::string icon;       // favicon file name; empty = none
    long long createdAt = 0;
    long long updatedAt = 0;
};

class BookmarkStore {
public:
    static BookmarkStore& instance();

    /// Add a bookmark. Returns false when the URL is invalid or already present.
    bool add(const std::string& title, const std::string& url);
    /// Add with an explicit id (used by backup import).
    bool addRecord(const Bookmark& record);
    /// Remove by URL (canonical match).
    bool remove(const std::string& url);
    /// Remove by id.
    bool removeById(const std::string& id);
    /// Update title/url of the record with `id`.
    bool update(const std::string& id, const std::string& title, const std::string& url);
    /// Find a record by canonical URL.
    bool find(const std::string& url, Bookmark& out) const;

    std::vector<Bookmark> all() const { return bookmarks_; }
    void clear();
    void load();
    void save();
    std::string filePath() const { return filePath_; }
    std::string iconsDir() const;

    /// Deterministic monogram for a bookmark (glyph, else title, else host).
    static std::string monogram(const Bookmark& b);
    /// Deterministic palette index 0..7 from the URL.
    static int colorIndex(const Bookmark& b);

private:
    BookmarkStore();
    std::vector<Bookmark> bookmarks_;
    std::string filePath_;
};

#endif
