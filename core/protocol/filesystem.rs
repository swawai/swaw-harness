use std::fs;
use std::path::{Path, PathBuf};

pub(crate) fn find_exact_child(
    parent: &Path,
    name: &str,
    description: &str,
) -> Result<PathBuf, String> {
    let mut matches = Vec::new();
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
        if actual_name.eq_ignore_ascii_case(name) {
            matches.push((actual_name.to_owned(), entry.path()));
        }
    }

    resolve_exact_child_matches(parent, name, description, matches)
}

fn resolve_exact_child_matches(
    parent: &Path,
    name: &str,
    description: &str,
    mut matches: Vec<(String, PathBuf)>,
) -> Result<PathBuf, String> {
    if matches.len() > 1 {
        matches.sort_by(|left, right| left.0.cmp(&right.0));
        let names = matches
            .iter()
            .map(|(actual_name, _)| format!("'{actual_name}'"))
            .collect::<Vec<_>>()
            .join(", ");
        return Err(format!(
            "ambiguous case-insensitive {description} names {names}; expected only '{name}' in '{}'",
            parent.display()
        ));
    }

    let Some((actual_name, path)) = matches.pop() else {
        return Err(format!(
            "cannot find {description} named '{name}' in '{}'",
            parent.display()
        ));
    };
    if actual_name != name {
        return Err(format!(
            "non-canonical {description} name '{actual_name}'; expected '{name}': {}",
            path.display()
        ));
    }
    Ok(path)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn exact_name_does_not_hide_a_case_alias() {
        let parent = Path::new("fixture-user-home");
        let error = resolve_exact_child_matches(
            parent,
            "user.json",
            "Harness User record",
            vec![
                ("user.json".to_owned(), parent.join("user.json")),
                ("User.json".to_owned(), parent.join("User.json")),
            ],
        )
        .unwrap_err();

        assert!(
            error.contains("ambiguous case-insensitive Harness User record names"),
            "{error}"
        );
    }
}
