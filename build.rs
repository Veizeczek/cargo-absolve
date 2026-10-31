use std::env;
use std::path::{Path, PathBuf};
use std::process::Command;

fn find_hcc_and_prefix() -> (PathBuf, PathBuf) {
    let mut candidates = Vec::new();
    if let Ok(hcc_env) = env::var("HCC") {
        candidates.push(PathBuf::from(hcc_env));
    }
    if let Ok(home) = env::var("HOME") {
        candidates.push(PathBuf::from(&home).join(".cargo/bin/hcc"));
        candidates.push(PathBuf::from(&home).join(".local/bin/hcc"));
    }
    candidates.push(PathBuf::from("/usr/local/bin/hcc"));
    candidates.push(PathBuf::from("/usr/bin/hcc"));

    if let Ok(path_var) = env::var("PATH") {
        for dir in env::split_paths(&path_var) {
            candidates.push(dir.join("hcc"));
        }
    }

    let hcc_bin = candidates
        .into_iter()
        .find(|p| p.is_file())
        .unwrap_or_else(|| PathBuf::from("hcc"));

    let mut prefix_candidates = Vec::new();
    if let Ok(prefix_env) = env::var("HCC_INSTALL_DIR") {
        prefix_candidates.push(PathBuf::from(prefix_env));
    }
    if let Some(bin_dir) = hcc_bin.parent() {
        if let Some(prefix) = bin_dir.parent() {
            prefix_candidates.push(prefix.to_path_buf());
        }
    }
    if let Ok(home) = env::var("HOME") {
        prefix_candidates.push(PathBuf::from(&home).join(".cargo"));
        prefix_candidates.push(PathBuf::from(&home).join(".local"));
    }
    prefix_candidates.push(PathBuf::from("/usr/local"));
    prefix_candidates.push(PathBuf::from("/usr"));

    let prefix = prefix_candidates
        .into_iter()
        .find(|p| p.join("include/tos.HH").is_file() && p.join("lib/libtos.a").is_file())
        .expect(
            "Failed to locate HolyC runtime prefix containing include/tos.HH and lib/libtos.a. \
             Set HCC_INSTALL_DIR or install Jamesbarford/holyc-lang into ~/.cargo or /usr/local.",
        );

    (hcc_bin, prefix)
}

fn run_checked(cmd: &mut Command, step: &str) {
    let output = cmd
        .output()
        .unwrap_or_else(|e| panic!("Failed to execute {} ({:?}): {}", step, cmd, e));
    if !output.status.success() {
        let stdout = String::from_utf8_lossy(&output.stdout);
        let stderr = String::from_utf8_lossy(&output.stderr);
        panic!(
            "{} failed with status {}:\nCommand: {:?}\nStdout:\n{}\nStderr:\n{}",
            step, output.status, cmd, stdout, stderr
        );
    }
}

fn main() {
    let manifest_dir = PathBuf::from(env::var("CARGO_MANIFEST_DIR").unwrap());
    let out_dir = PathBuf::from(env::var("OUT_DIR").unwrap());

    let holyc_files = [
        "holyc/Bible.HC",
        "holyc/Scripture.HC",
        "holyc/Judgment.HC",
        "holyc/FFI.HC",
    ];
    for file in &holyc_files {
        println!("cargo:rerun-if-changed={}", file);
    }
    println!("cargo:rerun-if-changed=build.rs");
    println!("cargo:rerun-if-env-changed=HCC");
    println!("cargo:rerun-if-env-changed=HCC_INSTALL_DIR");

    let default_bible = manifest_dir.join("assets/Bible.TXT");
    println!(
        "cargo:rustc-env=CARGO_ABSOLVE_DEFAULT_BIBLE={}",
        default_bible.display()
    );

    let (hcc_bin, prefix) = find_hcc_and_prefix();
    let ffi_hc = manifest_dir.join("holyc/FFI.HC");
    let asm_path = out_dir.join("holyc_engine.s");
    let obj_path = out_dir.join("holyc_engine.o");
    let lib_path = out_dir.join("libholyc_engine.a");

    let install_dir_arg = format!("--install-dir={}", prefix.display());
    let mut hcc_cmd = Command::new(&hcc_bin);
    hcc_cmd
        .current_dir(&manifest_dir)
        .arg(&install_dir_arg)
        .arg("-fPIC")
        .arg("-S")
        .arg("-o")
        .arg(&asm_path)
        .arg(&ffi_hc);
    run_checked(&mut hcc_cmd, "HolyC compilation (hcc)");

    let cc_bin = env::var("CC").unwrap_or_else(|_| "cc".to_string());
    let mut cc_cmd = Command::new(&cc_bin);
    cc_cmd
        .arg("-c")
        .arg("-fPIC")
        .arg(&asm_path)
        .arg("-o")
        .arg(&obj_path);
    run_checked(&mut cc_cmd, "Assembler (cc -c)");

    if lib_path.exists() {
        let _ = std::fs::remove_file(&lib_path);
    }
    let ar_bin = env::var("AR").unwrap_or_else(|_| "ar".to_string());
    let mut ar_cmd = Command::new(&ar_bin);
    ar_cmd.arg("rcs").arg(&lib_path).arg(&obj_path);
    run_checked(&mut ar_cmd, "Static archive creation (ar)");

    println!("cargo:rustc-link-search=native={}", out_dir.display());
    println!(
        "cargo:rustc-link-search=native={}",
        Path::new(&prefix).join("lib").display()
    );
    println!("cargo:rustc-link-lib=static=holyc_engine");
    println!("cargo:rustc-link-lib=static=tos");
    println!("cargo:rustc-link-lib=m");
    println!("cargo:rustc-link-lib=pthread");
    println!("cargo:rustc-link-lib=c");
}

