use std::env;
use std::ffi::{CStr, CString};
use std::os::raw::c_char;
use std::path::{Path, PathBuf};
use std::sync::Mutex;

static ENGINE_LOCK: Mutex<bool> = Mutex::new(false);

extern "C" {
    pub fn scripture_init(bible_path: *const c_char) -> i64;

    pub fn scripture_judge(
        diagnostic: *const c_char,
        diagnostic_len: i64,
        output: *mut c_char,
        output_capacity: i64,
    ) -> i64;

    pub fn scripture_shutdown();

    pub fn scripture_verse_count() -> i64;
    pub fn scripture_book_count() -> i64;
    pub fn scripture_vocab_count() -> i64;
    pub fn scripture_set_seed(seed: u64);

    pub fn scripture_lookup(
        reference: *const c_char,
        output: *mut c_char,
        output_capacity: i64,
    ) -> i64;

    pub fn scripture_search(
        query: *const c_char,
        out_ref: *mut c_char,
        ref_cap: i64,
        out_text: *mut c_char,
        text_cap: i64,
    ) -> i64;
}

/// Structured diagnostic metadata extracted from `cargo_metadata` to pass to HolyC.
#[derive(Debug, Clone, Default)]
pub struct DiagnosticPayload {
    pub level: String,
    pub code: Option<String>,
    pub location: Option<String>,
    pub message: String,
    pub notes: Option<String>,
    pub use_color: bool,
    pub deterministic: bool,
}

impl DiagnosticPayload {
    pub fn to_wire_format(&self) -> String {
        let mut s = String::with_capacity(512);
        s.push_str("LEVEL: ");
        s.push_str(if self.level.is_empty() {
            "error"
        } else {
            &self.level
        });
        s.push('\n');

        if let Some(ref c) = self.code {
            if !c.is_empty() {
                s.push_str("CODE: ");
                s.push_str(&c.replace('\n', " "));
                s.push('\n');
            }
        }

        if let Some(ref loc) = self.location {
            if !loc.is_empty() {
                s.push_str("LOCATION: ");
                s.push_str(&loc.replace('\n', " "));
                s.push('\n');
            }
        }

        s.push_str("COLOR: ");
        s.push_str(if self.use_color { "1" } else { "0" });
        s.push('\n');

        if self.deterministic {
            s.push_str("DETERMINISTIC: 1\n");
        }

        s.push_str("MESSAGE: ");
        s.push_str(&self.message.replace('\n', " "));
        s.push('\n');

        if let Some(ref notes) = self.notes {
            if !notes.is_empty() {
                s.push_str("NOTES: ");
                s.push_str(&notes.replace('\n', " | "));
                s.push('\n');
            }
        }
        s
    }
}

pub const EMBEDDED_BIBLE: &[u8] = include_bytes!("../assets/Bible.TXT");

/// Locate the TempleOS `Bible.TXT` (or `Bible.TXT.Z`) asset.
pub fn resolve_bible_path(explicit: Option<&Path>) -> Result<PathBuf, String> {
    if let Some(p) = explicit {
        if p.is_file() {
            return Ok(p.to_path_buf());
        }
        return Err(format!("Specified Bible file does not exist: {}", p.display()));
    }

    if let Ok(env_path) = env::var("CARGO_ABSOLVE_BIBLE") {
        let p = PathBuf::from(env_path);
        if p.is_file() {
            return Ok(p);
        }
    }

    let relative_candidates = [
        PathBuf::from("assets/Bible.TXT"),
        PathBuf::from("Misc/Bible.TXT"),
        PathBuf::from("Misc/Bible.TXT.Z"),
    ];
    for candidate in &relative_candidates {
        if candidate.is_file() {
            return Ok(candidate.clone());
        }
    }

    let compiled_default = PathBuf::from(env!("CARGO_ABSOLVE_DEFAULT_BIBLE"));
    if compiled_default.is_file() {
        return Ok(compiled_default);
    }

    // Fallback: extract the embedded authentic TempleOS Bible to a temporary cache directory
    let cache_dir = env::temp_dir().join("cargo_absolve");
    let _ = std::fs::create_dir_all(&cache_dir);
    let fallback_path = cache_dir.join("Bible.TXT");
    let needs_write = match std::fs::metadata(&fallback_path) {
        Ok(meta) => meta.len() != EMBEDDED_BIBLE.len() as u64,
        Err(_) => true,
    };
    if needs_write {
        std::fs::write(&fallback_path, EMBEDDED_BIBLE).map_err(|e| {
            format!(
                "Failed to unpack embedded Bible to {}: {}",
                fallback_path.display(),
                e
            )
        })?;
    }
    if fallback_path.is_file() {
        return Ok(fallback_path);
    }

    Err("Could not locate or extract TempleOS Bible.TXT".to_string())
}

/// Initialize the HolyC biblical engine with the given `Bible.TXT` (or `.TXT.Z`) path.
pub fn init(bible_path: &Path) -> Result<(), String> {
    let mut guard = ENGINE_LOCK.lock().unwrap_or_else(|e| e.into_inner());
    let path_str = bible_path
        .to_str()
        .ok_or_else(|| "Bible path is not valid UTF-8".to_string())?;
    let c_path = CString::new(path_str).map_err(|e| format!("Invalid Bible path: {}", e))?;

    let rc = unsafe { scripture_init(c_path.as_ptr()) };
    if rc != 0 {
        *guard = false;
        return Err(format!(
            "HolyC scripture_init failed with error code {} for {}",
            rc,
            bible_path.display()
        ));
    }
    *guard = true;
    Ok(())
}

/// Ensure the HolyC engine is initialized using the default Bible path if not already loaded.
pub fn ensure_initialized() -> Result<(), String> {
    {
        let guard = ENGINE_LOCK.lock().unwrap_or_else(|e| e.into_inner());
        if *guard && unsafe { scripture_verse_count() } > 0 {
            return Ok(());
        }
    }
    let path = resolve_bible_path(None)?;
    init(&path)
}

/// Shut down the HolyC biblical engine and release all HolyC allocations.
pub fn shutdown() {
    let mut guard = ENGINE_LOCK.lock().unwrap_or_else(|e| e.into_inner());
    unsafe {
        scripture_shutdown();
    }
    *guard = false;
}

/// Seed the HolyC engine's PRNG (`0` = randomized via clock; `> 0` = deterministic seed).
pub fn set_seed(seed: u64) {
    let _guard = ENGINE_LOCK.lock().unwrap_or_else(|e| e.into_inner());
    unsafe {
        scripture_set_seed(seed);
    }
}

/// Return the number of verses indexed in the HolyC engine (31,102 for full KJV).
pub fn verse_count() -> i64 {
    let _guard = ENGINE_LOCK.lock().unwrap_or_else(|e| e.into_inner());
    unsafe { scripture_verse_count() }
}

/// Return the number of books indexed in the HolyC engine (66 for full KJV).
pub fn book_count() -> i64 {
    let _guard = ENGINE_LOCK.lock().unwrap_or_else(|e| e.into_inner());
    unsafe { scripture_book_count() }
}

/// Return the number of unique lowercase vocabulary words indexed for BM25 in HolyC.
pub fn vocab_count() -> i64 {
    let _guard = ENGINE_LOCK.lock().unwrap_or_else(|e| e.into_inner());
    unsafe { scripture_vocab_count() }
}

/// Invoke `scripture_judge` in HolyC with a raw diagnostic string or wire payload.
pub fn judge_raw(diagnostic: &str) -> Result<String, String> {
    let _guard = ENGINE_LOCK.lock().unwrap_or_else(|e| e.into_inner());
    let c_diag =
        CString::new(diagnostic.as_bytes()).map_err(|_| "Diagnostic contains interior NUL")?;
    let mut buf = vec![0u8; 8192];

    let written = unsafe {
        scripture_judge(
            c_diag.as_ptr(),
            diagnostic.len() as i64,
            buf.as_mut_ptr() as *mut c_char,
            buf.len() as i64,
        )
    };

    if written < 0 {
        return Err(format!("HolyC scripture_judge returned error {}", written));
    }

    let len = (written as usize).min(buf.len() - 1);
    String::from_utf8(buf[..len].to_vec())
        .map_err(|e| format!("Invalid UTF-8 from HolyC judgment: {}", e))
}

/// Judge a structured `DiagnosticPayload` using the HolyC engine.
pub fn judge_diagnostic(payload: &DiagnosticPayload) -> Result<String, String> {
    let wire = payload.to_wire_format();
    judge_raw(&wire)
}

/// Generate the HolyC Absolution verdict for a clean build.
pub fn absolve(use_color: bool) -> Result<String, String> {
    let wire = if use_color {
        "ABSOLVE|COLOR: 1"
    } else {
        "ABSOLVE|COLOR: 0"
    };
    judge_raw(wire)
}

/// Look up an exact verse or contiguous range (e.g. `"Matthew 6:24"`, `"Job 14:1-2"`) via HolyC.
pub fn lookup_reference(reference: &str) -> Result<String, String> {
    let _guard = ENGINE_LOCK.lock().unwrap_or_else(|e| e.into_inner());
    let c_ref = CString::new(reference).map_err(|_| "Reference contains interior NUL")?;
    let mut buf = vec![0u8; 4096];

    let written = unsafe {
        scripture_lookup(
            c_ref.as_ptr(),
            buf.as_mut_ptr() as *mut c_char,
            buf.len() as i64,
        )
    };

    if written < 0 {
        return Err(format!(
            "Reference '{}' not found (HolyC code {})",
            reference, written
        ));
    }

    let len = (written as usize).min(buf.len() - 1);
    String::from_utf8(buf[..len].to_vec())
        .map_err(|e| format!("Invalid UTF-8 in verse text: {}", e))
}

/// Search the indexed KJV Bible in HolyC using BM25 + biblical synonym expansion.
/// Returns `(canonical_reference, verbatim_kjv_text)`.
pub fn search_keywords(query: &str) -> Result<(String, String), String> {
    let _guard = ENGINE_LOCK.lock().unwrap_or_else(|e| e.into_inner());
    let c_query = CString::new(query).map_err(|_| "Query contains interior NUL")?;
    let mut ref_buf = vec![0u8; 128];
    let mut txt_buf = vec![0u8; 4096];

    let written = unsafe {
        scripture_search(
            c_query.as_ptr(),
            ref_buf.as_mut_ptr() as *mut c_char,
            ref_buf.len() as i64,
            txt_buf.as_mut_ptr() as *mut c_char,
            txt_buf.len() as i64,
        )
    };

    if written < 0 {
        return Err(format!("No matching verse found for query '{}' (code {})", query, written));
    }

    let ref_cstr = unsafe { CStr::from_ptr(ref_buf.as_ptr() as *const c_char) };
    let reference = ref_cstr.to_string_lossy().into_owned();
    let len = (written as usize).min(txt_buf.len() - 1);
    let text = String::from_utf8(txt_buf[..len].to_vec())
        .map_err(|e| format!("Invalid UTF-8 in verse text: {}", e))?;

    Ok((reference, text))
}

