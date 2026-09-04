use std::fs;
use std::path::Path;

use crate::skill_map::{
    HelpLanguage, SkillHelpNode, SkillMap, help::HelpTraversalBudget, validate_directory_entries,
};

#[cfg(windows)]
use super::create_junction;
use super::{temporary_map, write_skill};

#[test]
fn help_descriptions_include_categories_depth_and_language_fallbacks() {
    let root = temporary_map("help-tree");
    fs::write(root.join("help.md"), "Default root.\n\nDetails.\n").unwrap();
    fs::write(root.join("help.en.md"), "English root.\n").unwrap();
    fs::write(root.join("help.zh.md"), "中文根。\n").unwrap();
    fs::create_dir_all(root.join("dev")).unwrap();
    fs::write(root.join("dev/help.md"), "Development tools.\n").unwrap();
    write_skill(
        &root.join("dev/setup"),
        "swaw/core/dev",
        "1.*",
        "dev.exe",
        &["dev/setup"],
    );
    fs::write(root.join("dev/setup/help.md"), "Set up tools.\n").unwrap();
    fs::write(root.join("dev/setup/help.zh-CN.md"), "安装工具。\n").unwrap();
    fs::create_dir(root.join("empty")).unwrap();

    let skill_map = SkillMap::open(&root).unwrap();
    skill_map.validate().unwrap();

    let english = skill_map
        .describe_help(None, 1, HelpLanguage::English)
        .unwrap();
    assert_eq!(english.skill_path(), None);
    assert_eq!(english.summary(), Some("English root."));
    assert!(!english.callable());
    assert_eq!(
        english
            .children()
            .iter()
            .map(|child| child.skill_path().unwrap())
            .collect::<Vec<_>>(),
        ["dev", "empty"]
    );
    assert!(english.children()[0].children().is_empty());
    assert_eq!(english.children()[1].summary(), None);

    let chinese = skill_map
        .describe_help(None, 2, HelpLanguage::ChineseSimplified)
        .unwrap();
    assert_eq!(chinese.summary(), Some("中文根。"));
    let dev = &chinese.children()[0];
    assert_eq!(dev.summary(), Some("Development tools."));
    let setup = &dev.children()[0];
    assert_eq!(setup.skill_path(), Some("dev/setup"));
    assert_eq!(setup.summary(), Some("安装工具。"));
    assert!(setup.callable());

    let selected = skill_map
        .describe_help(Some("dev"), 1, HelpLanguage::English)
        .unwrap();
    assert_eq!(selected.skill_path(), Some("dev"));
    assert_eq!(selected.children()[0].skill_path(), Some("dev/setup"));
    skill_map.find("dev/setup").unwrap();

    fs::remove_dir_all(root).unwrap();
}

#[test]
fn help_depth_does_not_inspect_hidden_descendants() {
    let root = temporary_map("help-depth-boundary");
    fs::create_dir_all(root.join("visible/Bad")).unwrap();
    fs::write(root.join("visible/help.md"), "Visible category.\n").unwrap();
    let skill_map = SkillMap::open(&root).unwrap();

    let help = skill_map
        .describe_help(None, 1, HelpLanguage::English)
        .unwrap();
    assert_eq!(help.children()[0].skill_path(), Some("visible"));
    assert_eq!(help.children()[0].summary(), Some("Visible category."));
    assert!(help.children()[0].children().is_empty());
    for forbidden in ["help.fr.md", "skill.json"] {
        fs::write(root.join("visible").join(forbidden), "not supported\n").unwrap();
        assert!(
            skill_map
                .describe_help(None, 1, HelpLanguage::English)
                .unwrap_err()
                .contains("unexpected Skill Map file")
        );
        fs::remove_file(root.join("visible").join(forbidden)).unwrap();
    }
    assert!(
        skill_map
            .describe_help(None, 2, HelpLanguage::English)
            .unwrap_err()
            .contains("invalid Skill Map directory name")
    );

    fs::remove_dir_all(root).unwrap();
}

#[test]
fn help_directory_budget_stops_visible_fanout_during_enumeration() {
    let root = temporary_map("help-visible-directory-budget");
    fs::create_dir(root.join("alpha")).unwrap();
    fs::create_dir(root.join("beta")).unwrap();
    let mut budget = HelpTraversalBudget::with_maximum_directories(2);
    budget.inspect_directory(&root).unwrap();

    let error = validate_directory_entries(&root, &root, true, |child_directory| {
        budget.inspect_directory(child_directory)
    })
    .unwrap_err();

    assert!(error.contains("exceeds 2 inspected directories"), "{error}");
    fs::remove_dir_all(root).unwrap();
}

#[test]
fn help_directory_budget_counts_hidden_boundary_fanout() {
    let root = temporary_map("help-hidden-directory-budget");
    fs::create_dir_all(root.join("visible/alpha")).unwrap();
    fs::create_dir(root.join("visible/beta")).unwrap();
    let mut budget = HelpTraversalBudget::with_maximum_directories(3);
    budget.inspect_directory(&root).unwrap();
    let visible = validate_directory_entries(&root, &root, true, |child_directory| {
        budget.inspect_directory(child_directory)
    })
    .unwrap();

    let error = validate_directory_entries(&root, &visible[0], false, |child_directory| {
        budget.inspect_directory(child_directory)
    })
    .unwrap_err();

    assert!(error.contains("exceeds 3 inspected directories"), "{error}");
    fs::remove_dir_all(root).unwrap();
}

#[test]
fn help_directory_budget_includes_target_resolution() {
    let root = temporary_map("help-target-directory-budget");
    fs::create_dir_all(root.join("alpha/beta")).unwrap();
    let skill_map = SkillMap::open(&root).unwrap();
    let mut budget = HelpTraversalBudget::with_maximum_directories(2);

    let error = skill_map
        .describe_help_with_budget(
            Some("alpha/beta"),
            1,
            HelpLanguage::English,
            &mut budget,
        )
        .unwrap_err();

    assert!(error.contains("exceeds 2 inspected directories"), "{error}");
    fs::remove_dir_all(root).unwrap();
}

#[cfg(windows)]
#[test]
fn help_depth_does_not_validate_a_hidden_reparse_directory() {
    let root = temporary_map("help-depth-reparse");
    let target = temporary_map("help-depth-reparse-target");
    fs::create_dir(root.join("visible")).unwrap();
    create_junction(&root.join("visible/hidden"), &target);
    let skill_map = SkillMap::open(&root).unwrap();

    let help = skill_map
        .describe_help(None, 1, HelpLanguage::English)
        .unwrap();
    assert_eq!(help.children()[0].skill_path(), Some("visible"));
    assert!(help.children()[0].children().is_empty());
    assert!(
        skill_map
            .describe_help(None, 2, HelpLanguage::English)
            .unwrap_err()
            .contains("reparse point")
    );

    fs::remove_dir(root.join("visible/hidden")).unwrap();
    fs::remove_dir_all(root).unwrap();
    fs::remove_dir_all(target).unwrap();
}

#[test]
fn malformed_or_unknown_help_documents_are_rejected() {
    let root = temporary_map("invalid-help");
    let help = root.join("help.md");
    let skill_map = SkillMap::open(&root).unwrap();

    fs::write(&help, "\n \r\n").unwrap();
    assert!(
        skill_map
            .validate()
            .unwrap_err()
            .contains("no non-empty summary")
    );

    fs::write(&help, [0xff_u8, 0xfe]).unwrap();
    assert!(skill_map.validate().unwrap_err().contains("UTF-8"));

    fs::write(&help, b"\xef\xbb\xbf[run] Not actually callable.\n").unwrap();
    assert!(
        skill_map
            .validate()
            .unwrap_err()
            .contains("UTF-8 without BOM")
    );

    fs::write(&help, b"ASCII is valid UTF-8.\n").unwrap();
    skill_map.validate().unwrap();

    fs::write(&help, format!("{}\n", "a".repeat(513))).unwrap();
    assert!(
        skill_map
            .validate()
            .unwrap_err()
            .contains("summary is invalid")
    );

    fs::write(&help, vec![b'a'; 16 * 1024 + 1]).unwrap();
    assert!(skill_map.validate().unwrap_err().contains("invalid size"));

    fs::write(&help, "[run] Not actually callable.\n").unwrap();
    assert!(
        skill_map
            .validate()
            .unwrap_err()
            .contains("reserved [run] marker")
    );

    fs::write(&help, "Valid summary.\n").unwrap();
    fs::write(root.join("help.fr.md"), "Résumé.\n").unwrap();
    assert!(
        skill_map
            .validate()
            .unwrap_err()
            .contains("unexpected Skill Map file")
    );
    fs::remove_file(root.join("help.fr.md")).unwrap();

    fs::remove_file(&help).unwrap();
    fs::write(root.join("Help.md"), "Wrong case.\n").unwrap();
    assert!(
        skill_map
            .validate()
            .unwrap_err()
            .contains("non-canonical Skill help document name")
    );

    fs::remove_dir_all(root).unwrap();
}

#[test]
fn repository_help_describes_every_visible_core_node() {
    let user_home = Path::new(env!("CARGO_MANIFEST_DIR")).join("../../data/admin");
    assert_repository_help_files_exist(&user_home.join("map/core"));
    let skill_map = SkillMap::open_core(user_home).unwrap();
    for language in [HelpLanguage::English, HelpLanguage::ChineseSimplified] {
        let root = skill_map.describe_help(None, 64, language).unwrap();
        assert!(root.summary().is_some());
        assert_repository_help_is_complete(&root);
    }
}

fn assert_repository_help_files_exist(directory: &Path) {
    for name in ["help.md", "help.zh-CN.md"] {
        let path = directory.join(name);
        assert!(
            path.is_file(),
            "missing repository help file: {}",
            path.display()
        );
    }
    let mut child_directories = fs::read_dir(directory)
        .unwrap()
        .map(|entry| entry.unwrap())
        .filter(|entry| entry.file_type().unwrap().is_dir())
        .map(|entry| entry.path())
        .collect::<Vec<_>>();
    child_directories.sort();
    for child_directory in child_directories {
        assert_repository_help_files_exist(&child_directory);
    }
}

fn assert_repository_help_is_complete(node: &SkillHelpNode) {
    assert!(
        node.summary().is_some(),
        "missing help for {:?}",
        node.skill_path()
    );
    for child in node.children() {
        assert_repository_help_is_complete(child);
    }
}

#[cfg(windows)]
#[test]
fn reparse_help_documents_are_rejected() {
    let root = temporary_map("help-reparse");
    let target = temporary_map("help-reparse-target");
    create_junction(&root.join("help.md"), &target);

    let skill_map = SkillMap::open(&root).unwrap();
    assert!(skill_map.validate().is_err());
    assert!(
        skill_map
            .describe_help(None, 1, HelpLanguage::English)
            .is_err()
    );

    fs::remove_dir(root.join("help.md")).unwrap();
    fs::remove_dir_all(root).unwrap();
    fs::remove_dir_all(target).unwrap();
}
