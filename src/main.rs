mod cli;
mod db;
mod embedding;

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
            
            if let Err(e) = tokio::runtime::Runtime::new()
                .unwrap()
                .block_on(db.generate_note_embedding(id, &content))
            {
                eprintln!("Warning: Failed to generate embedding: {}", e);
            } else {
                println!("Added note with id: {} (embedding generated)", id);
            }
        }
        cli::Command::List { limit } => {
            let db = Database::new(db_path.to_str().unwrap()).expect("Failed to open database");
            let notes = db.list_notes(limit).expect("Failed to list notes");
            for note in notes {
                println!("[{}] {} - {}", note.id, note.content, note.created_at);
            }
        }
        cli::Command::Find { query, top_k } => {
            let db = Database::new(db_path.to_str().unwrap()).expect("Failed to open database");
            let top_k = top_k.unwrap_or(5);

            match tokio::runtime::Runtime::new()
                .unwrap()
                .block_on(db.search_notes(&query, top_k))
            {
                Ok(results) => {
                    if results.is_empty() {
                        println!("No matching notes found");
                    } else {
                        println!("Found {} matching notes:", results.len());
                        for result in results {
                            println!(
                                "[{}] (similarity: {:.4}) {}",
                                result.note.id, result.similarity, result.note.content
                            );
                        }
                    }
                }
                Err(e) => println!("Error searching notes: {}", e),
            }
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
