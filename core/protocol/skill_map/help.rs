use std::fs;
use std::path::Path;

use super::{
    MAXIMUM_TREE_DEPTH, SKILL_DOCUMENT_NAME, SkillMap, join_exact_regular_directories_inspecting,
    parse_relative_path, parse_skill_declaration, regular_file_exists, validate_directory_entries,
};

const DEFAULT_HELP_DOCUMENT_NAME: &str = "help.md";
const ENGLISH_HELP_DOCUMENT_NAME: &str = "help.en.md";
const CHINESE_HELP_DOCUMENT_NAME: &str = "help.zh.md";
const CHINESE_SIMPLIFIED_HELP_DOCUMENT_NAME: &str = "help.zh-CN.md";
const HELP_DOCUMENT_NAMES: [&str; 4] = [
    DEFAULT_HELP_DOCUMENT_NAME,
    ENGLISH_HELP_DOCUMENT_NAME,
    CHINESE_HELP_DOCUMENT_NAME,
    CHINESE_SIMPLIFIED_HELP_DOCUMENT_NAME,
];
const MAXIMUM_HELP_DOCUMENT_BYTES: u64 = 16 * 1024;
const MAXIMUM_HELP_SUMMARY_BYTES: usize = 512;
const MAXIMUM_HELP_NODES: usize = 4096;
const MAXIMUM_HELP_DIRECTORIES: usize = 4096;
const UTF8_BOM: &[u8] = &[0xef, 0xbb, 0xbf];

pub(super) struct HelpTraversalBudget {
    displayed_nodes: usize,
    inspected_directories: usize,
    maximum_directories: usize,
}

impl HelpTraversalBudget {
    fn new() -> Self {
        Self {
            displayed_nodes: 0,
            inspected_directories: 0,
            maximum_directories: MAXIMUM_HELP_DIRECTORIES,
        }
    }

    #[cfg(test)]
    pub(super) fn with_maximum_directories(maximum_directories: usize) -> Self {
        Self {
            displayed_nodes: 0,
            inspected_directories: 0,
            maximum_directories,
        }
    }

    pub(super) fn inspect_directory(&mut self, directory: &Path) -> Result<(), String> {
        if self.inspected_directories >= self.maximum_directories {
            return Err(format!(
                "Help traversal exceeds {} inspected directories: {}",
                self.maximum_directories,
                directory.display()
            ));
        }
        self.inspected_directories += 1;
        Ok(())
    }

    fn display_node(&mut self) -> Result<(), String> {
        if self.displayed_nodes >= MAXIMUM_HELP_NODES {
            return Err(format!(
                "Help tree exceeds {MAXIMUM_HELP_NODES} displayed nodes"
            ));
        }
        self.displayed_nodes += 1;
        Ok(())
    }
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum HelpLanguage {
    English,
    Chinese,
    ChineseSimplified,
}

impl HelpLanguage {
    pub fn parse(value: &str) -> Result<Self, String> {
        match value {
            "en" => Ok(Self::English),
            "zh" => Ok(Self::Chinese),
            "zh-CN" => Ok(Self::ChineseSimplified),
            _ => Err(format!(
                "unsupported Help language '{value}'; expected en, zh, or zh-CN"
            )),
        }
    }

    fn document_candidates(self) -> &'static [&'static str] {
        match self {
            Self::English => &[ENGLISH_HELP_DOCUMENT_NAME, DEFAULT_HELP_DOCUMENT_NAME],
            Self::Chinese => &[CHINESE_HELP_DOCUMENT_NAME, DEFAULT_HELP_DOCUMENT_NAME],
            Self::ChineseSimplified => &[
                CHINESE_SIMPLIFIED_HELP_DOCUMENT_NAME,
                CHINESE_HELP_DOCUMENT_NAME,
                DEFAULT_HELP_DOCUMENT_NAME,
            ],
        }
    }
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct SkillHelpNode {
    skill_path: Option<String>,
    callable: bool,
    summary: Option<String>,
    children: Vec<Self>,
}

impl SkillHelpNode {
    pub fn skill_path(&self) -> Option<&str> {
        self.skill_path.as_deref()
    }

    pub fn callable(&self) -> bool {
        self.callable
    }

    pub fn summary(&self) -> Option<&str> {
        self.summary.as_deref()
    }

    pub fn children(&self) -> &[Self] {
        &self.children
    }
}

impl SkillMap {
    pub fn describe_help(
        &self,
        skill_path: Option<&str>,
        depth: usize,
        language: HelpLanguage,
    ) -> Result<SkillHelpNode, String> {
        let mut budget = HelpTraversalBudget::new();
        self.describe_help_with_budget(skill_path, depth, language, &mut budget)
    }

    pub(super) fn describe_help_with_budget(
        &self,
        skill_path: Option<&str>,
        depth: usize,
        language: HelpLanguage,
        budget: &mut HelpTraversalBudget,
    ) -> Result<SkillHelpNode, String> {
        if !(1..=MAXIMUM_TREE_DEPTH).contains(&depth) {
            return Err(format!(
                "Help depth must be between 1 and {MAXIMUM_TREE_DEPTH}"
            ));
        }
        budget.inspect_directory(&self.root)?;
        let (directory, skill_path) = match skill_path {
            Some(skill_path) => {
                let segments = parse_relative_path(skill_path, "SkillPath")?;
                let directory = join_exact_regular_directories_inspecting(
                    &self.root,
                    &segments,
                    "Skill directory",
                    |directory| budget.inspect_directory(directory),
                )?;
                (directory, Some(skill_path.to_owned()))
            }
            None => (self.root.clone(), None),
        };
        describe_directory(
            &self.root,
            &directory,
            skill_path,
            depth,
            language,
            budget,
        )
    }
}

fn describe_directory(
    root: &Path,
    directory: &Path,
    skill_path: Option<String>,
    depth: usize,
    language: HelpLanguage,
    budget: &mut HelpTraversalBudget,
) -> Result<SkillHelpNode, String> {
    budget.display_node()?;

    let skill_document = directory.join(SKILL_DOCUMENT_NAME);
    let callable = regular_file_exists(&skill_document, "Skill declaration")?;
    if callable {
        if directory == root {
            return Err("Skill Map root cannot declare a Skill".to_owned());
        }
        parse_skill_declaration(&skill_document)?;
    }

    let help_documents = read_help_documents(directory)?;
    let summary = language.document_candidates().iter().find_map(|candidate| {
        help_documents
            .iter()
            .find(|(name, _)| name == candidate)
            .map(|(_, summary)| summary.clone())
    });

    let mut child_directories =
        validate_directory_entries(root, directory, depth > 0, |child_directory| {
            budget.inspect_directory(child_directory)
        })?;
    let mut children = Vec::new();
    if depth > 0 {
        child_directories.sort_by(|left, right| left.file_name().cmp(&right.file_name()));
        for child_directory in child_directories {
            let child_name = child_directory
                .file_name()
                .and_then(|name| name.to_str())
                .ok_or_else(|| "Skill Map directory name is not Unicode".to_owned())?;
            let child_path = match skill_path.as_deref() {
                Some(parent) => format!("{parent}/{child_name}"),
                None => child_name.to_owned(),
            };
            children.push(describe_directory(
                root,
                &child_directory,
                Some(child_path),
                depth - 1,
                language,
                budget,
            )?);
        }
    }

    Ok(SkillHelpNode {
        skill_path,
        callable,
        summary,
        children,
    })
}

pub(super) fn is_help_document_name(name: &str) -> bool {
    HELP_DOCUMENT_NAMES.contains(&name)
}

pub(super) fn validate_help_documents(directory: &Path) -> Result<(), String> {
    read_help_documents(directory).map(|_| ())
}

fn read_help_documents(directory: &Path) -> Result<Vec<(&'static str, String)>, String> {
    let mut documents = Vec::new();
    for name in HELP_DOCUMENT_NAMES {
        let path = directory.join(name);
        if regular_file_exists(&path, "Skill help document")? {
            documents.push((name, parse_help_summary(&path)?));
        }
    }
    Ok(documents)
}

fn parse_help_summary(path: &Path) -> Result<String, String> {
    let metadata = fs::symlink_metadata(path).map_err(|error| {
        format!(
            "cannot inspect Skill help document '{}': {error}",
            path.display()
        )
    })?;
    if metadata.len() == 0 || metadata.len() > MAXIMUM_HELP_DOCUMENT_BYTES {
        return Err(format!(
            "Skill help document has an invalid size: {}",
            path.display()
        ));
    }
    let encoded = fs::read(path).map_err(|error| {
        format!(
            "cannot read Skill help document '{}': {error}",
            path.display()
        )
    })?;
    if encoded.starts_with(UTF8_BOM) {
        return Err(format!(
            "Skill help document must use UTF-8 without BOM: {}",
            path.display()
        ));
    }
    if encoded.contains(&0) {
        return Err(format!(
            "Skill help document contains NUL: {}",
            path.display()
        ));
    }
    let text = std::str::from_utf8(&encoded).map_err(|error| {
        format!(
            "cannot parse Skill help document '{}' as UTF-8: {error}",
            path.display()
        )
    })?;
    let summary = text
        .lines()
        .find(|line| !line.trim().is_empty())
        .map(str::trim)
        .ok_or_else(|| {
            format!(
                "Skill help document has no non-empty summary: {}",
                path.display()
            )
        })?;
    if summary.starts_with("[run]") {
        return Err(format!(
            "Skill help summary starts with the reserved [run] marker: {}",
            path.display()
        ));
    }
    if summary.as_bytes().len() > MAXIMUM_HELP_SUMMARY_BYTES
        || summary.chars().any(char::is_control)
    {
        return Err(format!(
            "Skill help summary is invalid or exceeds {MAXIMUM_HELP_SUMMARY_BYTES} bytes: {}",
            path.display()
        ));
    }
    Ok(summary.to_owned())
}
