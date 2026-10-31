/* holyc/Judgment.HC - HolyC Biblical Fuzzy Search Judgment Engine
 *
 * Combines:
 *   1. Diagnostic tokenization & Rust->KJV synonym expansion
 *   2. BM25 ranking over all 31,102 verses in Bible.TXT
 *   3. Weighted random selection among Top 5-10 BM25 verses
 *   4. Book of Revelation (Apocalypse) random fallback when no match is found
 *   5. Theological sin classification & TempleOS judgment rendering
 */

#define SIN_ABSOLVED         0
#define SIN_MUTABLE_ALIASING 1
#define SIN_OWNERSHIP        2
#define SIN_BORROW           3
#define SIN_LIFETIME         4
#define SIN_TYPE_MISMATCH    5
#define SIN_MISSING_TRAIT    6
#define SIN_UNDEFINED        7
#define SIN_UNUSED           8
#define SIN_UNSAFE           9
#define SIN_EXCESS           10
#define SIN_APOCALYPSE       11

public class CDiagnosticInput
{
  U8 level[32];
  U8 code[64];
  U8 location[256];
  U8 message[1024];
  U8 notes[1024];
  I32 use_color;
  I32 is_absolve;
  I32 deterministic;
};

public class CJudgmentPlan
{
  I32 category;
  U8 *book_header;
  U8 *sin_title;
  U8 *theme;
  U8 *commentary;
  U8 *curated_ref;
};

Bool HcContainsI(U8 *haystack, U8 *needle)
{
  if (!haystack || !needle) return FALSE;
  if (needle[0] == 0) return FALSE;
  I64 hlen = StrLen(haystack);
  I64 nlen = StrLen(needle);
  if (nlen > hlen) return FALSE;

  I64 limit = hlen - nlen;
  I64 i = 0;
  while (i <= limit) {
    I64 j = 0;
    while (j < nlen) {
      if (HcToLower(haystack[i + j]) != HcToLower(needle[j]))
        break;
      j++;
    }
    if (j == nlen) return TRUE;
    i++;
  }
  return FALSE;
}

U0 HcCopyTrimmed(U8 *dst, I64 dst_cap, U8 *src, I64 src_len)
{
  if (!dst || dst_cap <= 0) return;
  dst[0] = 0;
  if (!src || src_len <= 0) return;

  I64 start = 0;
  while (start < src_len && HcIsSpace(src[start])) start++;
  while (src_len > start && HcIsSpace(src[src_len - 1])) src_len--;
  I64 len = src_len - start;
  if (len <= 0) return;
  if (len >= dst_cap) len = dst_cap - 1;
  MemCpy(dst, src + start, len);
  dst[len] = 0;
}

Bool HcExtractJsonStr(U8 *raw, I64 raw_len, U8 *key, U8 *out_val, I64 out_cap)
{
  if (!raw || raw_len <= 0 || !key || !out_val || out_cap <= 1) return FALSE;
  I64 klen = StrLen(key);
  I64 i = 0;
  while (i + klen < raw_len) {
    if (raw[i] == '"' && StrNCmp(raw + i + 1, key, klen) == 0 && raw[i + 1 + klen] == '"') {
      I64 p = i + 2 + klen;
      while (p < raw_len && (raw[p] == ' ' || raw[p] == '\t' || raw[p] == ':'))
        p++;
      if (p < raw_len && raw[p] == '"') {
        p++;
        I64 out_pos = 0;
        while (p < raw_len && raw[p] != '"' && out_pos + 1 < out_cap) {
          if (raw[p] == '\\' && p + 1 < raw_len) {
            p++;
            if (raw[p] == 'n') out_val[out_pos++] = ' ';
            else out_val[out_pos++] = raw[p];
          } else {
            out_val[out_pos++] = raw[p];
          }
          p++;
        }
        out_val[out_pos] = 0;
        return (out_pos > 0);
      }
    }
    i++;
  }
  return FALSE;
}

Bool HcExtractErrorCode(U8 *text, I64 len, U8 *out_code, I64 out_cap)
{
  if (!text || len < 5 || !out_code || out_cap < 6) return FALSE;
  I64 i = 0;
  while (i + 4 < len) {
    if ((text[i] == 'E' || text[i] == 'e') &&
        HcIsDigit(text[i + 1]) && HcIsDigit(text[i + 2]) &&
        HcIsDigit(text[i + 3]) && HcIsDigit(text[i + 4])) {
      Bool prev_ok = TRUE;
      if (i > 0 && HcIsAlnum(text[i - 1])) prev_ok = FALSE;
      Bool next_ok = TRUE;
      if (i + 5 < len && HcIsAlnum(text[i + 5])) next_ok = FALSE;
      if (prev_ok && next_ok) {
        out_code[0] = 'E';
        MemCpy(out_code + 1, text + i + 1, 4);
        out_code[5] = 0;
        return TRUE;
      }
    }
    i++;
  }
  return FALSE;
}

U0 JudgmentParseDiagnostic(U8 *diag, I64 diag_len, CDiagnosticInput *out)
{
  MemSet(out, 0, sizeof(CDiagnosticInput));
  StrCpy(out->level, "error");
  out->use_color = 0;
  out->is_absolve = 0;
  out->deterministic = 0;

  if (!diag || diag_len <= 0) {
    out->is_absolve = 1;
    return;
  }

  if (HcStrStartsWithI(diag, "ABSOLVE")) {
    out->is_absolve = 1;
    if (HcContainsI(diag, "COLOR: 1") || HcContainsI(diag, "color=1"))
      out->use_color = 1;
    return;
  }

  if (HcStrStartsWithI(diag, "LEVEL:") || HcStrStartsWithI(diag, "CODE:") ||
      HcStrStartsWithI(diag, "MESSAGE:")) {
    I64 pos = 0;
    while (pos < diag_len) {
      I64 lstart = pos;
      while (pos < diag_len && diag[pos] != '\n') pos++;
      I64 lend = pos;
      if (pos < diag_len && diag[pos] == '\n') pos++;
      I64 llen = lend - lstart;
      U8 *lptr = diag + lstart;

      if (llen >= 6 && HcStrStartsWithI(lptr, "LEVEL:")) {
        HcCopyTrimmed(out->level, 32, lptr + 6, llen - 6);
      } else if (llen >= 5 && HcStrStartsWithI(lptr, "CODE:")) {
        HcCopyTrimmed(out->code, 64, lptr + 5, llen - 5);
      } else if (llen >= 9 && HcStrStartsWithI(lptr, "LOCATION:")) {
        HcCopyTrimmed(out->location, 256, lptr + 9, llen - 9);
      } else if (llen >= 6 && HcStrStartsWithI(lptr, "COLOR:")) {
        U8 cbuf[16];
        HcCopyTrimmed(cbuf, 16, lptr + 6, llen - 6);
        if (cbuf[0] == '1' || HcStrEqI(cbuf, "true"))
          out->use_color = 1;
      } else if (llen >= 14 && HcStrStartsWithI(lptr, "DETERMINISTIC:")) {
        U8 dbuf[16];
        HcCopyTrimmed(dbuf, 16, lptr + 14, llen - 14);
        if (dbuf[0] == '1' || HcStrEqI(dbuf, "true"))
          out->deterministic = 1;
      } else if (llen >= 8 && HcStrStartsWithI(lptr, "MESSAGE:")) {
        HcCopyTrimmed(out->message, 1024, lptr + 8, llen - 8);
      } else if (llen >= 6 && HcStrStartsWithI(lptr, "NOTES:")) {
        HcCopyTrimmed(out->notes, 1024, lptr + 6, llen - 6);
      }
    }
    if (HcStrEqI(out->level, "absolve") || HcStrEqI(out->code, "ABSOLVE")) {
      out->is_absolve = 1;
    }
    if (!out->code[0] && out->message[0]) {
      HcExtractErrorCode(out->message, StrLen(out->message), out->code, 64);
    }
    return;
  }

  if (diag[0] == '{') {
    HcExtractJsonStr(diag, diag_len, "level", out->level, 32);
    HcExtractJsonStr(diag, diag_len, "code", out->code, 64);
    HcExtractJsonStr(diag, diag_len, "message", out->message, 1024);
    HcExtractJsonStr(diag, diag_len, "file_name", out->location, 256);
    if (!out->message[0]) {
      HcCopyTrimmed(out->message, 1024, diag, diag_len);
    }
    if (!out->code[0]) {
      HcExtractErrorCode(diag, diag_len, out->code, 64);
    }
    return;
  }

  HcCopyTrimmed(out->message, 1024, diag, diag_len);
  HcExtractErrorCode(diag, diag_len, out->code, 64);
  if (HcStrStartsWithI(out->message, "warning")) {
    StrCpy(out->level, "warning");
  }

  if (out->code[0] && HcStrStartsWithI(out->message, out->code)) {
    I64 clen = StrLen(out->code);
    if (out->message[clen] == ':' && out->message[clen + 1] == ' ') {
      U8 cleaned[1024];
      StrCpy(cleaned, out->message + clen + 2);
      StrCpy(out->message, cleaned);
    }
  }
}

U0 JudgmentClassify(CDiagnosticInput *in, CJudgmentPlan *plan)
{
  MemSet(plan, 0, sizeof(CJudgmentPlan));

  if (in->is_absolve) {
    plan->category = SIN_ABSOLVED;
    plan->book_header = "THE BOOK OF ABSOLUTION";
    plan->sin_title = "BLESSING OF THE RIGHTEOUS";
    plan->theme = "forgiveness_salvation_blessing";
    plan->commentary = "Thy code hath been examined, and no transgression was found.";
    plan->curated_ref = "Numbers 6:24-26";
    return;
  }

  U8 *code = in->code;
  U8 *msg = in->message;

  /* 1. Mutable aliasing (E0499) */
  if (HcStrEqI(code, "E0499") ||
      HcContainsI(msg, "as mutable more than once") ||
      HcContainsI(msg, "second mutable borrow")) {
    plan->category = SIN_MUTABLE_ALIASING;
    plan->book_header = "THE BOOK OF BORROWINGS";
    plan->sin_title = "THE SECOND BORROW";
    plan->theme = "serving_two_masters";
    plan->commentary =
      "Thou hast taken a second mutable borrow whilst the first yet liveth.";
    plan->curated_ref = "Matthew 6:24";
    return;
  }

  /* 2. Ownership violations (E0382, E0507, E0508, E0509, E0381, E0384) */
  if (HcStrEqI(code, "E0382") ||
      HcContainsI(msg, "use of moved value") ||
      HcContainsI(msg, "value borrowed here after move") ||
      HcContainsI(msg, "borrow of moved value") ||
      HcContainsI(msg, "value used here after move")) {
    plan->category = SIN_OWNERSHIP;
    plan->book_header = "THE BOOK OF POSSESSIONS";
    plan->sin_title = "TAKING WHAT NO LONGER BELONGETH TO THEE";
    plan->theme = "theft_and_possession";
    plan->commentary =
      "Thou hast reached forth thine hand to lay hold upon a value already moved hence.";
    plan->curated_ref = "Job 1:21";
    return;
  }

  if (HcStrEqI(code, "E0507") || HcStrEqI(code, "E0508") || HcStrEqI(code, "E0509") ||
      HcContainsI(msg, "cannot move out of")) {
    plan->category = SIN_OWNERSHIP;
    plan->book_header = "THE BOOK OF POSSESSIONS";
    plan->sin_title = "PLUNDERING A BORROWED VESSEL";
    plan->theme = "covetousness_and_theft";
    plan->commentary =
      "Thou hast sought to carry away the substance of a vessel that is only lent unto thee.";
    plan->curated_ref = "Exodus 20:17";
    return;
  }

  if (HcStrEqI(code, "E0384") ||
      HcContainsI(msg, "cannot assign twice to immutable")) {
    plan->category = SIN_OWNERSHIP;
    plan->book_header = "THE BOOK OF POSSESSIONS";
    plan->sin_title = "ALTERING AN IMMUTABLE COVENANT";
    plan->theme = "unchanging_covenant";
    plan->commentary =
      "Thou hast sought to mutate that which was sworn immutable; what is sealed may not be rewritten.";
    plan->curated_ref = "Malachi 3:6";
    return;
  }

  if (HcStrEqI(code, "E0381") ||
      HcContainsI(msg, "possibly-uninitialized") ||
      HcContainsI(msg, "isn't initialized") ||
      HcContainsI(msg, "uninitialized variable")) {
    plan->category = SIN_OWNERSHIP;
    plan->book_header = "THE BOOK OF GENESIS";
    plan->sin_title = "ORIGINAL SIN OF UNINITIALIZED KNOWLEDGE";
    plan->theme = "forbidden_knowledge_and_the_void";
    plan->commentary =
      "Thou hast reached for forbidden knowledge from a vessel before any substance was breathed into it.";
    plan->curated_ref = "Genesis 3:5";
    return;
  }

  /* 3. Borrow checker violations (E0502, E0503, E0505, E0506, E0596) */
  if (HcStrEqI(code, "E0502") || HcStrEqI(code, "E0503") ||
      HcStrEqI(code, "E0505") || HcStrEqI(code, "E0506") ||
      HcStrEqI(code, "E0596") || HcStrEqI(code, "E0594") ||
      HcContainsI(msg, "cannot borrow") ||
      HcContainsI(msg, "because it is borrowed")) {
    plan->category = SIN_BORROW;
    plan->book_header = "THE BOOK OF BORROWINGS";
    plan->sin_title = "FORBIDDEN POSSESSION";
    plan->theme = "debts_and_obligations";
    plan->commentary =
      "Thou hast mingled mutable and immutable pledges over the same vessel whilst an existing borrow yet abideth.";
    plan->curated_ref = "Proverbs 22:7";
    return;
  }

  /* 4. Lifetime errors (E0597, E0106, E0495, E0515, E0716, E0621, E0310) */
  if (HcStrEqI(code, "E0597") || HcStrEqI(code, "E0106") ||
      HcStrEqI(code, "E0515") || HcStrEqI(code, "E0716") ||
      HcStrEqI(code, "E0495") || HcStrEqI(code, "E0621") || HcStrEqI(code, "E0310") ||
      HcContainsI(msg, "does not live long enough") ||
      HcContainsI(msg, "missing lifetime specifier") ||
      HcContainsI(msg, "temporary value dropped while borrowed") ||
      HcContainsI(msg, "lifetime may not live long enough")) {
    plan->category = SIN_LIFETIME;
    plan->book_header = "THE BOOK OF ETERNITY";
    plan->sin_title = "MORTALITY OF THE BORROWED";
    plan->theme = "mortality_and_appointed_time";
    plan->commentary =
      "Thou hast bound an enduring reference unto a mortal value whose days are spent before the reference perisheth.";
    plan->curated_ref = "Job 14:2";
    return;
  }

  /* 5. Type mismatches (E0308, E0605, E0271, E0053) */
  if (HcStrEqI(code, "E0308") || HcStrEqI(code, "E0605") ||
      HcStrEqI(code, "E0271") || HcStrEqI(code, "E0053") ||
      HcContainsI(msg, "mismatched types") ||
      HcContainsI(msg, "non-primitive cast") ||
      (HcContainsI(msg, "expected ") && HcContainsI(msg, "found "))) {
    plan->category = SIN_TYPE_MISMATCH;
    plan->book_header = "THE BOOK OF KINDS";
    plan->sin_title = "FALSE IDENTITY AND CONFUSION OF KIND";
    plan->theme = "identity_truth_and_falsehood";
    plan->commentary =
      "Thou hast presented a value of one kind where the covenant demanded another, mingling diverse natures.";
    plan->curated_ref = "Leviticus 19:19";
    return;
  }

  /* 6. Missing traits (E0277, E0599, E0038, E0046, E0369) */
  if (HcStrEqI(code, "E0277") || HcStrEqI(code, "E0599") ||
      HcStrEqI(code, "E0038") || HcStrEqI(code, "E0046") || HcStrEqI(code, "E0369") ||
      HcContainsI(msg, "the trait bound") ||
      HcContainsI(msg, "is not satisfied") ||
      HcContainsI(msg, "doesn't implement") ||
      HcContainsI(msg, "no method named")) {
    plan->category = SIN_MISSING_TRAIT;
    plan->book_header = "THE BOOK OF WORTHINESS";
    plan->sin_title = "UNWORTHINESS OF THE VESSEL";
    plan->theme = "faith_virtue_and_worthiness";
    plan->commentary =
      "Thy type hath been weighed in the balances of the trait covenant and found wanting.";
    plan->curated_ref = "Daniel 5:27";
    return;
  }

  /* 7. Gluttony / Excess or wrong number of arguments (E0061) */
  if (HcStrEqI(code, "E0061") ||
      HcContainsI(msg, "arguments were supplied") ||
      HcContainsI(msg, "argument was supplied") ||
      HcContainsI(msg, "too many arguments")) {
    plan->category = SIN_EXCESS;
    plan->book_header = "THE BOOK OF TEMPERANCE";
    plan->sin_title = "GLUTTONY AND EXCESS OF ARGUMENTS";
    plan->theme = "intemperance_and_excess";
    plan->commentary =
      "Thou hast demanded and supplied more than was appointed unto the covenant of this function.";
    plan->curated_ref = "Proverbs 25:16";
    return;
  }

  /* 8. Undefined variables / unresolved names (E0425, E0412, E0432, E0433, E0063) */
  if (HcStrEqI(code, "E0425") || HcStrEqI(code, "E0412") ||
      HcStrEqI(code, "E0432") || HcStrEqI(code, "E0433") ||
      HcStrEqI(code, "E0063") ||
      HcContainsI(msg, "cannot find value") ||
      HcContainsI(msg, "cannot find type") ||
      HcContainsI(msg, "cannot find function") ||
      HcContainsI(msg, "unresolved import") ||
      HcContainsI(msg, "not found in this scope")) {
    plan->category = SIN_UNDEFINED;
    plan->book_header = "THE BOOK OF THE LOST";
    plan->sin_title = "INVOKING THE UNKNOWN";
    plan->theme = "the_lost_and_the_unknown";
    plan->commentary =
      "Thou hast called upon a name that is not written within the Book of Scope.";
    plan->curated_ref = "Acts 17:23";
    return;
  }

  /* 8. Unused variables / dead code */
  if (HcStrEqI(code, "unused_variables") || HcStrEqI(code, "unused_mut") ||
      HcStrEqI(code, "dead_code") || HcStrEqI(code, "unused_imports") ||
      HcStrEqI(code, "unused_assignments") || HcStrEqI(code, "unused_must_use") ||
      HcContainsI(msg, "unused variable") ||
      HcContainsI(msg, "does not need to be mutable") ||
      HcContainsI(msg, "is never read") ||
      HcContainsI(msg, "is never used") ||
      HcContainsI(msg, "is never constructed") ||
      HcContainsI(msg, "unused import") ||
      HcContainsI(msg, "that must be used")) {
    plan->category = SIN_UNUSED;
    plan->book_header = "THE BOOK OF STEWARDSHIP";
    plan->sin_title = "THE BURIED TALENT AND IDLE SERVANT";
    plan->theme = "idleness_and_wasted_gifts";
    plan->commentary =
      "Thou hast declared a vessel and left it idle in the earth, bearing no fruit in thy work.";
    plan->curated_ref = "Matthew 25:25";
    return;
  }

  /* 9. Unsafe operations (E0133, unsafe_code) */
  if (HcStrEqI(code, "E0133") || HcStrEqI(code, "unsafe_code") ||
      HcContainsI(msg, "requires unsafe") ||
      HcContainsI(msg, "call to unsafe function") ||
      HcContainsI(msg, "dereference of raw pointer") ||
      HcContainsI(msg, "use of mutable static")) {
    plan->category = SIN_UNSAFE;
    plan->book_header = "THE BOOK OF TRANSGRESSIONS";
    plan->sin_title = "STEPPING BEYOND THE SANCTUARY HEDGE";
    plan->theme = "temptation_danger_and_transgression";
    plan->commentary =
      "Thou hast ventured beyond the hedge of safety to wield unguarded power without an `unsafe` covenant.";
    plan->curated_ref = "Proverbs 6:27";
    return;
  }

  /* 10. Uncategorized / Apocalyptic Fallback */
  plan->category = SIN_APOCALYPSE;
  plan->book_header = "THE BOOK OF REVELATION";
  plan->sin_title = "ABOMINATION OF DESOLATION IN CODE";
  plan->theme = "apocalyptic_judgment";
  plan->commentary =
    "Thy transgression passeth all earthly understanding; the seals of the Apocalypse are opened upon thy code.";
  plan->curated_ref = "Revelation 6:8";
}

I64 JudgmentRender(U8 *diagnostic, I64 diagnostic_len,
                   U8 *output, I64 output_capacity)
{
  if (!output || output_capacity <= 1) return -1;
  output[0] = 0;
  if (!g_bible_initialized) return -2;

  CDiagnosticInput in;
  JudgmentParseDiagnostic(diagnostic, diagnostic_len, &in);

  CJudgmentPlan plan;
  JudgmentClassify(&in, &plan);

  U8 verse_text[2048];
  U8 canonical_ref[128];
  verse_text[0] = 0;
  canonical_ref[0] = 0;

  if (plan.category == SIN_ABSOLVED) {
    ScriptureLookupReference(plan.curated_ref, verse_text, 2048,
                             canonical_ref, 128);
  } else {
    /* Combine code + primary message for the HolyC BM25 Fuzzy Search Engine */
    U8 combined_query[2048];
    snprintf(combined_query, 2048, "%s %s", in.code, in.message);

    I32 top_idx[BM25_TOP_K];
    F64 top_scores[BM25_TOP_K];
    I64 top_n = ScriptureRankBM25(combined_query, top_idx, top_scores, BM25_TOP_K);

    /* Ensure the curated anchor verse is also in the candidate pool if categorized */
    if (plan.category != SIN_APOCALYPSE && plan.curated_ref != NULL) {
      if (plan.curated_ref[0] != 0) {
        I32 cb = -1, cc = 0, cvs = 0, cve = 0;
        if (ScriptureParseReference(plan.curated_ref, &cb, &cc, &cvs, &cve)) {
          I64 c_idx = ScriptureFindVerseIdx(cb, cc, cvs);
          if (c_idx >= 0) {
            Bool already = FALSE;
            I64 ti = 0;
            while (ti < top_n) {
              if (top_idx[ti] == c_idx) {
                already = TRUE;
                break;
              }
              ti++;
            }
            if (!already) {
              F64 anchor_sc = 50.0;
              if (top_n > 0 && top_scores[0] * 0.85 > anchor_sc)
                anchor_sc = top_scores[0] * 0.85;
              if (top_n < BM25_TOP_K) {
                top_idx[top_n] = c_idx(I32);
                top_scores[top_n] = anchor_sc;
                top_n++;
              } else {
                top_idx[BM25_TOP_K - 1] = c_idx(I32);
                top_scores[BM25_TOP_K - 1] = anchor_sc;
              }
            }
          }
        }
      }
    }

    I64 chosen_idx = -1;
    Bool has_bm25_match = FALSE;
    if (top_n > 0) {
      if (top_scores[0] >= 5.0)
        has_bm25_match = TRUE;
    }

    if (has_bm25_match) {
      if (in.deterministic || g_rng_deterministic) {
        chosen_idx = top_idx[0];
      } else {
        chosen_idx = ScriptureSampleWeightedTopK(top_idx, top_scores, top_n);
      }
    } else {
      /* No meaningful BM25 match -> Roll from Book of Revelation (Apocalypse)! */
      plan.category = SIN_APOCALYPSE;
      plan.book_header = "THE BOOK OF REVELATION";
      plan.sin_title = "APOCALYPTIC INIQUITY OF CODE";
      plan.commentary =
        "No earthly statute could measure thy sin; a judgment hath been drawn from the Apocalypse.";
      if (in.deterministic || g_rng_deterministic) {
        I64 h = (ScriptureHashBytes(in.message, StrLen(in.message)) >> 1)(I64);
        if (h < 0) h = -h;
        CBook *rev = &g_books[65];
        if (rev->verse_count > 0 && rev->first_verse_idx >= 0) {
          chosen_idx = rev->first_verse_idx + (h % rev->verse_count);
        }
      } else {
        chosen_idx = ScriptureRandomRevelationVerse();
      }
    }

    if (chosen_idx >= 0 && chosen_idx < g_verse_count) {
      CVerse *cv = &g_verses[chosen_idx];
      ScriptureFormatCanonicalRef(cv->book_idx, cv->chapter, cv->verse, cv->verse,
                                  canonical_ref, 128);
      U8 *vptr = BibleVerseText(chosen_idx);
      I64 vlen = cv->text_len;
      if (vlen > 2040) vlen = 2040;
      MemCpy(verse_text, vptr, vlen);
      verse_text[vlen] = 0;
    } else {
      ScriptureLookupReference(plan.curated_ref, verse_text, 2048,
                               canonical_ref, 128);
    }
  }

  U8 *c_hdr   = "";
  U8 *c_gold  = "";
  U8 *c_red   = "";
  U8 *c_cyan  = "";
  U8 *c_green = "";
  U8 *c_dim   = "";
  U8 *c_reset = "";

  if (in.use_color) {
    c_hdr   = "\x1b[1;37;44m";
    c_gold  = "\x1b[1;33m";
    c_red   = "\x1b[1;31m";
    c_cyan  = "\x1b[1;36m";
    c_green = "\x1b[1;32m";
    c_dim   = "\x1b[2m";
    c_reset = "\x1b[0m";
  }

  if (plan.category == SIN_ABSOLVED) {
    I64 n = snprintf(
      output, output_capacity,
      "%s✝ THE HOLY COMPILER — THE LORD HAS SPOKEN ✝%s\n\n"
      "%s✝ VERDICT: ABSOLVED%s\n\n"
      "Thy code hath been examined,\n"
      "and no transgression was found.\n\n"
      "%sSCRIPTURE:%s\n"
      "\"%s\"\n\n"
      "                    %s (KJV)\n\n"
      "Go forth and compile.\n",
      c_hdr, c_reset,
      c_green, c_reset,
      c_cyan, c_reset,
      verse_text,
      canonical_ref
    );
    if (n < 0) return -3;
    if (n >= output_capacity) n = output_capacity - 1;
    output[n] = 0;
    return n;
  }

  U8 err_hdr_line[1200];
  if (in.code[0]) {
    snprintf(err_hdr_line, 1200, "%s%s[%s]%s: %s",
             c_red, in.level, in.code, c_reset, in.message);
  } else {
    snprintf(err_hdr_line, 1200, "%s%s%s: %s",
             c_red, in.level, c_reset, in.message);
  }

  U8 chap_label[96];
  if (in.code[0]) {
    snprintf(chap_label, 96, "Chapter %s", in.code);
  } else if (HcStrEqI(in.level, "warning")) {
    StrCpy(chap_label, "Epistle of Warning");
  } else {
    StrCpy(chap_label, "Chapter of Transgression");
  }

  U8 loc_block[384];
  if (in.location[0]) {
    snprintf(loc_block, 384, "%sTRANSGRESSION:%s\n%s\n\n",
             c_gold, c_reset, in.location);
  } else {
    loc_block[0] = 0;
  }

  U8 notes_block[1200];
  if (in.notes[0]) {
    snprintf(notes_block, 1200, "\n%sCOUNSEL:%s\n%s\n",
             c_dim, c_reset, in.notes);
  } else {
    notes_block[0] = 0;
  }

  U8 *verdict_color = c_red;
  U8 *verdict_line = "✝ VERDICT: GUILTY";
  U8 *closing_line = "Repent, and compile again.";
  if (HcStrEqI(in.level, "warning")) {
    verdict_color = c_gold;
    verdict_line = "✝ VERDICT: ADMONISHED (GUILTY OF SLOTH)";
    closing_line = "Purge thy sloth, amend thy ways, and compile again.";
  }

  I64 written = snprintf(
    output, output_capacity,
    "%s\n\n"
    "%s✝ THE LORD HAS SPOKEN — THE HOLY COMPILER ✝%s\n\n"
    "%s%s%s\n"
    "%s\n\n"
    "%sSIN: %s%s\n\n"
    "And the Judge spoke:\n\n"
    "\"%s\"\n\n"
    "%sSCRIPTURE:%s\n"
    "\"%s\"\n\n"
    "                    %s (KJV)\n\n"
    "%s"
    "%sRUSTC:%s\n"
    "%s%s\n"
    "%s%s%s\n\n"
    "%s\n",
    err_hdr_line,
    c_hdr, c_reset,
    c_gold, plan.book_header, c_reset,
    chap_label,
    c_red, plan.sin_title, c_reset,
    plan.commentary,
    c_cyan, c_reset,
    verse_text,
    canonical_ref,
    loc_block,
    c_gold, c_reset,
    in.message, notes_block,
    verdict_color, verdict_line, c_reset,
    closing_line
  );

  if (written < 0) return -3;
  if (written >= output_capacity) written = output_capacity - 1;
  output[written] = 0;
  return written;
}
