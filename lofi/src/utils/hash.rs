/// Returns a short hex string that uniquely identifies a URL for use as a cache filename.
/// Uses FNV-1a 64-bit — fast, no dependencies, good distribution for URLs.
pub fn url_hash(url: &str) -> String {
    const FNV_OFFSET: u64 = 14695981039346656037;
    const FNV_PRIME:  u64 = 1099511628211;
    let mut hash = FNV_OFFSET;
    for byte in url.bytes() {
        hash ^= byte as u64;
        hash = hash.wrapping_mul(FNV_PRIME);
    }
    format!("{:016x}", hash)
}
