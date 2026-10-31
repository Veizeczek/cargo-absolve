//! I. GREED (E0499)
//! Thou shalt not borrow thy neighbour's mutable reference.
//!
//! Run: `cargo absolve check --example greed`

fn main() {
    let mut holy_grail = String::from("eternal salvation");

    let pope = &mut holy_grail;
    let antipope = &mut holy_grail;

    println!("{pope} {antipope}");
}

