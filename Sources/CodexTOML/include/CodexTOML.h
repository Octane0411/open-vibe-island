#ifndef CODEX_TOML_H
#define CODEX_TOML_H
#include <stdbool.h>
#ifdef __cplusplus
extern "C" {
#endif
/// Parse both documents and compare the complete expected feature-only mutation.
bool codex_validate_feature_edit(const char *before, const char *after, const char *key, bool *was_enabled);
#ifdef __cplusplus
}
#endif
#endif
