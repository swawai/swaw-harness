fn main() {
    if let Err(error) = swaw_harness_core::run() {
        eprintln!("[ERROR] {error}");
        std::process::exit(1);
    }
}
