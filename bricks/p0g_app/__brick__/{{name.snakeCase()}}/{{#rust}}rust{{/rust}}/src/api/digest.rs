use flutter_rust_bridge::frb;
use sha2::{Digest, Sha256};

/// The SHA-256 of [data] as lowercase hex, through the `sha2` crate. An
/// example of a crate the core uses; replace it with the ones you need.
#[frb(sync)]
pub fn sha256_hex(data: Vec<u8>) -> String {
    Sha256::digest(&data)
        .iter()
        .map(|b| format!("{b:02x}"))
        .collect()
}

#[cfg(test)]
mod tests {
    #[test]
    fn hashes() {
        assert_eq!(
            super::sha256_hex(b"abc".to_vec()),
            "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
        );
    }
}
