const DEFAULT_RECIPIENT: &str = "World";

pub fn greeting(recipient: Option<&str>) -> String {
    format!("Hello, {}!", recipient.unwrap_or(DEFAULT_RECIPIENT))
}

#[cfg(test)]
mod tests {
    use super::greeting;

    #[test]
    fn greets_the_default_recipient() {
        assert_eq!(greeting(None), "Hello, World!");
    }

    #[test]
    fn greets_the_requested_recipient() {
        assert_eq!(greeting(Some("Swaw")), "Hello, Swaw!");
    }
}
