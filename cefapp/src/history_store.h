#ifndef HISTORY_STORE_H
#define HISTORY_STORE_H
#include <string>
#include <vector>

struct HistoryEntry {
    std::string url;
    std::string title;
    long long visitedAt = 0;
    int visitCount = 1;
};

class HistoryStore {
public:
    static HistoryStore& instance();
    void record(const std::string& url, const std::string& title, long long now);
    std::vector<HistoryEntry> all() const;
    void clear();
    void load();
    void save();

private:
    HistoryStore();
    std::vector<HistoryEntry> entries_;
    std::string filePath_;
    static const int MAX_ENTRIES = 500;
    static const long MERGE_WINDOW_MS = 30 * 60 * 1000;
};

#endif
