#include "CodexTOML.h"
#define TOML_EXCEPTIONS 0
#include "toml.hpp"

// toml++ 3.4.0, vendored unchanged from TOMLKit commit
// ec6198d37d495efc6acd4dffbd262cdca7ff9b3f (Sources/CTOML/Sources/toml.hpp).
// Keep ownership inside C++: no borrowed node pointers cross the Swift boundary.
bool codex_validate_feature_edit(const char *before, const char *after, const char *key, bool *was_enabled) {
    auto original = toml::parse(before);
    auto candidate = toml::parse(after);
    if (!original || !candidate) return false;
    auto expected = std::move(original).table();
    auto actual = std::move(candidate).table();
    if (expected.contains("features") && !expected["features"].is_table()) return false;
    if (!expected.contains("features")) expected.insert("features", toml::table{});
    auto &features = *expected["features"].as_table();
    *was_enabled = features["hooks"].value_or(false) || features["codex_hooks"].value_or(false);
    features.erase("hooks");
    features.erase("codex_hooks");
    if (key && *key) features.insert_or_assign(key, true);
    if (features.empty()) expected.erase("features");
    if (auto table = actual["features"].as_table(); table && table->empty()) actual.erase("features");
    return expected == actual;
}
