mod cli;
mod db;

use cli::{Cli, Parser};
use db::Database;
use std::path::PathBuf;

fn get_db_path() -> PathBuf {
    let home = std::env::var("HOME").unwrap_or_else(|_| ".".to_string());
    let config_dir = PathBuf::from(home).join(".config").join("notebase");
    std::fs::create_dir_all(&config_dir).ok();
    config_dir.join("notebase.db")
}

fn main() {
    let cli = Cli::parse();
    let db_path = get_db_path();

    match cli.command {
        cli::Command::Add { content } => {
            let db = Database::new(db_path.to_str().unwrap()).expect("Failed to open database");
            let id = db.add_note(&content, "text").expect("Failed to add note");
            println!("Added note with id: {}", id);
        }
        cli::Command::List { limit } => {
            let db = Database::new(db_path.to_str().unwrap()).expect("Failed to open database");
            let notes = db.list_notes(limit).expect("Failed to list notes");
            for note in notes {
                println!("[{}] {} - {}", note.id, note.content, note.created_at);
            }
        }
        cli::Command::Find { query, top_k } => {
            println!("Find with query: {}, top_k: {:?}", query, top_k);
            println!("(Not implemented yet - requires embedding service)");
        }
        cli::Command::Show { id } => {
            let db = Database::new(db_path.to_str().unwrap()).expect("Failed to open database");
            let note_id: i64 = id.parse().expect("Invalid note id");
            match db.get_note(note_id) {
                Ok(Some(note)) => {
                    println!("ID: {}", note.id);
                    println!("Content: {}", note.content);
                    println!("Type: {}", note.content_type);
                    println!("Created: {}", note.created_at);
                    println!("Updated: {}", note.updated_at);
                }
                Ok(None) => println!("Note not found"),
                Err(e) => println!("Error: {}", e),
            }
        }
        cli::Command::Modify { id, new_content } => {
            let db = Database::new(db_path.to_str().unwrap()).expect("Failed to open database");
            let note_id: i64 = id.parse().expect("Invalid note id");
            match db.update_note(note_id, &new_content) {
                Ok(true) => println!("Updated note {}", note_id),
                Ok(false) => println!("Note not found"),
                Err(e) => println!("Error: {}", e),
            }
        }
        cli::Command::Delete { id } => {
            let db = Database::new(db_path.to_str().unwrap()).expect("Failed to open database");
            let note_id: i64 = id.parse().expect("Invalid note id");
            match db.delete_note(note_id) {
                Ok(true) => println!("Deleted note {}", note_id),
                Ok(false) => println!("Note not found"),
                Err(e) => println!("Error: {}", e),
            }
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
