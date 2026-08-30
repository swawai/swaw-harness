use std::fmt;

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum BaseResourceSpace {
    Author,
    Runtime,
    Runs,
    Export,
    Context,
}

impl BaseResourceSpace {
    pub const fn name(self) -> &'static str {
        match self {
            Self::Author => "author",
            Self::Runtime => "runtime",
            Self::Runs => "runs",
            Self::Export => "export",
            Self::Context => "context",
        }
    }
}

impl fmt::Display for BaseResourceSpace {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter.write_str(self.name())
    }
}

#[cfg(test)]
mod tests {
    use super::BaseResourceSpace;

    #[test]
    fn base_resource_space_names_are_fixed() {
        assert_eq!(BaseResourceSpace::Author.name(), "author");
        assert_eq!(BaseResourceSpace::Runtime.name(), "runtime");
        assert_eq!(BaseResourceSpace::Runs.name(), "runs");
        assert_eq!(BaseResourceSpace::Export.name(), "export");
        assert_eq!(BaseResourceSpace::Context.name(), "context");
    }
}
