//! VI. GLUTTONY (E0061)
//! Thou hast demanded more than was appointed.
//!
//! Run: `cargo absolve check --example gluttony`

fn communion(bread: u32, wine: u32) {
    println!("{bread} loaves and {wine} cups");
}

fn main() {
    communion(5, 2, 5000);
}

