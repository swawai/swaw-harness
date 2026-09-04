use std::fs::File;

use swaw_harness_core_protocol::{
    HelpInvocationOptions, SkillHelpNode, SkillInvocationTarget, SkillMap,
};

use super::super::identity::HostIdentity;
use crate::wire::{self, KIND_RESULT};

const COMMENT_COLUMN_STEP: usize = 16;

pub(super) fn invoke(
    pipe: &mut File,
    identity: &HostIdentity,
    target: &SkillInvocationTarget,
    arguments: impl IntoIterator<Item = Vec<u16>>,
) -> Result<(), String> {
    let arguments = arguments
        .into_iter()
        .map(|value| {
            String::from_utf16(&value).map_err(|_| "Help argument is not valid UTF-16".to_owned())
        })
        .collect::<Result<Vec<_>, _>>()?;
    let options = HelpInvocationOptions::parse(&arguments)?;
    let skill_map = SkillMap::open_core(identity.user_home())?;
    let root = skill_map.describe_help(target.skill_path(), options.depth(), options.language())?;
    let output = render(target.skill_map_id(), &root)?;
    wire::write_utf8_stdout(pipe, &output)?;
    wire::write_frame(pipe, KIND_RESULT, &0_u32.to_le_bytes())
}

fn render(skill_map_id: &str, root: &SkillHelpNode) -> Result<String, String> {
    let mut output = String::new();
    let root_path = match root.skill_path() {
        Some(skill_path) => format!("{skill_map_id}/{skill_path}"),
        None => skill_map_id.to_owned(),
    };
    append_line(&mut output, &root_path, root);
    append_children(&mut output, skill_map_id, root.children())?;
    if output.len() > wire::MAXIMUM_PAYLOAD_BYTES {
        Err(format!(
            "Help output exceeds the Core Host response limit of {} bytes",
            wire::MAXIMUM_PAYLOAD_BYTES
        ))
    } else {
        Ok(output)
    }
}

fn append_children(
    output: &mut String,
    skill_map_id: &str,
    children: &[SkillHelpNode],
) -> Result<(), String> {
    for child in children {
        let skill_path = child
            .skill_path()
            .ok_or_else(|| "Help child is missing its SkillPath".to_owned())?;
        let path = format!("{skill_map_id}/{skill_path}");
        append_line(output, &path, child);
        append_children(output, skill_map_id, child.children())?;
    }
    Ok(())
}

fn append_line(output: &mut String, path: &str, node: &SkillHelpNode) {
    output.push_str(path);
    if !node.callable() && node.summary().is_none() {
        output.push('\n');
        return;
    }
    let padding = COMMENT_COLUMN_STEP - path.len() % COMMENT_COLUMN_STEP;
    for _ in 0..padding {
        output.push(' ');
    }
    output.push('#');
    if node.callable() {
        output.push_str(" [run]");
    }
    if let Some(summary) = node.summary() {
        output.push(' ');
        output.push_str(summary);
    }
    output.push('\n');
}

#[cfg(test)]
mod tests {
    use std::fs;
    use std::path::Path;

    use swaw_harness_core_protocol::{HelpLanguage, SkillMap};
    use uuid::Uuid;

    use super::{COMMENT_COLUMN_STEP, render};

    #[test]
    fn repository_help_renders_a_stable_bounded_path_list() {
        let user_home = Path::new(env!("CARGO_MANIFEST_DIR")).join("../../data/admin");
        let skill_map = SkillMap::open_core(user_home).unwrap();
        let root = skill_map
            .describe_help(None, 3, HelpLanguage::ChineseSimplified)
            .unwrap();

        let output = render("core", &root).unwrap();
        assert_eq!(
            output,
            concat!(
                "core            # 浏览内置 Core 技能。\n",
                "core/admin      # 管理 Harness。\n",
                "core/admin/user # 管理 Harness 用户。\n",
                "core/admin/user/create          # [run] 创建 Harness 用户。\n",
                "core/dev        # 管理开发工具。\n",
                "core/dev/bun    # 管理 Bun 运行时。\n",
                "core/dev/bun/mode               # [run] 查看或更改 Bun 模式。\n",
                "core/helloworld # [run] 输出问候语。\n",
            )
        );
        for line in output.lines() {
            assert_eq!(line.find('#').unwrap() % COMMENT_COLUMN_STEP, 0);
        }
    }

    #[test]
    fn selected_category_renders_its_full_invocation_path() {
        let user_home = Path::new(env!("CARGO_MANIFEST_DIR")).join("../../data/admin");
        let skill_map = SkillMap::open_core(user_home).unwrap();
        let root = skill_map
            .describe_help(Some("dev"), 2, HelpLanguage::English)
            .unwrap();

        assert_eq!(
            render("core", &root).unwrap(),
            concat!(
                "core/dev        # Manage development tools.\n",
                "core/dev/bun    # Manage the Bun runtime.\n",
                "core/dev/bun/mode               # [run] Read or change the Bun mode.\n",
            )
        );
    }

    #[test]
    fn flat_lines_handle_missing_summaries_and_exact_column_boundaries() {
        let map_root = std::env::temp_dir().join(format!(
            "swaw-harness-help-render-{}-{}",
            std::process::id(),
            Uuid::now_v7().simple()
        ));
        fs::create_dir_all(map_root.join("abcdefghijk")).unwrap();
        fs::write(map_root.join("abcdefghijk/help.md"), "Exact boundary.\n").unwrap();
        fs::create_dir_all(map_root.join("category")).unwrap();
        fs::create_dir_all(map_root.join("command")).unwrap();
        fs::write(
            map_root.join("command/skill.toml"),
            concat!(
                "schema = \"swaw.harness.skill/v2\"\n",
                "module = \"swaw/test/command\"\n",
                "version = \"1.*\"\n",
                "executable = \"command.exe\"\n",
                "arguments = []\n",
            ),
        )
        .unwrap();
        let skill_map = SkillMap::open(&map_root).unwrap();
        let root = skill_map
            .describe_help(None, 1, HelpLanguage::English)
            .unwrap();

        assert_eq!(
            render("core", &root).unwrap(),
            concat!(
                "core\n",
                "core/abcdefghijk                # Exact boundary.\n",
                "core/category\n",
                "core/command    # [run]\n",
            )
        );

        fs::remove_dir_all(map_root).unwrap();
    }
}
