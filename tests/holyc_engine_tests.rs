use cargo_absolve::cargo::{parse_cli_args, process_cargo_stream};
use cargo_absolve::ffi::{self, DiagnosticPayload};
use std::collections::HashSet;
use std::fs;
use std::io::Cursor;
use std::path::PathBuf;
use std::process::Command;
use std::sync::Mutex;

static TEST_MUTEX: Mutex<()> = Mutex::new(());

fn setup_full_bible() {
    let path = ffi::resolve_bible_path(None).expect("Bible.TXT must exist");
    ffi::init(&path).expect("HolyC scripture_init should succeed on Bible.TXT");
}

#[test]
fn test_bible_parsing_counts_and_boundaries() {
    let _lock = TEST_MUTEX.lock().unwrap_or_else(|e| e.into_inner());
    setup_full_bible();

    assert_eq!(
        ffi::book_count(),
        66,
        "Full KJV Bible in TempleOS Bible.TXT must have exactly 66 books"
    );
    assert_eq!(
        ffi::verse_count(),
        31102,
        "Full KJV Bible in TempleOS Bible.TXT must have exactly 31,102 verses"
    );
    assert!(
        ffi::vocab_count() > 12000,
        "HolyC BM25 inverted index should index >12,000 unique KJV words, got {}",
        ffi::vocab_count()
    );

    // First verse of the Bible
    let gen_1_1 = ffi::lookup_reference("Genesis 1:1").unwrap();
    assert_eq!(
        gen_1_1,
        "In the beginning God created the heaven and the earth."
    );

    // Mid-line verse marker in Bible.TXT (1:15 starts in the middle of line 342)
    let gen_1_14 = ffi::lookup_reference("Genesis 1:14").unwrap();
    assert!(gen_1_14.starts_with("And God said, Let there be lights in the firmament"));
    assert!(gen_1_14.ends_with("and for days, and years:"));

    let gen_1_15 = ffi::lookup_reference("Genesis 1:15").unwrap();
    assert_eq!(
        gen_1_15,
        "And let them be for lights in the firmament of the heaven to give light upon the earth: and it was so."
    );

    // Verse spanning across blank line ("Selah." / "Even so, come, Lord Jesus.")
    let ps_3_2 = ffi::lookup_reference("Psalms 3:2").unwrap();
    assert_eq!(
        ps_3_2,
        "Many there be which say of my soul, There is no help for him in God. Selah."
    );

    let rev_22_20 = ffi::lookup_reference("Revelation 22:20").unwrap();
    assert_eq!(
        rev_22_20,
        "He which testifieth these things saith, Surely I come quickly. Amen. Even so, come, Lord Jesus."
    );

    // 1 Kings vs 2 Kings disambiguation
    let kings1 = ffi::lookup_reference("1 Kings 3:9").unwrap();
    assert!(kings1.contains("Give therefore thy servant an understanding heart"));
    let kings2 = ffi::lookup_reference("2 Kings 6:5").unwrap();
    assert_eq!(
        kings2,
        "But as one was felling a beam, the axe head fell into the water: and he cried, and said, Alas, master! for it was borrowed."
    );

    // Last verse of Old Testament (Malachi 4:6) & New Testament (Revelation 22:21)
    // Must not contain any Project Gutenberg headers/footers
    let mal_4_6 = ffi::lookup_reference("Malachi 4:6").unwrap();
    assert_eq!(
        mal_4_6,
        "And he shall turn the heart of the fathers to the children, and the heart of the children to their fathers, lest I come and smite the earth with a curse."
    );

    let rev_22_21 = ffi::lookup_reference("Revelation 22:21").unwrap();
    assert_eq!(
        rev_22_21,
        "The grace of our Lord Jesus Christ be with you all. Amen."
    );
}

#[test]
fn test_contiguous_verse_range_and_aliases() {
    let _lock = TEST_MUTEX.lock().unwrap_or_else(|e| e.into_inner());
    setup_full_bible();

    let blessing = ffi::lookup_reference("Numbers 6:24-26").unwrap();
    assert_eq!(
        blessing,
        "The LORD bless thee, and keep thee: \
         The LORD make his face shine upon thee, and be gracious unto thee: \
         The LORD lift up his countenance upon thee, and give thee peace."
    );

    let job_range = ffi::lookup_reference("Job 14:1-2").unwrap();
    assert_eq!(
        job_range,
        "Man that is born of a woman is of few days and full of trouble. \
         He cometh forth like a flower, and is cut down: he fleeth also as a shadow, and continueth not."
    );

    // Book name aliases (Psalm -> Psalms, Roman numerals II Kings -> 2 Kings, Apocalypse -> Revelation)
    let ps_23_1 = ffi::lookup_reference("Psalm 23:1").unwrap();
    assert_eq!(ps_23_1, "The LORD is my shepherd; I shall not want.");

    let ii_kings = ffi::lookup_reference("II Kings 6:5").unwrap();
    assert!(ii_kings.contains("Alas, master! for it was borrowed."));

    let apoc = ffi::lookup_reference("Apocalypse 22:21").unwrap();
    assert_eq!(
        apoc,
        "The grace of our Lord Jesus Christ be with you all. Amen."
    );
}

#[test]
fn test_bm25_fuzzy_search_and_synonym_expansion() {
    let _lock = TEST_MUTEX.lock().unwrap_or_else(|e| e.into_inner());
    setup_full_bible();

    // 1. "borrow" + "mutable" -> expands to borrower, lender, masters, double, etc.
    let (ref1, txt1) =
        ffi::search_keywords("cannot borrow x as mutable more than once").unwrap();
    assert!(
        ref1 == "Proverbs 22:7" || ref1 == "Matthew 6:24" || ref1 == "James 1:8",
        "Unexpected top BM25 match for mutable borrow: {} -> {}",
        ref1,
        txt1
    );
    assert_eq!(ffi::lookup_reference(&ref1).unwrap(), txt1);

    // 2. "trait" + "satisfied" -> weighed in the balances and found wanting (Daniel 5:27)
    let (ref2, txt2) =
        ffi::search_keywords("the trait bound Foo is not satisfied").unwrap();
    assert_eq!(ref2, "Daniel 5:27");
    assert_eq!(
        txt2,
        "TEKEL; Thou art weighed in the balances, and art found wanting."
    );

    // 3. "unused" -> buried talent / idle servant
    let (ref3, txt3) = ffi::search_keywords("unused variable is never read").unwrap();
    assert!(
        txt3.to_lowercase().contains("talent") || txt3.to_lowercase().contains("idle"),
        "Expected talent/idle verse, got {} -> {}",
        ref3,
        txt3
    );
    assert_eq!(ffi::lookup_reference(&ref3).unwrap(), txt3);

    // 4. "unsafe" -> fire in bosom / breaking a hedge (serpent bites)
    let (ref4, txt4) =
        ffi::search_keywords("call to unsafe function requires unsafe block").unwrap();
    assert!(
        ref4 == "Ecclesiastes 10:8" || ref4 == "Proverbs 6:27",
        "Expected Ecclesiastes 10:8 or Proverbs 6:27, got {} -> {}",
        ref4,
        txt4
    );
    assert_eq!(ffi::lookup_reference(&ref4).unwrap(), txt4);
}

#[test]
fn test_weighted_random_top_k_sampling_variety_and_authenticity() {
    let _lock = TEST_MUTEX.lock().unwrap_or_else(|e| e.into_inner());
    setup_full_bible();

    // Seed PRNG in non-deterministic mode and run 30 times on the same E0499 error.
    // Should produce multiple distinct verses from the top BM25 candidates, and every
    // single quotation must be 100% verbatim from Bible.TXT.
    ffi::set_seed(0);

    let mut seen_refs = HashSet::new();
    for i in 1..=30 {
        // Advance with distinct non-deterministic state
        let payload = DiagnosticPayload {
            level: "error".to_string(),
            code: Some("E0499".to_string()),
            location: Some(format!("src/main.rs:{}:5", i)),
            message: "cannot borrow `x` as mutable more than once at a time".to_string(),
            notes: None,
            use_color: false,
            deterministic: false,
        };
        let out = ffi::judge_diagnostic(&payload).unwrap();
        assert!(out.contains("✝ THE LORD HAS SPOKEN"));
        assert!(out.contains("VERDICT: GUILTY"));

        // Extract reference before " (KJV)"
        let kjv_line = out
            .lines()
            .find(|l| l.contains("(KJV)"))
            .expect("Output must contain (KJV) reference line");
        let r = kjv_line.trim().trim_end_matches("(KJV)").trim().to_string();

        // Extract quoted scripture after SCRIPTURE:
        let scrip_idx = out.find("SCRIPTURE:\n\"").expect("Must have SCRIPTURE block");
        let after_scrip = &out[scrip_idx + "SCRIPTURE:\n\"".len()..];
        let end_quote = after_scrip.find("\"\n").expect("Must end quote");
        let quoted_verse = &after_scrip[..end_quote];

        // Verify quoted verse is 100% verbatim from Bible.TXT
        let expected_verbatim = ffi::lookup_reference(&r)
            .unwrap_or_else(|_| panic!("Referenced verse '{}' must exist in Bible.TXT", r));
        assert_eq!(
            quoted_verse, expected_verbatim,
            "Scripture quotation for {} must match KJV Bible.TXT verbatim",
            r
        );

        seen_refs.insert(r);
    }

    assert!(
        seen_refs.len() >= 2,
        "Weighted random Top-K sampling should select multiple distinct verses across runs, got {:?}",
        seen_refs
    );
}

#[test]
fn test_revelation_apocalypse_fallback_for_unmatched_errors() {
    let _lock = TEST_MUTEX.lock().unwrap_or_else(|e| e.into_inner());
    setup_full_bible();
    ffi::set_seed(0);

    let mut rev_refs = HashSet::new();
    for _ in 0..15 {
        let payload = DiagnosticPayload {
            level: "error".to_string(),
            code: Some("E9999".to_string()),
            location: Some("src/abomination.rs:666:13".to_string()),
            message: "xyzzy_quux_blarg_plugh_zorkmid".to_string(),
            notes: None,
            use_color: false,
            deterministic: false,
        };
        let out = ffi::judge_diagnostic(&payload).unwrap();
        assert!(
            out.contains("THE BOOK OF REVELATION"),
            "Unmatched diagnostic should fall back to THE BOOK OF REVELATION, got:\n{}",
            out
        );

        let kjv_line = out
            .lines()
            .find(|l| l.contains("(KJV)"))
            .expect("Must contain (KJV) reference");
        let r = kjv_line.trim().trim_end_matches("(KJV)").trim().to_string();
        assert!(
            r.starts_with("Revelation "),
            "Fallback reference must be from Revelation, got {}",
            r
        );

        // Verify verbatim text
        let scrip_idx = out.find("SCRIPTURE:\n\"").unwrap();
        let after_scrip = &out[scrip_idx + "SCRIPTURE:\n\"".len()..];
        let end_quote = after_scrip.find("\"\n").unwrap();
        let quoted = &after_scrip[..end_quote];
        assert_eq!(quoted, ffi::lookup_reference(&r).unwrap());

        rev_refs.insert(r);
    }

    assert!(
        rev_refs.len() >= 3,
        "Revelation fallback should pick random verses from Revelation, got {:?}",
        rev_refs
    );
}

#[test]
fn test_all_diagnostic_categories_and_deterministic_mode() {
    let _lock = TEST_MUTEX.lock().unwrap_or_else(|e| e.into_inner());
    setup_full_bible();

    let cases = [
        (
            "E0499",
            "cannot borrow `value` as mutable more than once at a time",
            "THE BOOK OF BORROWINGS",
            "THE SECOND BORROW",
        ),
        (
            "E0382",
            "use of moved value: `x`",
            "THE BOOK OF POSSESSIONS",
            "TAKING WHAT NO LONGER BELONGETH TO THEE",
        ),
        (
            "E0502",
            "cannot borrow `x` as mutable because it is also borrowed as immutable",
            "THE BOOK OF BORROWINGS",
            "FORBIDDEN POSSESSION",
        ),
        (
            "E0597",
            "`x` does not live long enough",
            "THE BOOK OF ETERNITY",
            "MORTALITY OF THE BORROWED",
        ),
        (
            "E0308",
            "mismatched types: expected `i32`, found `&str`",
            "THE BOOK OF KINDS",
            "FALSE IDENTITY AND CONFUSION OF KIND",
        ),
        (
            "E0277",
            "the trait bound `MyStruct: Display` is not satisfied",
            "THE BOOK OF WORTHINESS",
            "UNWORTHINESS OF THE VESSEL",
        ),
        (
            "E0425",
            "cannot find value `mystery` in this scope",
            "THE BOOK OF THE LOST",
            "INVOKING THE UNKNOWN",
        ),
        (
            "unused_variables",
            "unused variable: `talent`",
            "THE BOOK OF STEWARDSHIP",
            "THE BURIED TALENT AND IDLE SERVANT",
        ),
        (
            "E0133",
            "call to unsafe function `transmute` is unsafe and requires unsafe function or block",
            "THE BOOK OF TRANSGRESSIONS",
            "STEPPING BEYOND THE SANCTUARY HEDGE",
        ),
        (
            "E0061",
            "this function takes 2 arguments but 3 arguments were supplied",
            "THE BOOK OF TEMPERANCE",
            "GLUTTONY AND EXCESS OF ARGUMENTS",
        ),
        (
            "E0381",
            "used binding `forbidden_knowledge` isn't initialized",
            "THE BOOK OF GENESIS",
            "ORIGINAL SIN OF UNINITIALIZED KNOWLEDGE",
        ),
    ];

    for (code, msg, expected_book, expected_sin) in &cases {
        let level = if *code == "unused_variables" {
            "warning"
        } else {
            "error"
        };
        let payload = DiagnosticPayload {
            level: level.to_string(),
            code: Some(code.to_string()),
            location: Some("src/lib.rs:10:5".to_string()),
            message: msg.to_string(),
            notes: Some("first occurred here".to_string()),
            use_color: false,
            deterministic: true,
        };

        let j1 = ffi::judge_diagnostic(&payload).unwrap();
        let j2 = ffi::judge_diagnostic(&payload).unwrap();
        assert_eq!(
            j1, j2,
            "Deterministic mode must produce identical output for {}",
            code
        );
        assert!(
            j1.contains(expected_book),
            "Expected '{}' in judgment for {}, got:\n{}",
            expected_book,
            code,
            j1
        );
        assert!(
            j1.contains(expected_sin),
            "Expected '{}' in judgment for {}, got:\n{}",
            expected_sin,
            code,
            j1
        );
        assert!(j1.contains("src/lib.rs:10:5"));
    }

    // Also verify Absolution verdict
    let abs = ffi::absolve(false).unwrap();
    assert!(abs.contains("✝ VERDICT: ABSOLVED"));
    assert!(abs.contains("Numbers 6:24-26 (KJV)"));
    assert!(abs.contains("The LORD bless thee, and keep thee:"));
}

#[test]
fn test_templeos_arc_compress_dot_z_decompression_in_holyc() {
    let _lock = TEST_MUTEX.lock().unwrap_or_else(|e| e.into_inner());

    // Create a minimal TempleOS CArcCompress (CT_NONE = 1) .TXT.Z archive in /tmp
    let sample_bible = b"The First Book of Moses:  Called Genesis\n\n\
1:1 In the beginning God created the heaven and the earth.\n\
1:2 And the earth was without form, and void.\n";
    let expanded_size = sample_bible.len() as i64;
    let compressed_size = 17 + expanded_size;

    let mut z_bytes = Vec::with_capacity(compressed_size as usize);
    z_bytes.extend_from_slice(&compressed_size.to_le_bytes());
    z_bytes.extend_from_slice(&expanded_size.to_le_bytes());
    z_bytes.push(1u8); // CT_NONE = 1
    z_bytes.extend_from_slice(sample_bible);

    let tmp_z_path = PathBuf::from("/tmp/test_templeos_bible.TXT.Z");
    fs::write(&tmp_z_path, &z_bytes).unwrap();

    ffi::init(&tmp_z_path).expect("HolyC should decompress and parse .TXT.Z file");
    assert_eq!(ffi::book_count(), 1);
    assert_eq!(ffi::verse_count(), 2);
    assert_eq!(
        ffi::lookup_reference("Genesis 1:1").unwrap(),
        "In the beginning God created the heaven and the earth."
    );

    let _ = fs::remove_file(&tmp_z_path);
    // Re-init full Bible for subsequent tests
    setup_full_bible();
}

#[test]
fn test_cargo_json_stream_and_subcommand_cli() {
    let _lock = TEST_MUTEX.lock().unwrap_or_else(|e| e.into_inner());
    setup_full_bible();

    // Test CLI argument parsing for `cargo absolve check --release`
    let cfg = parse_cli_args(["cargo-absolve", "absolve", "--no-color", "--deterministic", "check", "--release"]);
    assert_eq!(cfg.cargo_subcommand, "check");
    assert!(!cfg.use_color);
    assert!(cfg.deterministic);
    assert_eq!(cfg.cargo_args, vec!["--release"]);

    // Test streaming a mixture of non-JSON build script output and two compiler-message JSON events
    let simulated_stream = r#"Compiling sinner v0.1.0 (/tmp/sinner)
{"reason":"compiler-message","package_id":"sinner 0.1.0","manifest_path":"/tmp/sinner/Cargo.toml","target":{"kind":["bin"],"crate_types":["bin"],"name":"sinner","src_path":"/tmp/sinner/src/main.rs","edition":"2021","doc":true,"doctest":false,"test":true},"message":{"rendered":"error[E0499]: cannot borrow `x` as mutable more than once at a time","children":[],"code":{"code":"E0499","explanation":null},"level":"error","message":"cannot borrow `x` as mutable more than once at a time","spans":[{"byte_end":50,"byte_start":40,"column_end":15,"column_start":5,"expansion":null,"file_name":"src/main.rs","is_primary":true,"label":"second mutable borrow occurs here","line_end":12,"line_start":12,"suggested_replacement":null,"suggestion_applicability":null,"text":[]}]}}
{"reason":"compiler-message","package_id":"sinner 0.1.0","manifest_path":"/tmp/sinner/Cargo.toml","target":{"kind":["bin"],"crate_types":["bin"],"name":"sinner","src_path":"/tmp/sinner/src/main.rs","edition":"2021","doc":true,"doctest":false,"test":true},"message":{"rendered":"error: aborting due to 1 previous error","children":[],"code":null,"level":"error","message":"aborting due to 1 previous error","spans":[]}}
"#;

    let reader = Cursor::new(simulated_stream.as_bytes());
    let mut output_buf = Vec::new();
    let (errors, warnings) =
        process_cargo_stream(reader, &mut output_buf, false, true).unwrap();
    assert_eq!(errors, 1);
    assert_eq!(warnings, 0);

    let rendered = String::from_utf8(output_buf).unwrap();
    assert!(rendered.contains("Compiling sinner v0.1.0"));
    assert!(rendered.contains("error[E0499]: cannot borrow `x` as mutable more than once at a time"));
    assert!(rendered.contains("THE BOOK OF BORROWINGS"));
    assert!(rendered.contains("src/main.rs:12:5"));
    assert!(rendered.contains("VERDICT: GUILTY"));
}

#[test]
fn test_end_to_end_binary_exit_codes() {
    let bin_path = env!("CARGO_BIN_EXE_cargo-absolve");

    // Create a temporary broken Rust crate in /tmp and run `cargo-absolve check` on it
    let tmp_dir = PathBuf::from("/tmp/cargo_absolve_e2e_sinner");
    let _ = fs::remove_dir_all(&tmp_dir);
    fs::create_dir_all(tmp_dir.join("src")).unwrap();

    fs::write(
        tmp_dir.join("Cargo.toml"),
        "[package]\nname = \"sinner\"\nversion = \"0.1.0\"\nedition = \"2021\"\n",
    )
    .unwrap();

    fs::write(
        tmp_dir.join("src/main.rs"),
        "fn main() {\n    let mut x = String::from(\"hello\");\n    let r1 = &mut x;\n    let r2 = &mut x;\n    println!(\"{} {}\", r1, r2);\n}\n",
    )
    .unwrap();

    let output = Command::new(bin_path)
        .current_dir(&tmp_dir)
        .args(["absolve", "--no-color", "check"])
        .output()
        .expect("Failed to run cargo-absolve binary");

    assert!(
        !output.status.success(),
        "cargo-absolve check must propagate non-zero exit code on broken Rust code"
    );
    let stdout = String::from_utf8_lossy(&output.stdout);
    assert!(stdout.contains("THE LORD HAS SPOKEN"));
    assert!(stdout.contains("E0499"));
    assert!(stdout.contains("VERDICT: GUILTY"));

    // Now fix the code and verify exit code 0 + ABSOLVED verdict
    fs::write(
        tmp_dir.join("src/main.rs"),
        "fn main() {\n    let x = 42;\n    println!(\"{}\", x);\n}\n",
    )
    .unwrap();

    let ok_output = Command::new(bin_path)
        .current_dir(&tmp_dir)
        .args(["absolve", "--no-color", "check"])
        .output()
        .expect("Failed to run cargo-absolve binary on clean crate");

    assert!(
        ok_output.status.success(),
        "cargo-absolve check must exit with 0 on valid Rust code"
    );
    let ok_stdout = String::from_utf8_lossy(&ok_output.stdout);
    assert!(ok_stdout.contains("VERDICT: ABSOLVED"));
    assert!(ok_stdout.contains("Numbers 6:24-26 (KJV)"));

    let _ = fs::remove_dir_all(&tmp_dir);
}

#[test]
fn test_seven_deadly_sins_examples() {
    let manifest_dir = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let expected_files = [
        "greed.rs",
        "pride.rs",
        "wrath.rs",
        "envy.rs",
        "lust.rs",
        "gluttony.rs",
        "sloth.rs",
        "original_sin.rs",
    ];
    for file in &expected_files {
        let p = manifest_dir.join("examples/seven-deadly-sins").join(file);
        assert!(p.is_file(), "Missing example file: {}", p.display());
    }

    let bin_path = env!("CARGO_BIN_EXE_cargo-absolve");

    // Verify `cargo absolve check --example greed` fails with E0499 & VERDICT: GUILTY
    let greed_out = Command::new(bin_path)
        .current_dir(&manifest_dir)
        .args(["absolve", "--no-color", "check", "--example", "greed", "--offline"])
        .output()
        .expect("Failed to run cargo-absolve on greed example");
    assert!(!greed_out.status.success());
    let greed_stdout = String::from_utf8_lossy(&greed_out.stdout);
    assert!(greed_stdout.contains("E0499"));
    assert!(greed_stdout.contains("VERDICT: GUILTY"));

    // Verify `cargo absolve check --example sloth` succeeds with exit 0 & ADMONISHED warning
    let sloth_out = Command::new(bin_path)
        .current_dir(&manifest_dir)
        .args(["absolve", "--no-color", "check", "--example", "sloth", "--offline"])
        .output()
        .expect("Failed to run cargo-absolve on sloth example");
    assert!(sloth_out.status.success());
    let sloth_stdout = String::from_utf8_lossy(&sloth_out.stdout);
    assert!(sloth_stdout.contains("ADMONISHED"));
    assert!(!sloth_stdout.contains("VERDICT: ABSOLVED"));
}
