//! IV. ENVY (E0502)
//! Thou shalt not covet what another hath borrowed.
//!
//! Run: `cargo absolve check --example envy`

fn main() {
    let mut commandments = vec![1, 2, 3];

    let old_testament = &commandments;
    let new_testament = &mut commandments;

    new_testament.push(4);
    println!("{old_testament:?}");
}

