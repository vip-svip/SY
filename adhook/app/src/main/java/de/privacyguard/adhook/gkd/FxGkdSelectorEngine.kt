package de.privacyguard.adhook.gkd

import li.gkd.selector.Selector
import li.gkd.selector.SelectorParseResult

/**
 * FX-facing adapter for the upstream GKD-XA selector parser.
 * This stage provides real parser/tokenizer behavior only. Accessibility-tree
 * matching and automatic actions remain unavailable until the unified FX
 * runtime adapter is implemented and verified.
 */
data class FxGkdSelectorToken(
    val kind: String,
    val scope: String,
    val start: Int,
    val end: Int,
)

data class FxGkdSelectorValidation(
    val valid: Boolean,
    val source: String,
    val canonical: String?,
    val error: String?,
    val errorIndex: Int?,
    val tokens: List<FxGkdSelectorToken>,
)

object FxGkdSelectorEngine {
    private const val MAX_SOURCE_LENGTH = 16_384

    @JvmStatic
    fun validate(source: String): FxGkdSelectorValidation {
        if (source.length > MAX_SOURCE_LENGTH) {
            return FxGkdSelectorValidation(
                valid = false,
                source = source,
                canonical = null,
                error = "选择器超过 16,384 个字符上限",
                errorIndex = MAX_SOURCE_LENGTH,
                tokens = emptyList(),
            )
        }

        return when (val result = Selector.parse(source)) {
            is SelectorParseResult.Success -> FxGkdSelectorValidation(
                valid = true,
                source = source,
                canonical = result.value.toString(),
                error = null,
                errorIndex = null,
                tokens = result.tokens.map { token ->
                    FxGkdSelectorToken(
                        kind = token.kind.name,
                        scope = token.scope.name,
                        start = token.start,
                        end = token.end,
                    )
                },
            )
            is SelectorParseResult.Failure -> FxGkdSelectorValidation(
                valid = false,
                source = source,
                canonical = null,
                error = result.error.message,
                errorIndex = result.error.index,
                tokens = result.tokens.map { token ->
                    FxGkdSelectorToken(
                        kind = token.kind.name,
                        scope = token.scope.name,
                        start = token.start,
                        end = token.end,
                    )
                },
            )
        }
    }
}
