/* holyc/Scripture.HC - HolyC Biblical Fuzzy Search Engine (BM25 + Synonym Map)
 *
 * Implements:
 *   1. Full inverted index over all 31,102 KJV verses built in HolyC.
 *   2. Diagnostic tokenization & Rust->KJV biblical vocabulary expansion.
 *   3. BM25 verse ranking with IDF, TF saturation, and document length norm.
 *   4. Weighted random sampling among the Top 5-10 best-matching verses.
 *   5. Book of Revelation (Apocalypse) fallback when no match is found.
 */

#define VOCAB_BUCKETS 32768
#define VOCAB_MASK    32767
#define INITIAL_VOCAB_ARENA 262144
#define MAX_QUERY_TERMS 64
#define BM25_TOP_K 8

public class CVocabEntry
{
  I64 word_off;
  I32 word_len;
  I32 df;
  I32 post_start;
  I32 post_count;
  I32 last_verse;
};

public class CPosting
{
  I32 verse_idx;
  I16 tf;
  I16 pad;
};

public class CSynPair
{
  U8 *rust_term;
  U8 *kjv_term;
  F64 weight;
};

public class CQueryTerm
{
  I32 vocab_bucket;
  F64 weight;
};

CVocabEntry *g_vocab_table;
I32 *g_vocab_used;
I64 g_vocab_count;

U8 *g_vocab_arena;
I64 g_vocab_arena_len;
I64 g_vocab_arena_cap;

CPosting *g_postings;
I64 g_total_postings;

I16 *g_doc_len;
F64 g_avg_doc_len;
F64 *g_bm25_scores;

U64 g_rng_state;
I64 g_rng_deterministic;

#define MAX_SYN_PAIRS 512
CSynPair g_syn_table[MAX_SYN_PAIRS];
I64 g_syn_count;

U0 ScriptureAddSyn(U8 *rust_term, U8 *kjv_term, F64 weight)
{
  if (g_syn_count >= MAX_SYN_PAIRS) return;
  g_syn_table[g_syn_count].rust_term = rust_term;
  g_syn_table[g_syn_count].kjv_term = kjv_term;
  g_syn_table[g_syn_count].weight = weight;
  g_syn_count++;
}

U0 ScriptureInitSynTable()
{
  g_syn_count = 0;

  /* Borrow / lending / debt */
  ScriptureAddSyn("borrow",     "borrower",     5.0);
  ScriptureAddSyn("borrow",     "borroweth",    4.5);
  ScriptureAddSyn("borrow",     "borrowed",     4.5);
  ScriptureAddSyn("borrow",     "borrow",       4.0);
  ScriptureAddSyn("borrow",     "lender",       4.5);
  ScriptureAddSyn("borrow",     "lend",         3.5);
  ScriptureAddSyn("borrow",     "debt",         3.5);
  ScriptureAddSyn("borrow",     "owe",          3.0);
  ScriptureAddSyn("borrow",     "pledge",       3.5);
  ScriptureAddSyn("borrowed",   "borrowed",     4.5);
  ScriptureAddSyn("borrowed",   "borrower",     4.5);
  ScriptureAddSyn("borrowed",   "borroweth",    4.5);
  ScriptureAddSyn("borrowed",   "lender",       4.0);
  ScriptureAddSyn("borrowed",   "pledge",       3.5);
  ScriptureAddSyn("borrows",    "borroweth",    4.5);
  ScriptureAddSyn("borrows",    "borrower",     4.5);
  ScriptureAddSyn("borrows",    "pledge",       3.5);

  /* Mutable / aliasing / two masters */
  ScriptureAddSyn("mutable",    "masters",      4.5);
  ScriptureAddSyn("mutable",    "mammon",       4.5);
  ScriptureAddSyn("mutable",    "double",       3.8);
  ScriptureAddSyn("mutable",    "unstable",     4.2);
  ScriptureAddSyn("mutable",    "change",       3.0);
  ScriptureAddSyn("mutable",    "changeth",     3.5);
  ScriptureAddSyn("mutable",    "divided",      3.0);
  ScriptureAddSyn("mutably",    "masters",      4.5);
  ScriptureAddSyn("mutably",    "double",       3.8);
  ScriptureAddSyn("mutably",    "unstable",     4.0);
  ScriptureAddSyn("once",       "masters",      4.0);
  ScriptureAddSyn("once",       "mammon",       3.8);
  ScriptureAddSyn("once",       "two",          2.2);
  ScriptureAddSyn("twice",      "twice",        3.8);
  ScriptureAddSyn("twice",      "masters",      4.0);
  ScriptureAddSyn("twice",      "double",       3.5);

  /* Move / ownership / theft / covetousness */
  ScriptureAddSyn("move",       "taken",        3.2);
  ScriptureAddSyn("move",       "away",         2.5);
  ScriptureAddSyn("move",       "departed",     4.0);
  ScriptureAddSyn("move",       "removed",      4.0);
  ScriptureAddSyn("move",       "steal",        3.8);
  ScriptureAddSyn("move",       "covet",        4.2);
  ScriptureAddSyn("move",       "naked",        3.8);
  ScriptureAddSyn("moved",      "departed",     4.2);
  ScriptureAddSyn("moved",      "removed",      4.2);
  ScriptureAddSyn("moved",      "taken",        3.5);
  ScriptureAddSyn("moved",      "away",         2.8);
  ScriptureAddSyn("moved",      "naked",        3.8);
  ScriptureAddSyn("moved",      "covet",        4.0);
  ScriptureAddSyn("moved",      "gone",         3.0);
  ScriptureAddSyn("ownership",  "possession",   4.0);
  ScriptureAddSyn("ownership",  "inheritance",  3.8);
  ScriptureAddSyn("ownership",  "covet",        4.0);

  /* Lifetime / mortality / eternity / dropped */
  ScriptureAddSyn("lifetime",   "life",         3.5);
  ScriptureAddSyn("lifetime",   "days",         3.0);
  ScriptureAddSyn("lifetime",   "death",        3.5);
  ScriptureAddSyn("lifetime",   "eternal",      4.0);
  ScriptureAddSyn("lifetime",   "everlasting",  3.8);
  ScriptureAddSyn("lifetime",   "vapour",       4.5);
  ScriptureAddSyn("lifetime",   "shadow",       3.8);
  ScriptureAddSyn("lifetime",   "continueth",   4.2);
  ScriptureAddSyn("lifetime",   "season",       3.8);
  ScriptureAddSyn("live",       "life",         3.0);
  ScriptureAddSyn("live",       "days",         2.8);
  ScriptureAddSyn("live",       "liveth",       3.5);
  ScriptureAddSyn("live",       "vapour",       4.5);
  ScriptureAddSyn("live",       "shadow",       3.8);
  ScriptureAddSyn("live",       "continueth",   4.2);
  ScriptureAddSyn("live",       "flower",       3.8);
  ScriptureAddSyn("dropped",    "vapour",       4.5);
  ScriptureAddSyn("dropped",    "vanisheth",    4.5);
  ScriptureAddSyn("dropped",    "flower",       3.8);
  ScriptureAddSyn("dropped",    "withereth",    4.2);
  ScriptureAddSyn("dropped",    "fadeth",       4.2);
  ScriptureAddSyn("dropped",    "grass",        3.2);
  ScriptureAddSyn("temporary",  "vapour",       4.5);
  ScriptureAddSyn("temporary",  "vanisheth",    4.5);
  ScriptureAddSyn("temporary",  "shadow",       3.8);
  ScriptureAddSyn("temporary",  "moment",       3.8);

  /* Type mismatch / diverse kinds / false weights */
  ScriptureAddSyn("types",      "kind",         4.0);
  ScriptureAddSyn("types",      "diverse",      4.5);
  ScriptureAddSyn("types",      "mingled",      4.5);
  ScriptureAddSyn("types",      "yoked",        4.5);
  ScriptureAddSyn("types",      "unequally",    4.5);
  ScriptureAddSyn("type",       "kind",         3.8);
  ScriptureAddSyn("type",       "diverse",      4.2);
  ScriptureAddSyn("type",       "mingled",      4.2);
  ScriptureAddSyn("type",       "likeness",     3.8);
  ScriptureAddSyn("mismatched", "diverse",      4.5);
  ScriptureAddSyn("mismatched", "mingled",      4.5);
  ScriptureAddSyn("mismatched", "yoked",        4.5);
  ScriptureAddSyn("mismatched", "unequally",    4.5);
  ScriptureAddSyn("mismatched", "kind",         4.0);
  ScriptureAddSyn("cast",       "darkness",     3.2);
  ScriptureAddSyn("cast",       "light",        3.0);
  ScriptureAddSyn("cast",       "bitter",       3.8);
  ScriptureAddSyn("cast",       "sweet",        3.8);

  /* Missing traits / unworthiness / weighed in balances */
  ScriptureAddSyn("trait",      "weighed",      4.5);
  ScriptureAddSyn("trait",      "balances",     4.5);
  ScriptureAddSyn("trait",      "wanting",      4.5);
  ScriptureAddSyn("trait",      "worthy",       4.0);
  ScriptureAddSyn("trait",      "unworthy",     4.2);
  ScriptureAddSyn("trait",      "lackest",      4.2);
  ScriptureAddSyn("satisfied",  "weighed",      4.2);
  ScriptureAddSyn("satisfied",  "balances",     4.2);
  ScriptureAddSyn("satisfied",  "wanting",      4.2);
  ScriptureAddSyn("satisfied",  "satisfied",    3.5);
  ScriptureAddSyn("implement",  "worthy",       3.8);
  ScriptureAddSyn("implement",  "statutes",     3.5);
  ScriptureAddSyn("method",     "worthy",       3.8);
  ScriptureAddSyn("method",     "way",          2.5);
  ScriptureAddSyn("method",     "custom",       3.5);

  /* Unused variables / dead code / sloth / buried talent */
  ScriptureAddSyn("unused",     "slothful",     4.5);
  ScriptureAddSyn("unused",     "idle",         4.5);
  ScriptureAddSyn("unused",     "idleness",     4.5);
  ScriptureAddSyn("unused",     "talent",       4.5);
  ScriptureAddSyn("unused",     "hid",          3.5);
  ScriptureAddSyn("unused",     "unprofitable", 4.5);
  ScriptureAddSyn("unused",     "cumbereth",    4.5);
  ScriptureAddSyn("dead",       "dead",         3.5);
  ScriptureAddSyn("dead",       "vain",         3.8);
  ScriptureAddSyn("dead",       "unprofitable", 4.2);
  ScriptureAddSyn("dead",       "withered",     3.8);
  ScriptureAddSyn("never",      "idle",         4.0);
  ScriptureAddSyn("never",      "slothful",     4.0);
  ScriptureAddSyn("never",      "unprofitable", 4.0);

  /* Unsafe operations / fire / serpent / breaking hedge */
  ScriptureAddSyn("unsafe",     "fire",         3.5);
  ScriptureAddSyn("unsafe",     "bosom",        4.5);
  ScriptureAddSyn("unsafe",     "burned",       4.0);
  ScriptureAddSyn("unsafe",     "coals",        4.0);
  ScriptureAddSyn("unsafe",     "hedge",        4.5);
  ScriptureAddSyn("unsafe",     "serpent",      4.0);
  ScriptureAddSyn("unsafe",     "pit",          3.5);
  ScriptureAddSyn("unsafe",     "bite",         4.0);
  ScriptureAddSyn("pointer",    "serpent",      3.8);
  ScriptureAddSyn("pointer",    "hedge",        4.0);
  ScriptureAddSyn("pointer",    "thorn",        3.8);
  ScriptureAddSyn("raw",        "fire",         3.5);
  ScriptureAddSyn("raw",        "coals",        4.0);
  ScriptureAddSyn("dereference","bosom",        4.2);
  ScriptureAddSyn("dereference","serpent",      4.0);

  /* Undefined / unresolved / lost / unknown */
  ScriptureAddSyn("find",       "unknown",      4.2);
  ScriptureAddSyn("find",       "ignorantly",   4.5);
  ScriptureAddSyn("find",       "seek",         3.5);
  ScriptureAddSyn("find",       "lost",         4.0);
  ScriptureAddSyn("find",       "astray",       4.0);
  ScriptureAddSyn("unresolved", "unknown",      4.2);
  ScriptureAddSyn("unresolved", "ignorantly",   4.5);
  ScriptureAddSyn("unresolved", "stranger",     3.8);
  ScriptureAddSyn("undeclared", "unknown",      4.2);
  ScriptureAddSyn("undeclared", "unwritten",    4.0);
  ScriptureAddSyn("scope",      "place",        2.8);
  ScriptureAddSyn("scope",      "habitation",   3.8);
  ScriptureAddSyn("scope",      "borders",      3.5);

  /* Immutability / uninitialized / visibility / overflow / division / threads */
  ScriptureAddSyn("immutable",  "change",       3.8);
  ScriptureAddSyn("immutable",  "consumed",     3.5);
  ScriptureAddSyn("immutable",  "alter",        4.0);
  ScriptureAddSyn("immutable",  "medes",        4.2);
  ScriptureAddSyn("immutable",  "persians",     4.2);
  ScriptureAddSyn("uninitialized","void",       4.2);
  ScriptureAddSyn("uninitialized","form",       3.5);
  ScriptureAddSyn("uninitialized","empty",      3.8);
  ScriptureAddSyn("Private",    "secret",       4.0);
  ScriptureAddSyn("Private",    "hidden",       4.0);
  ScriptureAddSyn("Private",    "veil",         3.8);
  ScriptureAddSyn("overflow",   "measure",      4.0);
  ScriptureAddSyn("overflow",   "abundance",    4.0);
  ScriptureAddSyn("overflow",   "runneth",      4.5);
  ScriptureAddSyn("overflow",   "bounds",       4.0);
  ScriptureAddSyn("divide",     "divided",      4.0);
  ScriptureAddSyn("divide",     "nought",       4.0);
  ScriptureAddSyn("zero",       "nought",       4.2);
  ScriptureAddSyn("zero",       "nothing",      3.5);
  ScriptureAddSyn("thread",     "together",     3.5);
  ScriptureAddSyn("thread",     "cord",         4.2);
  ScriptureAddSyn("thread",     "threefold",    4.5);
  ScriptureAddSyn("sync",       "unity",        4.2);
  ScriptureAddSyn("sync",       "together",     3.5);
  ScriptureAddSyn("mutex",      "bound",        3.8);
  ScriptureAddSyn("mutex",      "fetters",      4.2);
  ScriptureAddSyn("async",      "wait",         3.8);
  ScriptureAddSyn("async",      "waiteth",      4.2);
  ScriptureAddSyn("await",      "wait",         3.8);
  ScriptureAddSyn("await",      "tarry",        4.2);
  ScriptureAddSyn("await",      "patience",     4.0);
  ScriptureAddSyn("recursive",  "whirleth",     4.5);
  ScriptureAddSyn("recursive",  "circuits",     4.5);
  ScriptureAddSyn("recursion",  "whirleth",     4.5);
  ScriptureAddSyn("recursion",  "circuits",     4.5);
  ScriptureAddSyn("syntax",     "babel",        4.5);
  ScriptureAddSyn("syntax",     "confound",     4.5);
  ScriptureAddSyn("syntax",     "language",     4.0);
  ScriptureAddSyn("token",      "speech",       3.8);
  ScriptureAddSyn("token",      "stammering",   4.5);
  ScriptureAddSyn("panic",      "destruction",  4.0);
  ScriptureAddSyn("panic",      "suddenly",     3.8);
  ScriptureAddSyn("panic",      "calamity",     4.2);

  /* Error code direct anchors so bare codes also expand to biblical concepts */
  ScriptureAddSyn("e0499",      "borrower",     4.8);
  ScriptureAddSyn("e0499",      "lender",       4.5);
  ScriptureAddSyn("e0499",      "masters",      4.8);
  ScriptureAddSyn("e0499",      "mammon",       4.5);
  ScriptureAddSyn("e0499",      "double",       4.0);
  ScriptureAddSyn("e0499",      "unstable",     4.2);
  ScriptureAddSyn("e0382",      "departed",     4.2);
  ScriptureAddSyn("e0382",      "removed",      4.2);
  ScriptureAddSyn("e0382",      "taken",        3.8);
  ScriptureAddSyn("e0382",      "naked",        4.0);
  ScriptureAddSyn("e0382",      "covet",        4.2);
  ScriptureAddSyn("e0502",      "borrowed",     4.5);
  ScriptureAddSyn("e0502",      "borrower",     4.5);
  ScriptureAddSyn("e0502",      "pledge",       4.2);
  ScriptureAddSyn("e0502",      "covet",        4.5);
  ScriptureAddSyn("e0502",      "neighbour",    4.0);
  ScriptureAddSyn("e0507",      "covet",        4.5);
  ScriptureAddSyn("e0507",      "neighbour",    4.0);
  ScriptureAddSyn("e0507",      "pledge",       4.0);
  ScriptureAddSyn("e0597",      "vapour",       4.5);
  ScriptureAddSyn("e0597",      "vanisheth",    4.5);
  ScriptureAddSyn("e0597",      "shadow",       4.0);
  ScriptureAddSyn("e0597",      "continueth",   4.2);
  ScriptureAddSyn("e0597",      "flower",       4.0);
  ScriptureAddSyn("e0106",      "season",       4.5);
  ScriptureAddSyn("e0106",      "purpose",      4.0);
  ScriptureAddSyn("e0106",      "days",         3.5);
  ScriptureAddSyn("e0308",      "diverse",      4.5);
  ScriptureAddSyn("e0308",      "mingled",      4.5);
  ScriptureAddSyn("e0308",      "kind",         4.0);
  ScriptureAddSyn("e0308",      "yoked",        4.5);
  ScriptureAddSyn("e0308",      "unequally",    4.5);
  ScriptureAddSyn("e0277",      "weighed",      4.8);
  ScriptureAddSyn("e0277",      "balances",     4.8);
  ScriptureAddSyn("e0277",      "wanting",      4.8);
  ScriptureAddSyn("e0277",      "worthy",       4.2);
  ScriptureAddSyn("e0277",      "pride",        4.4);
  ScriptureAddSyn("e0277",      "haughty",      4.5);
  ScriptureAddSyn("e0599",      "worthy",       4.5);
  ScriptureAddSyn("e0599",      "weep",         3.8);
  ScriptureAddSyn("e0425",      "unknown",      4.5);
  ScriptureAddSyn("e0425",      "ignorantly",   4.8);
  ScriptureAddSyn("e0425",      "lost",         4.2);
  ScriptureAddSyn("e0425",      "seek",         3.8);
  ScriptureAddSyn("e0133",      "fire",         3.8);
  ScriptureAddSyn("e0133",      "bosom",        4.8);
  ScriptureAddSyn("e0133",      "burned",       4.2);
  ScriptureAddSyn("e0133",      "hedge",        4.8);
  ScriptureAddSyn("e0133",      "serpent",      4.5);
  ScriptureAddSyn("e0384",      "change",       4.2);
  ScriptureAddSyn("e0384",      "consumed",     4.0);
  ScriptureAddSyn("e0384",      "alter",        4.2);
  ScriptureAddSyn("e0061",      "glutton",      4.8);
  ScriptureAddSyn("e0061",      "drunkard",     4.2);
  ScriptureAddSyn("e0061",      "appetite",     4.5);
  ScriptureAddSyn("e0061",      "sufficient",   4.2);
  ScriptureAddSyn("e0061",      "honey",        3.8);
  ScriptureAddSyn("e0061",      "vomit",        4.2);
  ScriptureAddSyn("e0061",      "reprove",      4.0);
  ScriptureAddSyn("arguments",  "glutton",      4.2);
  ScriptureAddSyn("arguments",  "sufficient",   4.0);
  ScriptureAddSyn("arguments",  "appetite",     4.2);
  ScriptureAddSyn("supplied",   "sufficient",   4.0);
  ScriptureAddSyn("supplied",   "vomit",        3.8);
  ScriptureAddSyn("e0381",      "tree",         3.8);
  ScriptureAddSyn("e0381",      "knowledge",    4.4);
  ScriptureAddSyn("e0381",      "gods",         4.4);
  ScriptureAddSyn("e0381",      "void",         4.2);
  ScriptureAddSyn("e0381",      "empty",        3.8);
  ScriptureAddSyn("e0381",      "naked",        4.0);
  ScriptureAddSyn("initialized","void",         4.2);
  ScriptureAddSyn("initialized","empty",        3.8);
  ScriptureAddSyn("initialized","knowledge",    4.0);
}

U0 ScriptureSeedRng(U64 seed)
{
  if (seed == 0) {
    timeval tv;
    MemSet(&tv, 0, sizeof(timeval));
    gettimeofday(&tv, NULL);
    U64 s = (tv.tv_sec(U64) * 1000003) ^ (tv.tv_usec(U64) * 999983) ^ 0x9E3779B97F4A7C15;
    if (s == 0) s = 0xCAFEBABE12345678;
    g_rng_state = s;
    g_rng_deterministic = 0;
  } else {
    g_rng_state = seed;
    g_rng_deterministic = 1;
  }
}

U64 ScriptureNextRand()
{
  if (g_rng_state == 0) {
    ScriptureSeedRng(0);
  }
  U64 x = g_rng_state;
  x ^= x >> 12;
  x ^= x << 25;
  x ^= x >> 27;
  g_rng_state = x;
  return x * 0x2545F4914F6CDD1D;
}

F64 ScriptureNextRandUnit()
{
  U64 r = ScriptureNextRand();
  U64 mant = (r >> 11) & 0x1FFFFFFFFFFFFF;
  return mant(F64) / 9007199254740992.0;
}

U64 ScriptureHashBytes(U8 *str, I64 len)
{
  U64 h = 14695981039346656037;
  I64 i = 0;
  while (i < len) {
    h ^= HcToLower(str[i]);
    h *= 1099511628211;
    i++;
  }
  return h;
}

Bool ScriptureEnsureVocabArena(I64 needed)
{
  if (g_vocab_arena_len + needed + 2 <= g_vocab_arena_cap) return TRUE;
  I64 new_cap = g_vocab_arena_cap * 2;
  if (new_cap < g_vocab_arena_len + needed + 65536)
    new_cap = g_vocab_arena_len + needed + 65536;
  U8 *nb = ReAlloc(g_vocab_arena, new_cap);
  if (!nb) return FALSE;
  g_vocab_arena = nb;
  g_vocab_arena_cap = new_cap;
  return TRUE;
}

I32 ScriptureVocabFindOrInsert(U8 *word_lower, I64 wlen, Bool allow_insert)
{
  if (!g_vocab_table || wlen <= 0) return -1;
  U64 h = ScriptureHashBytes(word_lower, wlen);
  I32 idx = (h & VOCAB_MASK)(I32);
  I64 probes = 0;

  while (probes < VOCAB_BUCKETS) {
    CVocabEntry *e = &g_vocab_table[idx];
    if (e->word_len == 0) {
      if (!allow_insert) return -1;
      if (!ScriptureEnsureVocabArena(wlen + 1)) return -1;
      I64 w_off = g_vocab_arena_len;
      MemCpy(g_vocab_arena + w_off, word_lower, wlen);
      g_vocab_arena[w_off + wlen] = 0;
      g_vocab_arena_len += wlen + 1;

      e->word_off = w_off;
      e->word_len = wlen(I32);
      e->df = 0;
      e->post_start = 0;
      e->post_count = 0;
      e->last_verse = -1;

      g_vocab_used[g_vocab_count++] = idx;
      return idx;
    }

    if (e->word_len == wlen) {
      U8 *existing = g_vocab_arena + e->word_off;
      if (memcmp(existing, word_lower, wlen) == 0)
        return idx;
    }

    idx = ((idx + 1) & VOCAB_MASK)(I32);
    probes++;
  }
  return -1;
}

U0 ScriptureFreeIndex()
{
  if (g_vocab_table) { Free(g_vocab_table); g_vocab_table = NULL; }
  if (g_vocab_used)  { Free(g_vocab_used);  g_vocab_used = NULL; }
  if (g_vocab_arena) { Free(g_vocab_arena); g_vocab_arena = NULL; }
  if (g_postings)    { Free(g_postings);    g_postings = NULL; }
  if (g_doc_len)     { Free(g_doc_len);     g_doc_len = NULL; }
  if (g_bm25_scores) { Free(g_bm25_scores); g_bm25_scores = NULL; }
  g_vocab_count = 0;
  g_vocab_arena_len = 0;
  g_vocab_arena_cap = 0;
  g_total_postings = 0;
}

I64 ScriptureBuildIndex()
{
  if (!g_bible_initialized || g_verse_count <= 0) return -1;

  ScriptureFreeIndex();
  ScriptureInitSynTable();
  if (g_rng_state == 0) ScriptureSeedRng(0);

  g_vocab_table = CAlloc(VOCAB_BUCKETS * sizeof(CVocabEntry));
  g_vocab_used  = MAlloc(VOCAB_BUCKETS * sizeof(I32));
  g_vocab_arena = MAlloc(INITIAL_VOCAB_ARENA);
  g_doc_len     = CAlloc(g_verse_count * sizeof(I16));
  g_bm25_scores = MAlloc(g_verse_count * sizeof(F64));

  if (!g_vocab_table || !g_vocab_used || !g_vocab_arena || !g_doc_len || !g_bm25_scores) {
    ScriptureFreeIndex();
    return -2;
  }
  g_vocab_arena_cap = INITIAL_VOCAB_ARENA;
  g_vocab_arena_len = 0;
  g_vocab_count = 0;

  /* Pass 1: Compute document lengths and document frequencies (df) */
  I64 total_words = 0;
  U8 wbuf[64];
  I64 v = 0;
  while (v < g_verse_count) {
    U8 *txt = g_text_arena + g_verses[v].text_off;
    I64 tlen = g_verses[v].text_len;
    I64 i = 0;
    I16 dlen = 0;
    while (i < tlen) {
      while (i < tlen && !HcIsAlpha(txt[i])) i++;
      if (i >= tlen) break;
      I64 wstart = i;
      while (i < tlen && HcIsAlpha(txt[i])) i++;
      I64 wlen = i - wstart;
      dlen++;
      total_words++;
      if (wlen >= 2 && wlen < 60) {
        I64 k = 0;
        while (k < wlen) {
          wbuf[k] = HcToLower(txt[wstart + k]);
          k++;
        }
        wbuf[wlen] = 0;
        I32 b_idx = ScriptureVocabFindOrInsert(wbuf, wlen, TRUE);
        if (b_idx >= 0) {
          CVocabEntry *e = &g_vocab_table[b_idx];
          if (e->last_verse != v) {
            e->last_verse = v(I32);
            e->df++;
          }
        }
      }
    }
    g_doc_len[v] = dlen;
    v++;
  }

  if (g_verse_count > 0)
    g_avg_doc_len = total_words(F64) / g_verse_count(F64);
  if (g_avg_doc_len < 1.0) g_avg_doc_len = 25.0;

  /* Compute prefix sums for contiguous postings array */
  I64 running_off = 0;
  I64 u = 0;
  while (u < g_vocab_count) {
    CVocabEntry *e = &g_vocab_table[g_vocab_used[u]];
    e->post_start = running_off(I32);
    e->post_count = 0;
    e->last_verse = -1;
    running_off += e->df;
    u++;
  }

  g_total_postings = running_off;
  g_postings = MAlloc((g_total_postings + 1) * sizeof(CPosting));
  if (!g_postings) {
    ScriptureFreeIndex();
    return -3;
  }

  /* Pass 2: Populate postings with exact (verse_idx, tf) */
  v = 0;
  while (v < g_verse_count) {
    U8 *txt = g_text_arena + g_verses[v].text_off;
    I64 tlen = g_verses[v].text_len;
    I64 i = 0;
    while (i < tlen) {
      while (i < tlen && !HcIsAlpha(txt[i])) i++;
      if (i >= tlen) break;
      I64 wstart = i;
      while (i < tlen && HcIsAlpha(txt[i])) i++;
      I64 wlen = i - wstart;
      if (wlen >= 2 && wlen < 60) {
        I64 k = 0;
        while (k < wlen) {
          wbuf[k] = HcToLower(txt[wstart + k]);
          k++;
        }
        wbuf[wlen] = 0;
        I32 b_idx = ScriptureVocabFindOrInsert(wbuf, wlen, FALSE);
        if (b_idx >= 0) {
          CVocabEntry *e = &g_vocab_table[b_idx];
          if (e->last_verse == v && e->post_count > 0) {
            g_postings[e->post_start + e->post_count - 1].tf++;
          } else {
            I64 p_idx = e->post_start + e->post_count;
            g_postings[p_idx].verse_idx = v(I32);
            g_postings[p_idx].tf = 1;
            g_postings[p_idx].pad = 0;
            e->post_count++;
            e->last_verse = v(I32);
          }
        }
      }
    }
    v++;
  }

  return 0;
}

I32 ScriptureFindBook(U8 *name)
{
  if (!name || !g_bible_initialized) return -1;
  if (name[0] == 0) return -1;

  while (*name && HcIsSpace(*name)) name++;
  U8 clean[128];
  I64 len = 0;
  while (name[len] && len < 127) {
    clean[len] = name[len];
    len++;
  }
  while (len > 0 && HcIsSpace(clean[len - 1])) len--;
  clean[len] = 0;
  if (len == 0) return -1;

  U8 norm[128];
  if (len > 4 && HcStrStartsWithI(clean, "III ")) {
    norm[0] = '3';
    StrCpy(norm + 1, clean + 3);
  } else if (len > 3 && HcStrStartsWithI(clean, "II ")) {
    norm[0] = '2';
    StrCpy(norm + 1, clean + 2);
  } else if (len > 2 && HcStrStartsWithI(clean, "I ")) {
    norm[0] = '1';
    StrCpy(norm + 1, clean + 1);
  } else {
    StrCpy(norm, clean);
  }

  I32 i = 0;
  while (i < MAX_BOOKS) {
    if (HcStrEqI(norm, g_canonical_books[i]) || HcStrEqI(norm, g_kjv_titles[i]))
      return i;
    i++;
  }

  if (HcStrEqI(norm, "Psalm") || HcStrEqI(norm, "The Psalms"))
    return 18;
  if (HcStrEqI(norm, "Proverb") || HcStrEqI(norm, "The Proverbs"))
    return 19;
  if (HcStrEqI(norm, "Song of Songs") || HcStrEqI(norm, "Canticles") ||
      HcStrEqI(norm, "The Song of Solomon"))
    return 21;
  if (HcStrEqI(norm, "Qoheleth") || HcStrEqI(norm, "The Preacher"))
    return 20;
  if (HcStrEqI(norm, "Revelations") || HcStrEqI(norm, "Apocalypse") ||
      HcStrEqI(norm, "The Revelation") ||
      HcStrEqI(norm, "The Revelation of Saint John the Divine"))
    return 65;

  return -1;
}

I64 ScriptureFindVerseIdx(I32 book_idx, I32 chapter, I32 verse)
{
  if (!g_bible_initialized) return -1;
  if (book_idx < 0 || book_idx >= MAX_BOOKS) return -1;
  if (chapter <= 0 || chapter >= MAX_CHAPTERS_PER_BOOK || verse <= 0) return -1;

  CBook *bk = &g_books[book_idx];
  if (bk->verse_count <= 0) return -1;

  I32 start_idx = bk->chapter_start[chapter];
  if (start_idx < 0) return -1;

  I64 end_idx = bk->first_verse_idx + bk->verse_count;
  I64 idx = start_idx;
  while (idx < end_idx) {
    if (g_verses[idx].book_idx != book_idx || g_verses[idx].chapter != chapter)
      break;
    if (g_verses[idx].verse == verse)
      return idx;
    idx++;
  }
  return -1;
}

Bool ScriptureParseReference(U8 *ref_str, I32 *out_book, I32 *out_chap,
                             I32 *out_vstart, I32 *out_vend)
{
  if (!ref_str) return FALSE;
  if (ref_str[0] == 0) return FALSE;

  I64 len = StrLen(ref_str);
  I64 start = 0;
  while (start < len && HcIsSpace(ref_str[start])) start++;
  while (len > start && HcIsSpace(ref_str[len - 1])) len--;
  if (start >= len) return FALSE;

  I64 colon_pos = -1;
  I64 i = len - 1;
  while (i > start) {
    if (ref_str[i] == ':') {
      colon_pos = i;
      break;
    }
    i--;
  }
  if (colon_pos <= start || colon_pos + 1 >= len) return FALSE;

  I64 chap_start = colon_pos;
  while (chap_start > start && HcIsDigit(ref_str[chap_start - 1]))
    chap_start--;
  if (chap_start == colon_pos || chap_start <= start) return FALSE;

  I32 chap = 0;
  i = chap_start;
  while (i < colon_pos) {
    chap = chap * 10 + (ref_str[i] - '0');
    i++;
  }
  if (chap <= 0) return FALSE;

  I64 book_end = chap_start;
  while (book_end > start && HcIsSpace(ref_str[book_end - 1]))
    book_end--;
  if (book_end <= start) return FALSE;

  U8 book_buf[128];
  I64 blen = book_end - start;
  if (blen > 127) blen = 127;
  MemCpy(book_buf, ref_str + start, blen);
  book_buf[blen] = 0;

  I32 book_idx = ScriptureFindBook(book_buf);
  if (book_idx < 0) return FALSE;

  i = colon_pos + 1;
  if (i >= len || !HcIsDigit(ref_str[i])) return FALSE;
  I32 vstart = 0;
  while (i < len && HcIsDigit(ref_str[i])) {
    vstart = vstart * 10 + (ref_str[i] - '0');
    i++;
  }
  if (vstart <= 0) return FALSE;

  I32 vend = vstart;
  if (i < len && ref_str[i] == '-') {
    i++;
    if (i >= len || !HcIsDigit(ref_str[i])) return FALSE;
    vend = 0;
    while (i < len && HcIsDigit(ref_str[i])) {
      vend = vend * 10 + (ref_str[i] - '0');
      i++;
    }
    if (vend < vstart) return FALSE;
  }
  if (i != len) return FALSE;

  *out_book = book_idx;
  *out_chap = chap;
  *out_vstart = vstart;
  *out_vend = vend;
  return TRUE;
}

U0 ScriptureFormatCanonicalRef(I32 book_idx, I32 chap, I32 vstart, I32 vend,
                               U8 *out_ref, I64 out_cap)
{
  if (!out_ref || out_cap <= 0) return;
  out_ref[0] = 0;
  if (book_idx < 0 || book_idx >= MAX_BOOKS) return;
  if (vend > vstart) {
    snprintf(out_ref, out_cap, "%s %d:%d-%d",
             g_books[book_idx].name, chap, vstart, vend);
  } else {
    snprintf(out_ref, out_cap, "%s %d:%d",
             g_books[book_idx].name, chap, vstart);
  }
}

I64 ScriptureLookupReference(U8 *ref_str, U8 *out_text, I64 out_cap,
                             U8 *out_canonical_ref, I64 ref_cap)
{
  if (!g_bible_initialized || !ref_str || !out_text || out_cap <= 1)
    return -1;

  I32 book_idx = -1, chap = 0, vstart = 0, vend = 0;
  if (!ScriptureParseReference(ref_str, &book_idx, &chap, &vstart, &vend))
    return -2;

  I64 first_idx = ScriptureFindVerseIdx(book_idx, chap, vstart);
  if (first_idx < 0) return -3;

  I64 last_idx = ScriptureFindVerseIdx(book_idx, chap, vend);
  if (last_idx < 0 || last_idx < first_idx) return -3;

  if (out_canonical_ref && ref_cap > 0) {
    ScriptureFormatCanonicalRef(book_idx, chap, vstart, vend,
                                out_canonical_ref, ref_cap);
  }

  I64 pos = 0;
  I64 idx = first_idx;
  while (idx <= last_idx) {
    U8 *vtxt = BibleVerseText(idx);
    I64 vlen = g_verses[idx].text_len;
    if (idx > first_idx && pos + 1 < out_cap) {
      out_text[pos++] = ' ';
    }
    I64 copy_len = vlen;
    if (pos + copy_len >= out_cap) {
      copy_len = out_cap - 1 - pos;
    }
    if (copy_len > 0) {
      MemCpy(out_text + pos, vtxt, copy_len);
      pos += copy_len;
    }
    idx++;
  }
  out_text[pos] = 0;
  return pos;
}

Bool ScriptureIsStopword(U8 *w, I64 wlen)
{
  if (wlen < 3) return TRUE;
  if (HcStrEqI(w, "the") || HcStrEqI(w, "and") || HcStrEqI(w, "for") ||
      HcStrEqI(w, "not") || HcStrEqI(w, "but") || HcStrEqI(w, "are") ||
      HcStrEqI(w, "was") || HcStrEqI(w, "were") || HcStrEqI(w, "have") ||
      HcStrEqI(w, "has") || HcStrEqI(w, "had") || HcStrEqI(w, "this") ||
      HcStrEqI(w, "that") || HcStrEqI(w, "with") || HcStrEqI(w, "from") ||
      HcStrEqI(w, "unto") || HcStrEqI(w, "shall") || HcStrEqI(w, "will") ||
      HcStrEqI(w, "into") || HcStrEqI(w, "upon") || HcStrEqI(w, "they") ||
      HcStrEqI(w, "them") || HcStrEqI(w, "their") || HcStrEqI(w, "there") ||
      HcStrEqI(w, "which") || HcStrEqI(w, "when") || HcStrEqI(w, "what") ||
      HcStrEqI(w, "where") || HcStrEqI(w, "who") || HcStrEqI(w, "whom") ||
      HcStrEqI(w, "his") || HcStrEqI(w, "her") || HcStrEqI(w, "him") ||
      HcStrEqI(w, "you") || HcStrEqI(w, "your") || HcStrEqI(w, "our") ||
      HcStrEqI(w, "out") || HcStrEqI(w, "all") || HcStrEqI(w, "any") ||
      HcStrEqI(w, "can") || HcStrEqI(w, "cannot") || HcStrEqI(w, "may") ||
      HcStrEqI(w, "more") || HcStrEqI(w, "than") || HcStrEqI(w, "also") ||
      HcStrEqI(w, "only") || HcStrEqI(w, "other") || HcStrEqI(w, "some") ||
      HcStrEqI(w, "such") || HcStrEqI(w, "then") || HcStrEqI(w, "these") ||
      HcStrEqI(w, "those") || HcStrEqI(w, "very") || HcStrEqI(w, "here") ||
      HcStrEqI(w, "error") || HcStrEqI(w, "warning") || HcStrEqI(w, "note") ||
      HcStrEqI(w, "help") || HcStrEqI(w, "rustc") || HcStrEqI(w, "main") ||
      HcStrEqI(w, "src") || HcStrEqI(w, "let") || HcStrEqI(w, "mut") ||
      HcStrEqI(w, "pub") || HcStrEqI(w, "impl") || HcStrEqI(w, "struct") ||
      HcStrEqI(w, "enum") || HcStrEqI(w, "crate") || HcStrEqI(w, "self") ||
      HcStrEqI(w, "value") || HcStrEqI(w, "variable") || HcStrEqI(w, "time"))
    return TRUE;
  return FALSE;
}

U0 ScriptureAddQueryBucket(CQueryTerm *qterms, I64 *qcount, I32 bucket, F64 weight)
{
  if (bucket < 0 || !qterms) return;
  I64 i = 0;
  while (i < *qcount) {
    if (qterms[i].vocab_bucket == bucket) {
      if (weight > qterms[i].weight)
        qterms[i].weight = weight;
      return;
    }
    i++;
  }
  if (*qcount >= MAX_QUERY_TERMS) return;
  qterms[*qcount].vocab_bucket = bucket;
  qterms[*qcount].weight = weight;
  *qcount = *qcount + 1;
}

U0 ScriptureAddQueryWord(CQueryTerm *qterms, I64 *qcount, U8 *word_lower, F64 weight, Bool expand_prefix)
{
  if (!word_lower || !g_vocab_table) return;
  if (word_lower[0] == 0) return;
  I64 wlen = StrLen(word_lower);
  I32 exact_b = ScriptureVocabFindOrInsert(word_lower, wlen, FALSE);
  if (exact_b >= 0) {
    ScriptureAddQueryBucket(qterms, qcount, exact_b, weight);
  }

  /* Optional fuzzy/prefix stem expansion for KJV archaic endings (-eth, -est, -er, -ed) */
  if (expand_prefix && wlen >= 5 && *qcount < MAX_QUERY_TERMS) {
    I64 u = 0;
    while (u < g_vocab_count && *qcount < MAX_QUERY_TERMS) {
      I32 b = g_vocab_used[u];
      CVocabEntry *e = &g_vocab_table[b];
      if (e->word_len > wlen && e->word_len <= wlen + 3) {
        U8 *vw = g_vocab_arena + e->word_off;
        if (memcmp(vw, word_lower, wlen) == 0) {
          ScriptureAddQueryBucket(qterms, qcount, b, weight * 0.65);
        }
      }
      u++;
    }
  }
}

/* Step 1 + 2 + 3: Tokenize diagnostic, expand to KJV vocabulary, and rank all
 * 31,102 verses using BM25. Populates out_top_idx[0..top_n) and out_top_scores[0..top_n)
 * in descending order of BM25 score, returning top_n (0..max_top). */
I64 ScriptureRankBM25(U8 *query_text, I32 *out_top_idx, F64 *out_top_scores, I64 max_top)
{
  if (!g_bible_initialized || !g_vocab_table || !g_bm25_scores || !query_text)
    return 0;
  if (max_top <= 0) return 0;
  if (max_top > BM25_TOP_K) max_top = BM25_TOP_K;

  CQueryTerm qterms[MAX_QUERY_TERMS];
  I64 qcount = 0;

  /* 1. Tokenize diagnostic text (including alphanumeric codes like E0499) */
  I64 qlen = StrLen(query_text);
  I64 i = 0;
  U8 tok[64];
  while (i < qlen) {
    while (i < qlen && !HcIsAlnum(query_text[i])) i++;
    if (i >= qlen) break;
    I64 tstart = i;
    while (i < qlen && HcIsAlnum(query_text[i])) i++;
    I64 tlen = i - tstart;
    if (tlen >= 3 && tlen < 60) {
      I64 k = 0;
      while (k < tlen) {
        tok[k] = HcToLower(query_text[tstart + k]);
        k++;
      }
      tok[tlen] = 0;

      /* 2. Check Biblical Synonym Dictionary */
      Bool found_syn = FALSE;
      I64 s = 0;
      while (s < g_syn_count) {
        if (HcStrEqI(tok, g_syn_table[s].rust_term)) {
          ScriptureAddQueryWord(qterms, &qcount, g_syn_table[s].kjv_term,
                                g_syn_table[s].weight, FALSE);
          found_syn = TRUE;
        }
        s++;
      }

      /* Also include the direct token (and KJV stem matches) if not a stopword */
      if (!ScriptureIsStopword(tok, tlen)) {
        F64 direct_w = 2.0;
        if (found_syn) direct_w = 1.5;
        ScriptureAddQueryWord(qterms, &qcount, tok, direct_w, TRUE);
      }
    }
  }

  if (qcount == 0) return 0;

  /* 3. Clear score accumulator and run BM25 over inverted index postings */
  MemSet(g_bm25_scores, 0, g_verse_count * sizeof(F64));

  F64 n_docs = g_verse_count(F64);
  F64 k1 = 1.5;
  F64 b_param = 0.75;

  I64 q = 0;
  while (q < qcount) {
    CVocabEntry *e = &g_vocab_table[qterms[q].vocab_bucket];
    F64 w = qterms[q].weight;
    F64 df = e->df(F64);
    if (df > 0.0) {
      F64 idf = log(1.0 + (n_docs - df + 0.5) / (df + 0.5));
      I64 p_start = e->post_start;
      I64 p_end = p_start + e->post_count;
      I64 p = p_start;
      while (p < p_end) {
        I32 v_idx = g_postings[p].verse_idx;
        F64 tf = g_postings[p].tf(F64);
        F64 dl = g_doc_len[v_idx](F64);
        F64 tf_norm = (tf * (k1 + 1.0)) /
                      (tf + k1 * (1.0 - b_param + b_param * (dl / g_avg_doc_len)));
        g_bm25_scores[v_idx] += w * idf * tf_norm;
        p++;
      }
    }
    q++;
  }

  /* Collect Top-K verses with length/wisdom quality adjustment */
  I64 top_n = 0;
  I64 v = 0;
  while (v < g_verse_count) {
    F64 sc = g_bm25_scores[v];
    if (sc > 0.0) {
      I16 dl = g_doc_len[v];
      if (dl >= 6 && dl <= 32) sc *= 1.15;
      else if (dl > 55) sc *= 0.75;

      /* Insert into sorted top-K if higher than smallest */
      if (top_n < max_top || sc > out_top_scores[top_n - 1]) {
        I64 ins = top_n;
        if (ins >= max_top) ins = max_top - 1;
        else top_n++;

        while (ins > 0 && sc > out_top_scores[ins - 1]) {
          out_top_scores[ins] = out_top_scores[ins - 1];
          out_top_idx[ins] = out_top_idx[ins - 1];
          ins--;
        }
        out_top_scores[ins] = sc;
        out_top_idx[ins] = v(I32);
      }
    }
    v++;
  }

  /* Prune weak tail candidates (< 35% of best score) so weighted sampling stays sharp */
  if (top_n > 1) {
    F64 min_keep = out_top_scores[0] * 0.35;
    while (top_n > 1 && out_top_scores[top_n - 1] < min_keep) {
      top_n--;
    }
  }

  return top_n;
}

/* Step 4: Weighted random sampling from Top 5-10 BM25 matches */
I64 ScriptureSampleWeightedTopK(I32 *top_idx, F64 *top_scores, I64 top_n)
{
  if (top_n <= 0 || !top_idx || !top_scores) return -1;
  if (top_n == 1) return top_idx[0];

  /* Square the BM25 weights to favor top matches while giving all Top-K a chance */
  F64 weights[BM25_TOP_K];
  F64 sum_w = 0.0;
  I64 i = 0;
  while (i < top_n) {
    F64 w = top_scores[i] * top_scores[i];
    weights[i] = w;
    sum_w += w;
    i++;
  }
  if (sum_w <= 0.0) return top_idx[0];

  F64 target = ScriptureNextRandUnit() * sum_w;
  F64 accum = 0.0;
  i = 0;
  while (i < top_n) {
    accum += weights[i];
    if (target <= accum)
      return top_idx[i];
    i++;
  }
  return top_idx[top_n - 1];
}

/* Step 5: Book of Revelation (Apocalypse, Book 65) random fallback when no
 * meaningful BM25 match exists — because the code is evidently that bad! */
I64 ScriptureRandomRevelationVerse()
{
  if (!g_bible_initialized) return -1;
  CBook *rev = &g_books[65];
  if (rev->verse_count > 0 && rev->first_verse_idx >= 0) {
    I64 r = (ScriptureNextRand() >> 1)(I64);
    if (r < 0) r = -r;
    I64 offset = r % rev->verse_count;
    return rev->first_verse_idx + offset;
  }
  /* Fallback if a partial test Bible has no Book 65 */
  if (g_verse_count > 0) {
    I64 r = (ScriptureNextRand() >> 1)(I64);
    if (r < 0) r = -r;
    return r % g_verse_count;
  }
  return -1;
}

/* Deterministic top-1 BM25 search helper (used by scripture_search FFI) */
I64 ScriptureSearchKeywords(U8 *query)
{
  I32 top_idx[BM25_TOP_K];
  F64 top_scores[BM25_TOP_K];
  I64 n = ScriptureRankBM25(query, top_idx, top_scores, BM25_TOP_K);
  if (n <= 0 || top_scores[0] < 3.0) return -1;
  return top_idx[0];
}
