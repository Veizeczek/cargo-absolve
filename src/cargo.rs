use crate::ffi::{self, DiagnosticPayload};
use cargo_metadata::diagnostic::{Diagnostic, DiagnosticLevel};
use cargo_metadata::Message;
use std::env;
use std::io::{self, BufRead, BufReader, IsTerminal, Write};
use std::path::PathBuf;
use std::process::{Command, Stdio};

#[derive(Debug, Clone)]
pub struct AbsolveConfig {
    pub cargo_subcommand: String,
    pub cargo_args: Vec<String>,
    pub bible_path: Option<PathBuf>,
    pub use_color: bool,
    pub deterministic: bool,
    pub seed: Option<u64>,
    pub show_help: bool,
    pub show_version: bool,
}

impl Default for AbsolveConfig {
    fn default() -> Self {
        let use_color = env::var_os("NO_COLOR").is_none() && io::stdout().is_terminal();
        Self {
            cargo_subcommand: "check".to_string(),
            cargo_args: Vec::new(),
            bible_path: None,
            use_color,
            deterministic: false,
            seed: None,
            show_help: false,
            show_version: false,
        }
    }
}

pub fn parse_cli_args<I, S>(args: I) -> AbsolveConfig
where
    I: IntoIterator<Item = S>,
    S: Into<String>,
{
    let mut raw: Vec<String> = args.into_iter().map(Into::into).collect();
    if !raw.is_empty() {
        raw.remove(0); // binary name
    }
    if raw.first().map(|s| s.as_str()) == Some("absolve") {
        raw.remove(0); // invoked as `cargo absolve ...`
    }

    let mut cfg = AbsolveConfig::default();
    let mut subcmd_set = false;
    let mut i = 0;

    while i < raw.len() {
        let arg = &raw[i];
        match arg.as_str() {
            "-h" | "--help" if !subcmd_set => {
                cfg.show_help = true;
                i += 1;
            }
            "-V" | "--version" if !subcmd_set => {
                cfg.show_version = true;
                i += 1;
            }
            "--no-color" => {
                cfg.use_color = false;
                i += 1;
            }
            "--color" => {
                if let Some(mode) = raw.get(i + 1) {
                    match mode.as_str() {
                        "always" => cfg.use_color = true,
                        "never" => cfg.use_color = false,
                        _ => {}
                    }
                    i += 2;
                } else {
                    i += 1;
                }
            }
            s if s.starts_with("--color=") => {
                let mode = &s["--color=".len()..];
                match mode {
                    "always" => cfg.use_color = true,
                    "never" => cfg.use_color = false,
                    _ => {}
                }
                i += 1;
            }
            "--deterministic" => {
                cfg.deterministic = true;
                i += 1;
            }
            "--seed" => {
                if let Some(val) = raw.get(i + 1) {
                    if let Ok(s) = val.parse::<u64>() {
                        cfg.seed = Some(s);
                    }
                    i += 2;
                } else {
                    i += 1;
                }
            }
            "--bible" => {
                if let Some(p) = raw.get(i + 1) {
                    cfg.bible_path = Some(PathBuf::from(p));
                    i += 2;
                } else {
                    i += 1;
                }
            }
            s if s.starts_with("--bible=") => {
                let p = &s["--bible=".len()..];
                cfg.bible_path = Some(PathBuf::from(p));
                i += 1;
            }
            _ => {
                if !subcmd_set && !arg.starts_with('-') {
                    cfg.cargo_subcommand = arg.clone();
                    subcmd_set = true;
                } else {
                    cfg.cargo_args.push(arg.clone());
                }
                i += 1;
            }
        }
    }

    cfg
}

/// Returns `true` if a compiler diagnostic is a summary/noise note rather than an actual sin.
pub fn is_summary_noise(diag: &Diagnostic) -> bool {
    match diag.level {
        DiagnosticLevel::Error | DiagnosticLevel::Ice | DiagnosticLevel::Warning => {}
        _ => return true,
    }
    let msg = diag.message.trim();
    if msg.starts_with("aborting due to ")
        || msg.starts_with("For more information about this error")
        || msg.ends_with("warning emitted")
        || msg.ends_with("warnings emitted")
    {
        return true;
    }
    false
}

/// Convert a `cargo_metadata::diagnostic::Diagnostic` into a `DiagnosticPayload` for HolyC.
pub fn diagnostic_to_payload(
    diag: &Diagnostic,
    use_color: bool,
    deterministic: bool,
) -> Option<DiagnosticPayload> {
    if is_summary_noise(diag) {
        return None;
    }

    let level = match diag.level {
        DiagnosticLevel::Error | DiagnosticLevel::Ice => "error".to_string(),
        DiagnosticLevel::Warning => "warning".to_string(),
        _ => return None,
    };

    let code = diag.code.as_ref().map(|c| c.code.clone());

    let primary_span = diag
        .spans
        .iter()
        .find(|s| s.is_primary)
        .or_else(|| diag.spans.first());

    let location = primary_span.map(|s| {
        format!("{}:{}:{}", s.file_name, s.line_start, s.column_start)
    });

    let mut notes_parts = Vec::new();
    for span in &diag.spans {
        if let Some(ref label) = span.label {
            let trimmed = label.trim();
            if !trimmed.is_empty() {
                notes_parts.push(format!(
                    "{}:{}: {}",
                    span.file_name, span.line_start, trimmed
                ));
            }
        }
    }
    for child in &diag.children {
        let cmsg = child.message.trim();
        if !cmsg.is_empty() && !cmsg.starts_with("for more information") {
            if let Some(span) = child.spans.first() {
                if let Some(ref repl) = span.suggested_replacement {
                    notes_parts.push(format!("{}: `{}`", cmsg, repl.trim()));
                    continue;
                }
            }
            notes_parts.push(cmsg.to_string());
        }
    }

    let notes = if notes_parts.is_empty() {
        None
    } else {
        Some(notes_parts.join(" | "))
    };

    Some(DiagnosticPayload {
        level,
        code,
        location,
        message: diag.message.clone(),
        notes,
        use_color,
        deterministic,
    })
}

/// Process a stream of Cargo stdout lines (JSON `compiler-message` events and plain text lines),
/// invoking the HolyC engine for every compiler diagnostic.
/// Returns `(errors_seen, warnings_seen)`.
pub fn process_cargo_stream<R: BufRead, W: Write>(
    reader: R,
    mut out: W,
    use_color: bool,
    deterministic: bool,
) -> io::Result<(usize, usize)> {
    let mut errors_seen = 0usize;
    let mut warnings_seen = 0usize;

    for line_res in reader.lines() {
        let line = line_res?;
        let trimmed = line.trim();
        if trimmed.is_empty() {
            continue;
        }

        if trimmed.starts_with('{') {
            match serde_json::from_str::<Message>(trimmed) {
                Ok(Message::CompilerMessage(cmsg)) => {
                    if let Some(payload) =
                        diagnostic_to_payload(&cmsg.message, use_color, deterministic)
                    {
                        if payload.level == "error" {
                            errors_seen += 1;
                        } else {
                            warnings_seen += 1;
                        }
                        if let Ok(judgment) = ffi::judge_diagnostic(&payload) {
                            writeln!(out, "{}", judgment)?;
                            out.flush()?;
                        }
                    }
                }
                Ok(Message::BuildScriptExecuted(_))
                | Ok(Message::CompilerArtifact(_))
                | Ok(Message::BuildFinished(_)) => {}
                Ok(Message::TextLine(txt)) => {
                    writeln!(out, "{}", txt)?;
                    out.flush()?;
                }
                Ok(_) => {}
                Err(_) => {
                    // Non-cargo_metadata JSON line (e.g. from test/build output); forward as-is
                    writeln!(out, "{}", line)?;
                    out.flush()?;
                }
            }
        } else {
            writeln!(out, "{}", line)?;
            out.flush()?;
        }
    }

    Ok((errors_seen, warnings_seen))
}

fn find_target_manifest(cargo_args: &[String]) -> Option<PathBuf> {
    let mut i = 0;
    while i < cargo_args.len() {
        if cargo_args[i] == "--manifest-path" {
            if let Some(p) = cargo_args.get(i + 1) {
                return Some(PathBuf::from(p));
            }
        } else if let Some(rest) = cargo_args[i].strip_prefix("--manifest-path=") {
            return Some(PathBuf::from(rest));
        }
        i += 1;
    }

    let mut dir = env::current_dir().ok()?;
    loop {
        let candidate = dir.join("Cargo.toml");
        if candidate.is_file() {
            return Some(candidate);
        }
        if !dir.pop() {
            break;
        }
    }
    None
}

fn should_auto_enable_deadly_sins(cargo_args: &[String]) -> bool {
    let requests_example = cargo_args.iter().any(|a| {
        a == "--example"
            || a == "--examples"
            || a.starts_with("--example=")
    });
    if !requests_example {
        return false;
    }

    let already_has_feature = cargo_args
        .iter()
        .any(|a| a == "--all-features" || a.contains("deadly-sins"));
    if already_has_feature {
        return false;
    }

    if let Some(manifest_path) = find_target_manifest(cargo_args) {
        if let Ok(contents) = std::fs::read_to_string(manifest_path) {
            return contents.contains("deadly-sins");
        }
    }
    false
}

pub fn run_cargo_and_absolve(cfg: &AbsolveConfig) -> Result<i32, String> {
    let bible_path = ffi::resolve_bible_path(cfg.bible_path.as_deref())?;
    ffi::init(&bible_path)?;

    if let Some(seed) = cfg.seed {
        ffi::set_seed(seed);
    } else if cfg.deterministic {
        ffi::set_seed(1);
    } else {
        ffi::set_seed(0);
    }

    let cargo_bin = env::var("CARGO").unwrap_or_else(|_| "cargo".to_string());
    let mut cmd = Command::new(cargo_bin);
    cmd.arg(&cfg.cargo_subcommand);

    let has_msg_fmt = cfg
        .cargo_args
        .iter()
        .any(|a| a.starts_with("--message-format"));
    if !has_msg_fmt {
        cmd.arg("--message-format=json");
    }

    if should_auto_enable_deadly_sins(&cfg.cargo_args) {
        cmd.args(["--features", "deadly-sins"]);
    }

    cmd.args(&cfg.cargo_args);
    cmd.stdout(Stdio::piped());
    cmd.stderr(Stdio::inherit());

    let mut child = cmd
        .spawn()
        .map_err(|e| format!("Failed to spawn cargo {}: {}", cfg.cargo_subcommand, e))?;

    let stdout = child
        .stdout
        .take()
        .ok_or_else(|| "Failed to capture cargo stdout".to_string())?;

    let reader = BufReader::new(stdout);
    let mut out_handle = io::stdout();
    let (errors_seen, warnings_seen) =
        process_cargo_stream(reader, &mut out_handle, cfg.use_color, cfg.deterministic)
            .map_err(|e| format!("Error reading cargo output stream: {}", e))?;

    let status = child
        .wait()
        .map_err(|e| format!("Failed to wait on cargo process: {}", e))?;

    let exit_code = status.code().unwrap_or(1);

    if exit_code == 0 && errors_seen == 0 && warnings_seen == 0 {
        if let Ok(absolution) = ffi::absolve(cfg.use_color) {
            let _ = writeln!(out_handle, "{}", absolution);
            let _ = out_handle.flush();
        }
    }

    ffi::shutdown();
    Ok(exit_code)
}

pub fn print_help() {
    println!(
        "\
cargo-absolve — Rust × HolyC × TempleOS Biblical Compiler Judgments

USAGE:
    cargo absolve [OPTIONS] [SUBCOMMAND] [CARGO_ARGS...]

SUBCOMMANDS:
    check       Examine the current package and pronounce biblical judgment (default)
    build       Compile the current package under the gaze of the HolyC Judge
    clippy      Judge lints and transgressions via Clippy
    test        Build and execute tests with biblical diagnostics

OPTIONS:
    --bible <PATH>       Path to TempleOS Bible.TXT or Bible.TXT.Z
    --color <WHEN>       Coloring: auto, always, never
    --no-color           Disable ANSI colors
    --deterministic      Always choose the #1 BM25 verse instead of weighted Top-K sampling
    --seed <U64>         Seed the HolyC weighted-random verse sampler
    -h, --help           Print help information
    -V, --version        Print version information"
    );
}

pub fn cli_main() -> i32 {
    let cfg = parse_cli_args(env::args());
    if cfg.show_help {
        print_help();
        return 0;
    }
    if cfg.show_version {
        println!("cargo-absolve {}", env!("CARGO_PKG_VERSION"));
        return 0;
    }

    match run_cargo_and_absolve(&cfg) {
        Ok(code) => code,
        Err(e) => {
            eprintln!("cargo-absolve error: {}", e);
            1
        }
    }
}

