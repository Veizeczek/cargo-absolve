//! II. PRIDE (E0277)
//! Thou art not worthy of the trait.
//!
//! Run: `cargo absolve check --example pride`

fn main() {
    struct FalseProphet;

    fn proclaim<T: std::fmt::Display>(prophet: T) {
        println!("{prophet}");
    }

    proclaim(FalseProphet);
}

