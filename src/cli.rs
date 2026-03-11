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
