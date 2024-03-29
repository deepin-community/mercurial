use crate::error::CommandError;
use clap::Arg;
use format_bytes::format_bytes;
use hg::operations::cat;
use hg::utils::hg_path::HgPathBuf;
use std::ffi::OsString;
use std::os::unix::prelude::OsStrExt;

pub const HELP_TEXT: &str = "
Output the current or given revision of files
";

pub fn args() -> clap::Command {
    clap::command!("cat")
        .arg(
            Arg::new("rev")
                .help("search the repository as it is in REV")
                .short('r')
                .long("rev")
                .value_name("REV"),
        )
        .arg(
            clap::Arg::new("files")
                .required(true)
                .num_args(1..)
                .value_name("FILE")
                .value_parser(clap::value_parser!(std::ffi::OsString))
                .help("Files to output"),
        )
        .about(HELP_TEXT)
}

#[logging_timer::time("trace")]
pub fn run(invocation: &crate::CliInvocation) -> Result<(), CommandError> {
    let cat_enabled_default = true;
    let cat_enabled = invocation.config.get_option(b"rhg", b"cat")?;
    if !cat_enabled.unwrap_or(cat_enabled_default) {
        return Err(CommandError::unsupported(
            "cat is disabled in rhg (enable it with 'rhg.cat = true' \
            or enable fallback with 'rhg.on-unsupported = fallback')",
        ));
    }

    let rev = invocation.subcommand_args.get_one::<String>("rev");
    let file_args =
        match invocation.subcommand_args.get_many::<OsString>("files") {
            Some(files) => files
                .filter(|s| !s.is_empty())
                .map(|s| s.as_os_str())
                .collect(),
            None => vec![],
        };

    let repo = invocation.repo?;
    let cwd = hg::utils::current_dir()?;
    let working_directory = repo.working_directory_path();
    let working_directory = cwd.join(working_directory); // Make it absolute

    let mut files = vec![];
    for file in file_args {
        if file.as_bytes().starts_with(b"set:") {
            let message = "fileset";
            return Err(CommandError::unsupported(message));
        }

        let normalized = cwd.join(&file);
        // TODO: actually normalize `..` path segments etc?
        let dotted = normalized.components().any(|c| c.as_os_str() == "..");
        if file.as_bytes() == b"." || dotted {
            let message = "`..` or `.` path segment";
            return Err(CommandError::unsupported(message));
        }
        let relative_path = working_directory
            .strip_prefix(&cwd)
            .unwrap_or(&working_directory);
        let stripped = normalized
            .strip_prefix(&working_directory)
            .map_err(|_| {
                CommandError::abort(format!(
                    "abort: {} not under root '{}'\n(consider using '--cwd {}')",
                    String::from_utf8_lossy(file.as_bytes()),
                    working_directory.display(),
                    relative_path.display(),
                ))
            })?;
        let hg_file = HgPathBuf::try_from(stripped.to_path_buf())
            .map_err(|e| CommandError::abort(e.to_string()))?;
        files.push(hg_file);
    }
    let files = files.iter().map(|file| file.as_ref()).collect();
    // TODO probably move this to a util function like `repo.default_rev` or
    // something when it's used somewhere else
    let rev = match rev {
        Some(r) => r.to_string(),
        None => format!("{:x}", repo.dirstate_parents()?.p1),
    };

    let output = cat(repo, &rev, files).map_err(|e| (e, rev.as_str()))?;
    for (_file, contents) in output.results {
        invocation.ui.write_stdout(&contents)?;
    }
    if !output.missing.is_empty() {
        let short = format!("{:x}", output.node.short()).into_bytes();
        for path in &output.missing {
            invocation.ui.write_stderr(&format_bytes!(
                b"{}: no such file in rev {}\n",
                path.as_bytes(),
                short
            ))?;
        }
    }
    if output.found_any {
        Ok(())
    } else {
        Err(CommandError::Unsuccessful)
    }
}
