use std::fs;
use std::path::{Path, PathBuf};

pub(crate) fn find_exact_child(
    parent: &Path,
    name: &str,
    description: &str,
) -> Result<PathBuf, String> {
    let mut case_alias = None;
    for entry in fs::read_dir(parent).map_err(|error| {
        format!(
            "cannot enumerate parent directory '{}' for {description}: {error}",
            parent.display()
        )
    })? {
        let entry = entry.map_err(|error| {
            format!(
                "cannot enumerate parent directory '{}' for {description}: {error}",
                parent.display()
            )
        })?;
        let file_name = entry.file_name();
        let Some(actual_name) = file_name.to_str() else {
            continue;
        };
        if actual_name == name {
            return Ok(entry.path());
        }
        if actual_name.eq_ignore_ascii_case(name) {
            case_alias = Some((actual_name.to_owned(), entry.path()));
        }
    }

    if let Some((actual_name, path)) = case_alias {
        return Err(format!(
            "non-canonical {description} name '{actual_name}'; expected '{name}': {}",
            path.display()
        ));
    }
    Err(format!(
        "cannot find {description} named '{name}' in '{}'",
        parent.display()
    ))
}
