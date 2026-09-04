use crate::skill_map::{assert_safe_segment, parse_relative_path};

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum TreeStructureMode {
    Declared,
    ParentSuccess,
    NoStructure,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum SkillNodeMethod {
    Node,
    Tree(TreeStructureMode),
    Help,
    Plan,
}

impl SkillNodeMethod {
    pub const fn name(self) -> &'static str {
        match self {
            Self::Node => "node",
            Self::Tree(TreeStructureMode::Declared) => "tree",
            Self::Tree(TreeStructureMode::ParentSuccess) => "tree.parent-success",
            Self::Tree(TreeStructureMode::NoStructure) => "tree.no-structure",
            Self::Help => "help",
            Self::Plan => "plan",
        }
    }
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct SkillInvocationTarget {
    skill_map_id: String,
    skill_path: Option<String>,
    method: SkillNodeMethod,
}

impl SkillInvocationTarget {
    pub fn parse(value: &str) -> Result<Self, String> {
        if value.is_empty() || value.contains('\\') {
            return Err(format!(
                "Skill invocation target must be a canonical relative path: {value}"
            ));
        }
        let mut segments: Vec<_> = value.split('/').collect();

        let method = match segments.last().copied() {
            Some(".tree") => {
                segments.pop();
                SkillNodeMethod::Tree(TreeStructureMode::Declared)
            }
            Some(".tree.parent-success") => {
                segments.pop();
                SkillNodeMethod::Tree(TreeStructureMode::ParentSuccess)
            }
            Some(".tree.no-structure") => {
                segments.pop();
                SkillNodeMethod::Tree(TreeStructureMode::NoStructure)
            }
            Some(".help") => {
                segments.pop();
                SkillNodeMethod::Help
            }
            Some(".plan") => {
                segments.pop();
                SkillNodeMethod::Plan
            }
            Some(segment) if segment.starts_with('.') => {
                return Err(format!(
                    "unknown Core Host node method '{segment}' in Skill invocation target"
                ));
            }
            _ => SkillNodeMethod::Node,
        };
        if segments.is_empty() {
            return Err(format!(
                "Skill invocation target must contain a SkillMapId: {value}"
            ));
        }
        if segments.len() < 2 && method != SkillNodeMethod::Help {
            return Err(format!(
                "Skill invocation target must contain a non-empty SkillPath: {value}"
            ));
        }

        let skill_map_id = segments.remove(0);
        assert_safe_segment(skill_map_id, "SkillMapId")?;
        let skill_path = if segments.is_empty() {
            None
        } else {
            let skill_path = segments.join("/");
            parse_relative_path(&skill_path, "SkillPath")?;
            Some(skill_path)
        };

        Ok(Self {
            skill_map_id: skill_map_id.to_owned(),
            skill_path,
            method,
        })
    }

    pub fn skill_map_id(&self) -> &str {
        &self.skill_map_id
    }

    pub fn skill_path(&self) -> Option<&str> {
        self.skill_path.as_deref()
    }

    pub fn method(&self) -> SkillNodeMethod {
        self.method
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn target_separates_map_path_and_virtual_method() {
        for (source, path, method) in [
            ("core/helloworld", Some("helloworld"), SkillNodeMethod::Node),
            (
                "core/release/publish/.tree",
                Some("release/publish"),
                SkillNodeMethod::Tree(TreeStructureMode::Declared),
            ),
            (
                "core/release/publish/.tree.parent-success",
                Some("release/publish"),
                SkillNodeMethod::Tree(TreeStructureMode::ParentSuccess),
            ),
            (
                "core/release/publish/.tree.no-structure",
                Some("release/publish"),
                SkillNodeMethod::Tree(TreeStructureMode::NoStructure),
            ),
            (
                "core/helloworld/.help",
                Some("helloworld"),
                SkillNodeMethod::Help,
            ),
            ("core/.help", None, SkillNodeMethod::Help),
            (
                "core/helloworld/.plan",
                Some("helloworld"),
                SkillNodeMethod::Plan,
            ),
        ] {
            let target = SkillInvocationTarget::parse(source).unwrap();
            assert_eq!(target.skill_map_id(), "core");
            assert_eq!(target.skill_path(), path);
            assert_eq!(target.method(), method);
        }
    }

    #[test]
    fn invalid_targets_and_unknown_methods_are_rejected() {
        for source in [
            "",
            "helloworld",
            "core",
            "core/.tree",
            "core/.plan",
            "Core/helloworld",
            "core/Hello",
            "core//helloworld",
            "core/helloworld/.retry",
            "core/helloworld/.tree.none",
            "core/helloworld\\.tree",
        ] {
            assert!(SkillInvocationTarget::parse(source).is_err(), "{source}");
        }
    }
}
