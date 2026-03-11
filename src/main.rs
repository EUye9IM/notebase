mod cli;

use cli::{Cli, Parser};

fn main() {
    let cli = Cli::parse();
    match cli.command {
        cli::Command::Add { content } => {
            println!("Add note with content: {}", content);
        }
        cli::Command::List { limit } => {
            println!("List notes with limit: {:?}", limit);
        }
        cli::Command::Find { query, top_k } => {
            println!("Find with query: {}, top_k: {:?}", query, top_k);
        }
        cli::Command::Show { id } => {
            println!("Show note with id: {}", id);
        }
        cli::Command::Modify { id, new_content } => {
            println!("Modify note {} with new content: {}", id, new_content);
        }
        cli::Command::Delete { id } => {
            println!("Delete note with id: {}", id);
        }
        cli::Command::Serve => {
            println!("Start daemon");
        }
        cli::Command::Status => {
            println!("Check daemon status");
        }
        cli::Command::Stop => {
            println!("Stop daemon");
        }
    }
}
