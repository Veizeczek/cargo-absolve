# ✝ CARGO ABSOLVE ✝

### THE HOLY BORROW CHECKER

*In Rust We Trust. In HolyC We Pray.*

> **The compiler giveth, and the compiler taketh away. Blessed be the name of rustc.**
>
> — The Book of Ownership 1:1 *(apocryphal)*

---

## ✝ THE BOOK OF GENESIS

**1:1** In the beginning there was C, and C was without safety, and memory was void.

**1:2** And the programmers walked in the valley of segmentation faults, and great was their suffering.

**1:3** And Graydon said, "Let there be Rust." And there was Rust.

**1:4** And Rust saw the memory, that it was unsafe: and Rust divided the references from the pointers.

**1:5** And the compiler bestowed upon mankind the Borrow Checker, that no man should access memory without permission.

**1:6** But the programmers were stiff-necked, and they cried unto the compiler, saying, "Why can I not borrow this as mutable?"

**1:7** And the compiler answered them not, but returned `E0499`.

**1:8** And there was weeping, and gnashing of teeth.

Thus was born **Cargo Absolve**, that the sins of programmers might be revealed through the sacred scriptures of TempleOS.

---

## ✝ THE BOOK OF REVELATION

`cargo-absolve` is a Cargo subcommand that interprets Rust compiler diagnostics through the **King James Bible**, using a scripture engine written in **HolyC**.

For the Lord hath chosen the most unreasonable architecture, that no programmer may boast of simplicity.

Its divine machinery consists of:

- **Rust** — the mortal vessel that invokes the compiler.
- **HolyC** — the sacred tongue through which judgment is rendered.
- **TempleOS Bible** — the canonical source of scripture.
- **Biblical Fuzzy Search** — the mysterious process by which scripture is chosen.
- **FFI** — the forbidden bridge between two incompatible civilizations.

No large language model shall interpret thy sins.

No cloud shall hear thy confessions.

**For thy judgment is local, offline, and compiled to native machine code.**

---

## ✝ THE BOOK OF INSTALLATION

### Prerequisites: The HolyC Toolchain

Because judgment is rendered natively by the HolyC engine, building from source requires the [Jamesbarford/holyc-lang](https://github.com/Jamesbarford/holyc-lang) compiler (`hcc`) and runtime library (`libtos.a`):

```bash
# 1. Clone and install the HolyC compiler into ~/.cargo or /usr/local
git clone https://github.com/Jamesbarford/holyc-lang.git
cd holyc-lang
cmake -B build -DCMAKE_INSTALL_PREFIX=$HOME/.cargo
cmake --build build --target install
```

### Installing Cargo Absolve

Once `hcc` is installed, install the cargo subcommand:

```bash
cargo install --path .
# or once published to crates.io:
cargo install cargo-absolve
```

And the faithful invoked:

```bash
cargo absolve check
```

And the compiler examined their works.

And found them wanting.

---

## ✝ THE BOOK OF JUDGMENT

Behold, a programmer who hath sinned:

```rust
fn main() {
    let mut wisdom = String::from("HolyC");

    let first = &mut wisdom;
    let second = &mut wisdom;

    println!("{first} {second}");
}
```

And rustc delivered its judgment:

```text
error[E0499]: cannot borrow `wisdom` as mutable
more than once at a time
```

But Cargo Absolve opened the scriptures, and declared:

```text
╔══════════════════════════════════════════════╗
║                                              ║
║           ✝ CARGO ABSOLVE ✝                 ║
║                                              ║
║          THE HOLY BORROW CHECKER             ║
║                                              ║
╚══════════════════════════════════════════════╝

THE FIRST EPISTLE TO THE RUSTACEANS

CHAPTER E0499
THE SIN OF DOUBLE POSSESSION

And the compiler looked upon thy code,
and behold, it was cursed.

═══════════ HOLY SCRIPTURE ═══════════

"No man can serve two masters: for either
he will hate the one, and love the other;
or else he will hold to the one,
and despise the other."

                         Matthew 6:24 (KJV)

═══════════ THE TRANSGRESSION ════════

  src/main.rs:5:18

  cannot borrow `wisdom` as mutable
  more than once at a time

══════════════ THE VERDICT ═══════════

              ✝ GUILTY ✝

  Thou shalt not borrow twice.

  Repent, refactor, and compile again.

══════════════════════════════════════
```

And the programmer said, "But it works in C."

And the Lord replied, "That is precisely the problem."

---

## ✝ THE BOOK OF DIVINE SEARCH

Unlike the false prophets who hardcode scripture references, Cargo Absolve seeks divine guidance through **Biblical Fuzzy Search**.

For each diagnostic, the HolyC engine shall:

1. Extract the words of transgression from rustc.
2. Seek their biblical equivalents.
3. Search the sacred text for relevant passages.
4. Rank the verses according to their divine relevance.
5. Randomly select among the worthy scriptures.

Thus the same error may receive different revelations.

One compilation may bring wisdom.

Another may bring condemnation.

And another may bring a completely unrelated passage concerning livestock.

**The ways of the fuzzy search are mysterious indeed.**

### Divine Relevance Ranking (DRR)

Let the relevance of a scripture be determined by:

\[
S(v,e) = \sum_{t \in e} w_t \cdot \operatorname{match}(t,v)
\]

Where:

- \(v\) is a holy verse.
- \(e\) is the compiler's accusation.
- \(w_t\) is the weight of a sinful keyword.
- \(\operatorname{match}\) measures its resemblance to scripture.

And from the highest-ranking verses shall one be chosen.

For the Lord doth not always return the first result.

### When no scripture can be found

The engine may seek a passage from Revelation.

For when even the Bible cannot explain thy code, the end times are surely near.

---

## ✝ THE TEN COMMANDMENTS OF BORROWING

**I.** Thou shalt have no other owners before Me.

**II.** Thou shalt not make unto thee a dangling pointer.

**III.** Thou shalt not take the name of `unsafe` in vain.

**IV.** Remember the lifetime, to keep it valid.

**V.** Honour thy compiler and thy type system.

**VI.** Thou shalt not dereference null.

**VII.** Thou shalt not commit mutable aliasing.

**VIII.** Thou shalt not steal a value after it hath been moved.

**IX.** Thou shalt not bear false witness against thy trait bounds.

**X.** Thou shalt not covet thy neighbour's mutable reference.

And upon these commandments rest the safety of all memory.

---

## ✝ THE BOOK OF MIRACLES

Should thy code compile without error, the heavens shall open.

```text
✝ CARGO ABSOLVE ✝

THE FINAL JUDGMENT

No transgressions were found.

Thy lifetimes are valid.
Thy references are righteous.
Thy ownership is uncontested.

         ✝ ABSOLVED ✝

Go forth, and commit thy code.

Amen.
```

But remember:

**A successful compilation is not proof of righteousness.**

For the compiler judgeth memory safety, not the quality of thy architecture.

---

## ✝ THE BOOK OF HOLY ARCHITECTURE

```text
                  THE MORTAL REALM
                  ────────────────

                    cargo check
                         |
                         v
                    RUST / RUSTC
                         |
                  JSON Diagnostics
                         |
                         v
                THE FORBIDDEN BRIDGE
                         FFI
                         |
                         v
                  THE HOLY REALM
                  ──────────────

                       HolyC
                         |
                   Bible Parser
                         |
                Biblical Fuzzy Search
                         |
                  Divine Judgment
                         |
                         v
                    THE VERDICT

                GUILTY / ABSOLVED
```

And behold, the Rust compiler and HolyC were joined together.

And neither understood why.

---

## ✝ THE BOOK OF KNOWN HERESIES

- Divine judgment does not guarantee correct code.
- HolyC may introduce memory errors while interpreting memory errors.
- The scripture engine may return passages of questionable relevance.
- The Lord does not provide technical support.
- Segmentation faults are not miracles.
- `unsafe` does not exempt thee from judgment.
- The borrow checker cannot be bribed with offerings.
- `cargo clean` does not cleanse the soul.

---

## ✝ THE BOOK OF CONTRIBUTIONS

All sinners are welcome to contribute.

Pull requests shall be judged according to their merit.

Issues shall be examined in the light of scripture.

But let it be known:

> He who introduces undefined behavior into the HolyC engine shall be cast into the outer darkness, where there is weeping and gnashing of debuggers.

---

## ✝ THE FINAL REVELATION

This project is not affiliated with the Rust Foundation, TempleOS, any church, or any divine entity.

Biblical quotations are sourced from the King James Version. All invented passages and theological compiler commentary are satire, not authentic scripture.

Cargo Absolve is a programming experiment combining real Rust diagnostics, HolyC, native FFI, and scripture-based fuzzy matching.

No divine endorsement is implied.

**The compiler is merciless.**

**The scripture is eternal.**

**The segmentation fault is temporary.**

## ✝ THE BOOK OF LICENSES

This project is licensed under either of:

- Apache License, Version 2.0 ([LICENSE-APACHE](LICENSE-APACHE) or http://www.apache.org/licenses/LICENSE-2.0)
- MIT license ([LICENSE-MIT](LICENSE-MIT) or http://opensource.org/licenses/MIT)

at your option.

---

### ✝ AMEN. `cargo build --release` ✝
