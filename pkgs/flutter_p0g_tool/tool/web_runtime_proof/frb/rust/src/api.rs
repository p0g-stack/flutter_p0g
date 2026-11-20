#[flutter_rust_bridge::frb(sync)]
pub fn deterministic_value() -> String {
    format!("rust:{}", (1..=100).sum::<u32>())
}
