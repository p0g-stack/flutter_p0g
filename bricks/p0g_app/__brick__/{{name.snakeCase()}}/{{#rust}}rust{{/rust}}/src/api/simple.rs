use flutter_rust_bridge::frb;

/// An example binding. Replace with the crates the core needs.
#[frb(sync)]
pub fn add(a: i64, b: i64) -> i64 {
    a + b
}

#[cfg(test)]
mod tests {
    #[test]
    fn adds() {
        assert_eq!(super::add(2, 3), 5);
    }
}
