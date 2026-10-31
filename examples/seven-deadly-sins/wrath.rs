//! III. WRATH (E0382)
//! The Lord giveth, and the Lord taketh away.
//!
//! Run: `cargo absolve check --example wrath`

fn main() {
    let salvation = String::from("eternal life");

    let devil = salvation;

    println!("Give it back! {salvation}");
    drop(devil);
}

