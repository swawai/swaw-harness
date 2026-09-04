use crate::skill_map::HelpLanguage;

pub const MAXIMUM_HELP_DEPTH: usize = crate::skill_map::MAXIMUM_TREE_DEPTH;
const DEFAULT_HELP_DEPTH: usize = 1;
const USAGE: &str = "usage: /.help [depth] [--language en|zh|zh-CN]";

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct HelpInvocationOptions {
    depth: usize,
    language: HelpLanguage,
}

impl HelpInvocationOptions {
    pub fn parse(arguments: &[String]) -> Result<Self, String> {
        let (depth, language) = match arguments {
            [] => (DEFAULT_HELP_DEPTH, HelpLanguage::English),
            [depth] => (parse_depth(depth)?, HelpLanguage::English),
            [flag, language] if flag == "--language" => {
                (DEFAULT_HELP_DEPTH, HelpLanguage::parse(language)?)
            }
            [depth, flag, language] if flag == "--language" => {
                (parse_depth(depth)?, HelpLanguage::parse(language)?)
            }
            _ => return Err(USAGE.to_owned()),
        };
        Ok(Self { depth, language })
    }

    pub fn depth(self) -> usize {
        self.depth
    }

    pub fn language(self) -> HelpLanguage {
        self.language
    }
}

fn parse_depth(value: &str) -> Result<usize, String> {
    if value.is_empty()
        || !value.bytes().all(|byte| byte.is_ascii_digit())
        || (value.len() > 1 && value.starts_with('0'))
    {
        return Err(USAGE.to_owned());
    }
    let depth = value.parse::<usize>().map_err(|_| USAGE.to_owned())?;
    if !(1..=MAXIMUM_HELP_DEPTH).contains(&depth) {
        return Err(format!(
            "Help depth must be between 1 and {MAXIMUM_HELP_DEPTH}"
        ));
    }
    Ok(depth)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn help_options_have_bounded_defaults_and_explicit_language() {
        for (arguments, depth, language) in [
            (vec![], 1, HelpLanguage::English),
            (vec!["3"], 3, HelpLanguage::English),
            (
                vec!["--language", "zh-CN"],
                1,
                HelpLanguage::ChineseSimplified,
            ),
            (vec!["2", "--language", "zh"], 2, HelpLanguage::Chinese),
        ] {
            let arguments: Vec<_> = arguments.into_iter().map(str::to_owned).collect();
            let options = HelpInvocationOptions::parse(&arguments).unwrap();
            assert_eq!(options.depth(), depth);
            assert_eq!(options.language(), language);
        }
    }

    #[test]
    fn unknown_or_noncanonical_help_options_are_rejected() {
        for arguments in [
            vec!["0"],
            vec!["01"],
            vec!["65"],
            vec!["-v"],
            vec!["--language"],
            vec!["--language", "zh-cn"],
            vec!["--language", "fr"],
            vec!["--language", "zh-CN", "2"],
        ] {
            let arguments: Vec<_> = arguments.into_iter().map(str::to_owned).collect();
            assert!(
                HelpInvocationOptions::parse(&arguments).is_err(),
                "{arguments:?}"
            );
        }
    }
}
