/* holyc/Bible.HC - TempleOS King James Bible Parser & Decompressor
 *
 * Parses the authentic TempleOS King James Bible (Misc/Bible.TXT or .TXT.Z)
 * into structured books, chapters, and verses while preserving exact KJV
 * wording.
 */

#define MAX_BOOKS 66
#define MAX_CHAPTERS_PER_BOOK 155
#define INITIAL_VERSE_CAP 32768
#define INITIAL_TEXT_CAP 4718592

#define CT_NONE  1
#define CT_7_BIT 2
#define CT_8_BIT 3

public class CVerse
{
  I32 book_idx;
  I32 chapter;
  I32 verse;
  I32 text_len;
  I64 text_off;
};

public class CBook
{
  I32 idx;
  U8 *name;
  U8 *title;
  I32 first_verse_idx;
  I32 verse_count;
  I32 max_chapter;
  I32 chapter_start[MAX_CHAPTERS_PER_BOOK];
};

I64 g_bible_initialized;
CVerse *g_verses;
I64 g_verse_count;
I64 g_verse_cap;

U8 *g_text_arena;
I64 g_text_len;
I64 g_text_cap;

CBook g_books[MAX_BOOKS];
I64 g_book_count;

U8 *g_canonical_books[MAX_BOOKS];
U8 *g_kjv_titles[MAX_BOOKS];

U0 BibleInitBookTables()
{
  g_canonical_books[0]  = "Genesis";
  g_canonical_books[1]  = "Exodus";
  g_canonical_books[2]  = "Leviticus";
  g_canonical_books[3]  = "Numbers";
  g_canonical_books[4]  = "Deuteronomy";
  g_canonical_books[5]  = "Joshua";
  g_canonical_books[6]  = "Judges";
  g_canonical_books[7]  = "Ruth";
  g_canonical_books[8]  = "1 Samuel";
  g_canonical_books[9]  = "2 Samuel";
  g_canonical_books[10] = "1 Kings";
  g_canonical_books[11] = "2 Kings";
  g_canonical_books[12] = "1 Chronicles";
  g_canonical_books[13] = "2 Chronicles";
  g_canonical_books[14] = "Ezra";
  g_canonical_books[15] = "Nehemiah";
  g_canonical_books[16] = "Esther";
  g_canonical_books[17] = "Job";
  g_canonical_books[18] = "Psalms";
  g_canonical_books[19] = "Proverbs";
  g_canonical_books[20] = "Ecclesiastes";
  g_canonical_books[21] = "Song of Solomon";
  g_canonical_books[22] = "Isaiah";
  g_canonical_books[23] = "Jeremiah";
  g_canonical_books[24] = "Lamentations";
  g_canonical_books[25] = "Ezekiel";
  g_canonical_books[26] = "Daniel";
  g_canonical_books[27] = "Hosea";
  g_canonical_books[28] = "Joel";
  g_canonical_books[29] = "Amos";
  g_canonical_books[30] = "Obadiah";
  g_canonical_books[31] = "Jonah";
  g_canonical_books[32] = "Micah";
  g_canonical_books[33] = "Nahum";
  g_canonical_books[34] = "Habakkuk";
  g_canonical_books[35] = "Zephaniah";
  g_canonical_books[36] = "Haggai";
  g_canonical_books[37] = "Zechariah";
  g_canonical_books[38] = "Malachi";
  g_canonical_books[39] = "Matthew";
  g_canonical_books[40] = "Mark";
  g_canonical_books[41] = "Luke";
  g_canonical_books[42] = "John";
  g_canonical_books[43] = "Acts";
  g_canonical_books[44] = "Romans";
  g_canonical_books[45] = "1 Corinthians";
  g_canonical_books[46] = "2 Corinthians";
  g_canonical_books[47] = "Galatians";
  g_canonical_books[48] = "Ephesians";
  g_canonical_books[49] = "Philippians";
  g_canonical_books[50] = "Colossians";
  g_canonical_books[51] = "1 Thessalonians";
  g_canonical_books[52] = "2 Thessalonians";
  g_canonical_books[53] = "1 Timothy";
  g_canonical_books[54] = "2 Timothy";
  g_canonical_books[55] = "Titus";
  g_canonical_books[56] = "Philemon";
  g_canonical_books[57] = "Hebrews";
  g_canonical_books[58] = "James";
  g_canonical_books[59] = "1 Peter";
  g_canonical_books[60] = "2 Peter";
  g_canonical_books[61] = "1 John";
  g_canonical_books[62] = "2 John";
  g_canonical_books[63] = "3 John";
  g_canonical_books[64] = "Jude";
  g_canonical_books[65] = "Revelation";

  g_kjv_titles[0]  = "The First Book of Moses:  Called Genesis";
  g_kjv_titles[1]  = "The Second Book of Moses:  Called Exodus";
  g_kjv_titles[2]  = "The Third Book of Moses:  Called Leviticus";
  g_kjv_titles[3]  = "The Fourth Book of Moses:  Called Numbers";
  g_kjv_titles[4]  = "The Fifth Book of Moses:  Called Deuteronomy";
  g_kjv_titles[5]  = "The Book of Joshua";
  g_kjv_titles[6]  = "The Book of Judges";
  g_kjv_titles[7]  = "The Book of Ruth";
  g_kjv_titles[8]  = "The First Book of the Kings";
  g_kjv_titles[9]  = "The Second Book of the Kings";
  g_kjv_titles[10] = "The Third Book of the Kings";
  g_kjv_titles[11] = "The Fourth Book of the Kings";
  g_kjv_titles[12] = "The First Book of the Chronicles";
  g_kjv_titles[13] = "The Second Book of the Chronicles";
  g_kjv_titles[14] = "Ezra";
  g_kjv_titles[15] = "The Book of Nehemiah";
  g_kjv_titles[16] = "The Book of Esther";
  g_kjv_titles[17] = "The Book of Job";
  g_kjv_titles[18] = "The Book of Psalms";
  g_kjv_titles[19] = "The Proverbs";
  g_kjv_titles[20] = "The Preacher";
  g_kjv_titles[21] = "The Song of Solomon";
  g_kjv_titles[22] = "The Book of the Prophet Isaiah";
  g_kjv_titles[23] = "The Book of the Prophet Jeremiah";
  g_kjv_titles[24] = "The Lamentations of Jeremiah";
  g_kjv_titles[25] = "The Book of the Prophet Ezekiel";
  g_kjv_titles[26] = "The Book of Daniel";
  g_kjv_titles[27] = "Hosea";
  g_kjv_titles[28] = "Joel";
  g_kjv_titles[29] = "Amos";
  g_kjv_titles[30] = "Obadiah";
  g_kjv_titles[31] = "Jonah";
  g_kjv_titles[32] = "Micah";
  g_kjv_titles[33] = "Nahum";
  g_kjv_titles[34] = "Habakkuk";
  g_kjv_titles[35] = "Zephaniah";
  g_kjv_titles[36] = "Haggai";
  g_kjv_titles[37] = "Zechariah";
  g_kjv_titles[38] = "Malachi";
  g_kjv_titles[39] = "The Gospel According to Saint Matthew";
  g_kjv_titles[40] = "The Gospel According to Saint Mark";
  g_kjv_titles[41] = "The Gospel According to Saint Luke";
  g_kjv_titles[42] = "The Gospel According to Saint John";
  g_kjv_titles[43] = "The Acts of the Apostles";
  g_kjv_titles[44] = "The Epistle of Paul the Apostle to the Romans";
  g_kjv_titles[45] = "The First Epistle of Paul the Apostle to the Corinthians";
  g_kjv_titles[46] = "The Second Epistle of Paul the Apostle to the Corinthians";
  g_kjv_titles[47] = "The Epistle of Paul the Apostle to the Galatians";
  g_kjv_titles[48] = "The Epistle of Paul the Apostle to the Ephesians";
  g_kjv_titles[49] = "The Epistle of Paul the Apostle to the Philippians";
  g_kjv_titles[50] = "The Epistle of Paul the Apostle to the Colossians";
  g_kjv_titles[51] = "The First Epistle of Paul the Apostle to the Thessalonians";
  g_kjv_titles[52] = "The Second Epistle of Paul the Apostle to the Thessalonians";
  g_kjv_titles[53] = "The First Epistle of Paul the Apostle to Timothy";
  g_kjv_titles[54] = "The Second Epistle of Paul the Apostle to Timothy";
  g_kjv_titles[55] = "The Epistle of Paul the Apostle to Titus";
  g_kjv_titles[56] = "The Epistle of Paul the Apostle to Philemon";
  g_kjv_titles[57] = "The Epistle of Paul the Apostle to the Hebrews";
  g_kjv_titles[58] = "The General Epistle of James";
  g_kjv_titles[59] = "The First Epistle General of Peter";
  g_kjv_titles[60] = "The Second General Epistle of Peter";
  g_kjv_titles[61] = "The First Epistle General of John";
  g_kjv_titles[62] = "The Second Epistle General of John";
  g_kjv_titles[63] = "The Third Epistle General of John";
  g_kjv_titles[64] = "The General Epistle of Jude";
  g_kjv_titles[65] = "The Revelation of Saint John the Devine";
}

Bool HcIsDigit(U8 ch)
{
  return (ch >= '0' && ch <= '9');
}

Bool HcIsAlpha(U8 ch)
{
  return ((ch >= 'a' && ch <= 'z') || (ch >= 'A' && ch <= 'Z'));
}

Bool HcIsAlnum(U8 ch)
{
  return (HcIsAlpha(ch) || HcIsDigit(ch));
}

Bool HcIsSpace(U8 ch)
{
  return (ch == ' ' || ch == '\t' || ch == '\r' || ch == '\n');
}

U8 HcToLower(U8 ch)
{
  if (ch >= 'A' && ch <= 'Z')
    return ch + 32;
  return ch;
}

Bool HcStrEqI(U8 *a, U8 *b)
{
  if (!a || !b) return FALSE;
  I64 i = 0;
  while (a[i] && b[i]) {
    if (HcToLower(a[i]) != HcToLower(b[i]))
      return FALSE;
    i++;
  }
  return (a[i] == 0 && b[i] == 0);
}

Bool HcStrStartsWithI(U8 *str, U8 *prefix)
{
  if (!str || !prefix) return FALSE;
  I64 i = 0;
  while (prefix[i]) {
    if (HcToLower(str[i]) != HcToLower(prefix[i]))
      return FALSE;
    i++;
  }
  return TRUE;
}

/* TempleOS CArcCompress (.Z) LZW decompressor in HolyC */
U8 *BibleExpandArcCompress(U8 *src, I64 src_size, I64 *out_size)
{
  if (!src || src_size < 17) return NULL;
  I64 compressed_size = *(src)(I64 *);
  I64 expanded_size = *(src + 8)(I64 *);
  U8 compression_type = src[16];

  if (expanded_size <= 0 || expanded_size > 67108864) return NULL;
  if (compressed_size > src_size) compressed_size = src_size;

  U8 *dst = MAlloc(expanded_size + 1);
  if (!dst) return NULL;

  if (compression_type == CT_NONE) {
    I64 copy_len = expanded_size;
    if (src_size - 17 < copy_len) copy_len = src_size - 17;
    if (copy_len > 0) MemCpy(dst, src + 17, copy_len);
    dst[copy_len] = 0;
    if (out_size) *out_size = copy_len;
    return dst;
  }

  if (compression_type != CT_7_BIT && compression_type != CT_8_BIT) {
    Free(dst);
    return NULL;
  }

  I64 min_bits = 7;
  if (compression_type == CT_8_BIT) min_bits = 8;
  I64 base_code = 1 << min_bits;
  I64 eof_code = base_code + 1;
  I64 first_free = base_code + 2;

  I32 *dict_prefix = MAlloc(65536 * sizeof(I32));
  U8 *dict_char = MAlloc(65536);
  U8 *stack = MAlloc(65536);
  if (!dict_prefix || !dict_char || !stack) {
    if (dict_prefix) Free(dict_prefix);
    if (dict_char) Free(dict_char);
    if (stack) Free(stack);
    Free(dst);
    return NULL;
  }

  I64 cur_bits = min_bits + 1;
  I64 next_free = first_free;
  I64 max_code = 1 << cur_bits;

  I64 bit_pos = 17 * 8;
  I64 max_bits_total = compressed_size * 8;
  I64 out_pos = 0;
  I64 old_code = -1;
  U8 fin_char = 0;

  while (bit_pos + cur_bits <= max_bits_total && out_pos < expanded_size) {
    I64 byte_idx = bit_pos >> 3;
    I64 bit_off = bit_pos & 7;
    U64 raw_word = 0;
    I64 b = 0;
    while (b < 4 && (byte_idx + b) < src_size) {
      raw_word |= (src[byte_idx + b](U64)) << (b * 8);
      b++;
    }
    I64 code = (raw_word >> bit_off) & ((1 << cur_bits) - 1);
    bit_pos += cur_bits;

    if (code == eof_code) break;
    if (code == base_code) {
      cur_bits++;
      if (cur_bits > 16) break;
      max_code = 1 << cur_bits;
      continue;
    }

    I64 in_code = code;
    I64 sp = 0;
    if (code >= next_free) {
      if (old_code < 0) break;
      stack[sp++] = fin_char;
      code = old_code;
    }

    while (code >= base_code && sp < 65535) {
      stack[sp++] = dict_char[code];
      code = dict_prefix[code];
    }
    fin_char = code & 0xFF;
    stack[sp++] = fin_char;

    while (sp > 0 && out_pos < expanded_size) {
      dst[out_pos++] = stack[--sp];
    }

    if (old_code >= 0 && next_free < 65536) {
      dict_prefix[next_free] = old_code;
      dict_char[next_free] = fin_char;
      next_free++;
    }
    old_code = in_code;
  }

  dst[out_pos] = 0;
  if (out_size) *out_size = out_pos;

  Free(dict_prefix);
  Free(dict_char);
  Free(stack);
  return dst;
}

I64 BibleResolveHeaderToBookIdx(U8 *hdr_line, I64 fallback_seq)
{
  if (hdr_line != NULL) {
    if (hdr_line[0] != 0) {
      I64 i = 0;
      while (i < MAX_BOOKS) {
        if (HcStrEqI(hdr_line, g_kjv_titles[i]) || HcStrEqI(hdr_line, g_canonical_books[i]))
          return i;
        i++;
      }
      if (HcStrEqI(hdr_line, "Psalm") || HcStrEqI(hdr_line, "The Psalms"))
        return 18;
      if (HcStrEqI(hdr_line, "Song of Songs") || HcStrEqI(hdr_line, "Canticles"))
        return 21;
      if (HcStrEqI(hdr_line, "The Revelation of Saint John the Divine") ||
          HcStrEqI(hdr_line, "Apocalypse"))
        return 65;
    }
  }
  if (fallback_seq >= 0 && fallback_seq < MAX_BOOKS)
    return fallback_seq;
  return -1;
}

Bool BibleMatchKnownBookTitle(U8 *line)
{
  if (!line) return FALSE;
  if (line[0] == 0) return FALSE;
  I64 i = 0;
  while (i < MAX_BOOKS) {
    if (HcStrEqI(line, g_kjv_titles[i]) || HcStrEqI(line, g_canonical_books[i]))
      return TRUE;
    i++;
  }
  if (HcStrEqI(line, "Otherwise Called:") ||
      HcStrEqI(line, "Commonly Called:") ||
      HcStrEqI(line, "The First Book of Samuel") ||
      HcStrEqI(line, "The Second Book of Samuel") ||
      HcStrEqI(line, "Ecclesiastes"))
    return TRUE;
  return FALSE;
}

/* Check if str[pos..] starts with <digits>:<digits> followed by space or EOS.
 * Writes parsed chapter, verse, and index immediately after the token. */
Bool BibleTryParseRefToken(U8 *str, I64 len, I64 pos,
                           I32 *out_chap, I32 *out_verse, I64 *out_next_pos)
{
  if (pos < 0 || pos >= len) return FALSE;
  if (pos > 0) {
    U8 prev = str[pos - 1];
    if (HcIsAlnum(prev) || prev == ':') return FALSE;
  }
  if (!HcIsDigit(str[pos])) return FALSE;

  I64 i = pos;
  I32 chap = 0;
  I64 chap_digits = 0;
  while (i < len && HcIsDigit(str[i])) {
    chap = chap * 10 + (str[i] - '0');
    chap_digits++;
    if (chap_digits > 3) return FALSE;
    i++;
  }
  if (chap <= 0 || i >= len || str[i] != ':') return FALSE;
  i++; /* skip ':' */

  if (i >= len || !HcIsDigit(str[i])) return FALSE;
  I32 vnum = 0;
  I64 v_digits = 0;
  while (i < len && HcIsDigit(str[i])) {
    vnum = vnum * 10 + (str[i] - '0');
    v_digits++;
    if (v_digits > 3) return FALSE;
    i++;
  }
  if (vnum <= 0) return FALSE;
  if (i < len) {
    U8 next = str[i];
    if (HcIsAlnum(next) || next == ':') return FALSE;
  }

  *out_chap = chap;
  *out_verse = vnum;
  *out_next_pos = i;
  return TRUE;
}

Bool BibleEnsureArenaSpace(I64 needed)
{
  if (g_text_len + needed + 2 <= g_text_cap) return TRUE;
  I64 new_cap = g_text_cap * 2;
  if (new_cap < g_text_len + needed + 65536)
    new_cap = g_text_len + needed + 65536;
  U8 *new_buf = ReAlloc(g_text_arena, new_cap);
  if (!new_buf) return FALSE;
  g_text_arena = new_buf;
  g_text_cap = new_cap;
  return TRUE;
}

Bool BibleEnsureVerseCap()
{
  if (g_verse_count + 1 <= g_verse_cap) return TRUE;
  I64 new_cap = g_verse_cap * 2;
  if (new_cap < 1024) new_cap = 1024;
  CVerse *new_arr = ReAlloc(g_verses, new_cap * sizeof(CVerse));
  if (!new_arr) return FALSE;
  g_verses = new_arr;
  g_verse_cap = new_cap;
  return TRUE;
}

/* Append normalized slice [s..s+slen) to the active verse in g_text_arena */
U0 BibleAppendSliceNormalized(U8 *s, I64 slen, I64 verse_text_start)
{
  if (!s || slen <= 0) return;
  if (!BibleEnsureArenaSpace(slen + 2)) return;

  I64 i = 0;
  while (i < slen && HcIsSpace(s[i])) i++;
  while (slen > i && HcIsSpace(s[slen - 1])) slen--;
  if (i >= slen) return;

  if (g_text_len > verse_text_start && g_text_arena[g_text_len - 1] != ' ') {
    g_text_arena[g_text_len++] = ' ';
  }

  Bool prev_space = FALSE;
  while (i < slen) {
    U8 ch = s[i++];
    if (HcIsSpace(ch)) {
      if (!prev_space) {
        g_text_arena[g_text_len++] = ' ';
        prev_space = TRUE;
      }
    } else {
      g_text_arena[g_text_len++] = ch;
      prev_space = FALSE;
    }
  }
}

U0 BibleCommitVerse(I32 book_idx, I32 chap, I32 vnum, I64 verse_text_start)
{
  if (book_idx < 0 || book_idx >= MAX_BOOKS || chap <= 0 || vnum <= 0)
    return;

  while (g_text_len > verse_text_start && g_text_arena[g_text_len - 1] == ' ')
    g_text_len--;

  I32 tlen = (g_text_len - verse_text_start)(I32);
  g_text_arena[g_text_len++] = 0;

  if (!BibleEnsureVerseCap()) return;
  I64 v_idx = g_verse_count++;
  g_verses[v_idx].book_idx = book_idx;
  g_verses[v_idx].chapter = chap;
  g_verses[v_idx].verse = vnum;
  g_verses[v_idx].text_len = tlen;
  g_verses[v_idx].text_off = verse_text_start;

  CBook *bk = &g_books[book_idx];
  if (bk->first_verse_idx < 0)
    bk->first_verse_idx = v_idx(I32);
  bk->verse_count++;
  if (chap > bk->max_chapter)
    bk->max_chapter = chap;
  if (chap < MAX_CHAPTERS_PER_BOOK && bk->chapter_start[chap] < 0)
    bk->chapter_start[chap] = v_idx(I32);
}

U0 BibleFreeAll()
{
  if (g_verses) {
    Free(g_verses);
    g_verses = NULL;
  }
  if (g_text_arena) {
    Free(g_text_arena);
    g_text_arena = NULL;
  }
  g_verse_count = 0;
  g_verse_cap = 0;
  g_text_len = 0;
  g_text_cap = 0;
  g_book_count = 0;
  g_bible_initialized = 0;
}

I64 BibleParseBuffer(U8 *buf, I64 buf_len)
{
  if (!buf || buf_len <= 0) return -1;

  BibleFreeAll();
  BibleInitBookTables();

  g_verses = MAlloc(INITIAL_VERSE_CAP * sizeof(CVerse));
  if (!g_verses) return -2;
  g_verse_cap = INITIAL_VERSE_CAP;

  g_text_arena = MAlloc(INITIAL_TEXT_CAP);
  if (!g_text_arena) {
    BibleFreeAll();
    return -2;
  }
  g_text_cap = INITIAL_TEXT_CAP;

  I64 b = 0;
  while (b < MAX_BOOKS) {
    g_books[b].idx = b(I32);
    g_books[b].name = g_canonical_books[b];
    g_books[b].title = g_kjv_titles[b];
    g_books[b].first_verse_idx = -1;
    g_books[b].verse_count = 0;
    g_books[b].max_chapter = 0;
    I64 c = 0;
    while (c < MAX_CHAPTERS_PER_BOOK) {
      g_books[b].chapter_start[c] = -1;
      c++;
    }
    b++;
  }

  Bool in_book = FALSE;
  I64 consecutive_blanks = 0;
  U8 last_hdr[256];
  last_hdr[0] = 0;

  I32 cur_book = -1;
  I32 cur_chap = 0;
  I32 cur_verse = 0;
  I64 cur_verse_text_start = 0;
  I64 seq_books_seen = 0;

  I64 pos = 0;
  while (pos < buf_len) {
    I64 line_start = pos;
    while (pos < buf_len && buf[pos] != '\n')
      pos++;
    I64 line_end = pos;
    if (pos < buf_len && buf[pos] == '\n')
      pos++;

    while (line_start < line_end && HcIsSpace(buf[line_start]))
      line_start++;
    while (line_end > line_start && HcIsSpace(buf[line_end - 1]))
      line_end--;
    I64 line_len = line_end - line_start;
    U8 *line_ptr = buf + line_start;

    if (!in_book) {
      if (line_len == 0) continue;
      I32 t_chap = 0, t_verse = 0;
      I64 t_next = 0;
      if (BibleTryParseRefToken(line_ptr, line_len, 0, &t_chap, &t_verse, &t_next) &&
          t_chap == 1 && t_verse == 1) {
        cur_book = BibleResolveHeaderToBookIdx(last_hdr, seq_books_seen)(I32);
        if (cur_book < 0) cur_book = 0;
        seq_books_seen++;
        in_book = TRUE;
        consecutive_blanks = 0;
        cur_chap = 0;
        cur_verse = 0;
        cur_verse_text_start = g_text_len;
      } else {
        I64 copy_len = line_len;
        if (copy_len > 255) copy_len = 255;
        MemCpy(last_hdr, line_ptr, copy_len);
        last_hdr[copy_len] = 0;
        continue;
      }
    } else {
      if (line_len == 0) {
        consecutive_blanks++;
        continue;
      }

      I32 l_chap = 0, l_verse = 0;
      I64 l_next = 0;
      Bool starts_with_ref = BibleTryParseRefToken(line_ptr, line_len, 0,
                                                   &l_chap, &l_verse, &l_next);

      Bool is_divider = FALSE;
      if (line_len >= 3 && line_ptr[0] == '*' && line_ptr[1] == '*' && line_ptr[2] == '*')
        is_divider = TRUE;
      else if (line_len >= 28 && HcStrStartsWithI(line_ptr, "End of the Project Gutenberg"))
        is_divider = TRUE;
      else if (line_len >= 20 && HcStrStartsWithI(line_ptr, "The New Testament of"))
        is_divider = TRUE;
      else if (consecutive_blanks >= 2 && !starts_with_ref)
        is_divider = TRUE;
      else if (consecutive_blanks >= 1 && !starts_with_ref) {
        U8 tmp_line[256];
        I64 clen = line_len;
        if (clen > 255) clen = 255;
        MemCpy(tmp_line, line_ptr, clen);
        tmp_line[clen] = 0;
        if (BibleMatchKnownBookTitle(tmp_line))
          is_divider = TRUE;
      }

      if (is_divider) {
        if (cur_chap > 0 && cur_verse > 0) {
          BibleCommitVerse(cur_book, cur_chap, cur_verse, cur_verse_text_start);
          cur_chap = 0;
          cur_verse = 0;
          cur_verse_text_start = g_text_len;
        }
        in_book = FALSE;
        consecutive_blanks = 0;
        I64 copy_len = line_len;
        if (copy_len > 255) copy_len = 255;
        MemCpy(last_hdr, line_ptr, copy_len);
        last_hdr[copy_len] = 0;
        continue;
      }

      consecutive_blanks = 0;
    }

    /* Scan line_ptr[0..line_len) for <chap>:<verse> markers */
    I64 scan = 0;
    I64 seg_start = 0;
    while (scan < line_len) {
      I32 m_chap = 0, m_verse = 0;
      I64 m_next = 0;
      if (BibleTryParseRefToken(line_ptr, line_len, scan, &m_chap, &m_verse, &m_next)) {
        if (scan > seg_start && cur_chap > 0 && cur_verse > 0) {
          BibleAppendSliceNormalized(line_ptr + seg_start, scan - seg_start,
                                     cur_verse_text_start);
        }
        if (cur_chap > 0 && cur_verse > 0) {
          BibleCommitVerse(cur_book, cur_chap, cur_verse, cur_verse_text_start);
        }
        if (m_chap == 1 && m_verse == 1 && g_books[cur_book].verse_count > 0) {
          /* Safety: if a book started without a blank-line separator */
          if (cur_book + 1 < MAX_BOOKS) {
            cur_book++;
            seq_books_seen++;
          }
        }
        cur_chap = m_chap;
        cur_verse = m_verse;
        cur_verse_text_start = g_text_len;
        scan = m_next;
        seg_start = scan;
      } else {
        scan++;
      }
    }

    if (line_len > seg_start && cur_chap > 0 && cur_verse > 0) {
      BibleAppendSliceNormalized(line_ptr + seg_start, line_len - seg_start,
                                 cur_verse_text_start);
    }
  }

  if (cur_chap > 0 && cur_verse > 0) {
    BibleCommitVerse(cur_book, cur_chap, cur_verse, cur_verse_text_start);
  }

  g_book_count = 0;
  b = 0;
  while (b < MAX_BOOKS) {
    if (g_books[b].verse_count > 0)
      g_book_count++;
    b++;
  }

  if (g_verse_count <= 0) {
    BibleFreeAll();
    return -3;
  }

  g_bible_initialized = 1;
  return 0;
}

I64 BibleLoadFile(U8 *bible_path)
{
  if (!bible_path) return -1;
  if (bible_path[0] == 0) return -1;
  I64 raw_size = 0;
  U8 *raw_buf = FileRead(bible_path, &raw_size);
  if (!raw_buf || raw_size <= 0) {
    if (raw_buf) Free(raw_buf);
    return -1;
  }

  Bool is_compressed = IsDotZ(bible_path);
  if (!is_compressed && raw_size > 17) {
    I64 hdr_comp_sz = *(raw_buf)(I64 *);
    I64 hdr_exp_sz = *(raw_buf + 8)(I64 *);
    U8 ctype = raw_buf[16];
    if (hdr_comp_sz == raw_size && hdr_exp_sz > raw_size &&
        hdr_exp_sz < 67108864 && (ctype >= CT_NONE && ctype <= CT_8_BIT)) {
      is_compressed = TRUE;
    }
  }

  if (is_compressed) {
    I64 exp_size = 0;
    U8 *exp_buf = BibleExpandArcCompress(raw_buf, raw_size, &exp_size);
    Free(raw_buf);
    if (!exp_buf || exp_size <= 0) {
      if (exp_buf) Free(exp_buf);
      return -2;
    }
    I64 rc = BibleParseBuffer(exp_buf, exp_size);
    Free(exp_buf);
    return rc;
  }

  I64 rc = BibleParseBuffer(raw_buf, raw_size);
  Free(raw_buf);
  return rc;
}

U8 *BibleVerseText(I64 verse_idx)
{
  if (!g_bible_initialized || verse_idx < 0 || verse_idx >= g_verse_count)
    return "";
  return g_text_arena + g_verses[verse_idx].text_off;
}
