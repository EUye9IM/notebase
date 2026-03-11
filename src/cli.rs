pub use clap::{Parser, Subcommand};

#[derive(Parser)]
#[command(
    name = "nb",
    about = "Notebase - a Rust-based note library with RAG",
    version
)]
pub struct Cli {
    #[command(subcommand)]
    pub command: Command,
}

#[derive(Subcommand)]
pub enum Command {
    /// Add a note (file or direct text)
    Add {
        /// Path to file or direct text content
        content: String,
    },
    /// List recent notes
    List {
        /// Maximum number of notes to list
        #[arg(short, long)]
        limit: Option<usize>,
    },
    /// Natural language search
    Find {
        /// Query string
        query: String,
        /// Number of top results to return
        #[arg(short = 'k', long)]
        top_k: Option<usize>,
    },
    /// Show note details
    Show {
        /// Note ID
        id: String,
    },
    /// Modify a note
    #[command(name = "mod")]
    Modify {
        /// Note ID
        id: String,
        /// New content
        new_content: String,
    },
    /// Delete a note
    Delete {
        /// Note ID
        id: String,
    },
    /// Start background daemon (if not running)
    Serve,
    /// Check daemon status
    Status,
    /// Stop daemon
    Stop,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_add_command() {
        let cli = Cli::try_parse_from(["nb", "add", "hello"]).unwrap();
        assert!(matches!(cli.command, Command::Add { content } if content == "hello"));
    }

    #[test]
    fn test_list_with_limit() {
        let cli = Cli::try_parse_from(["nb", "list", "--limit", "10"]).unwrap();
        assert!(matches!(cli.command, Command::List { limit: Some(10) }));
    }

    #[test]
    fn test_list_default_limit() {
        let cli = Cli::try_parse_from(["nb", "list"]).unwrap();
        assert!(matches!(cli.command, Command::List { limit: None }));
    }

    #[test]
    fn test_find_with_top_k() {
        let cli = Cli::try_parse_from(["nb", "find", "query", "-k", "5"]).unwrap();
        assert!(matches!(cli.command, Command::Find { query, top_k: Some(5) } if query == "query"));
    }

    #[test]
    fn test_show_command() {
        let cli = Cli::try_parse_from(["nb", "show", "abc123"]).unwrap();
        assert!(matches!(cli.command, Command::Show { id } if id == "abc123"));
    }

    #[test]
    fn test_modify_command() {
        let cli = Cli::try_parse_from(["nb", "mod", "123", "new content"]).unwrap();
        assert!(
            matches!(cli.command, Command::Modify { id, new_content } if id == "123" && new_content == "new content")
        );
    }

    #[test]
    fn test_delete_command() {
        let cli = Cli::try_parse_from(["nb", "delete", "456"]).unwrap();
        assert!(matches!(cli.command, Command::Delete { id } if id == "456"));
    }

    #[test]
    fn test_serve_command() {
        let cli = Cli::try_parse_from(["nb", "serve"]).unwrap();
        assert!(matches!(cli.command, Command::Serve));
    }

    #[test]
    fn test_status_command() {
        let cli = Cli::try_parse_from(["nb", "status"]).unwrap();
        assert!(matches!(cli.command, Command::Status));
    }

    #[test]
    fn test_stop_command() {
        let cli = Cli::try_parse_from(["nb", "stop"]).unwrap();
        assert!(matches!(cli.command, Command::Stop));
    }
}
