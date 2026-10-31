/* holyc/FFI.HC - C-ABI FFI Boundary for the HolyC Biblical Engine
 *
 * Exposes a minimal, stable C-compatible ABI for Rust:
 *   - scripture_init(const char *bible_path)
 *   - scripture_judge(const char *diagnostic, int64_t diagnostic_len,
 *                     char *output, int64_t output_capacity)
 *   - scripture_shutdown(void)
 * plus query helpers for direct verification of the HolyC parser and BM25 engine.
 */

#include "./Bible.HC"
#include "./Scripture.HC"
#include "./Judgment.HC"

public I64 scripture_init(U8 *bible_path)
{
  if (!bible_path) return -1;
  if (bible_path[0] == 0) return -1;
  I64 rc = BibleLoadFile(bible_path);
  if (rc < 0) return rc;
  I64 irc = ScriptureBuildIndex();
  if (irc < 0) {
    BibleFreeAll();
    return irc - 10;
  }
  return 0;
}

public I64 scripture_judge(U8 *diagnostic, I64 diagnostic_len,
                           U8 *output, I64 output_capacity)
{
  return JudgmentRender(diagnostic, diagnostic_len, output, output_capacity);
}

public U0 scripture_shutdown()
{
  ScriptureFreeIndex();
  BibleFreeAll();
}

public I64 scripture_verse_count()
{
  if (!g_bible_initialized) return 0;
  return g_verse_count;
}

public I64 scripture_book_count()
{
  if (!g_bible_initialized) return 0;
  return g_book_count;
}

public I64 scripture_vocab_count()
{
  if (!g_bible_initialized) return 0;
  return g_vocab_count;
}

public U0 scripture_set_seed(U64 seed)
{
  ScriptureSeedRng(seed);
}

public I64 scripture_lookup(U8 *reference, U8 *output, I64 output_capacity)
{
  U8 ref_norm[128];
  return ScriptureLookupReference(reference, output, output_capacity, ref_norm, 128);
}

public I64 scripture_search(U8 *query, U8 *out_ref, I64 ref_cap,
                            U8 *out_text, I64 text_cap)
{
  if (!g_bible_initialized || !query || !out_ref || !out_text) return -1;
  if (ref_cap <= 1 || text_cap <= 1) return -1;

  I64 idx = ScriptureSearchKeywords(query);
  if (idx < 0 || idx >= g_verse_count) return -2;

  CVerse *v = &g_verses[idx];
  ScriptureFormatCanonicalRef(v->book_idx, v->chapter, v->verse, v->verse,
                              out_ref, ref_cap);
  U8 *vtxt = BibleVerseText(idx);
  I64 copy_len = v->text_len;
  if (copy_len >= text_cap) copy_len = text_cap - 1;
  MemCpy(out_text, vtxt, copy_len);
  out_text[copy_len] = 0;
  return copy_len;
}
