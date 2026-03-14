mod cli;
mod client;
mod db;
mod embedding;
mod server;

use cli::{Cli, Parser};
use client::{is_server_running, send_command_and_print, send_command_and_print_result};
use db::Database;
use std::collections::HashMap;
use std::path::{Path, PathBuf};

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
        cli::Command::Serve => {
            if is_server_running() {
                println!("Server is already running");
                return;
            }
            if let Err(e) = server::start_server(db_path.to_str().unwrap()) {
                eprintln!("Failed to start server: {}", e);
                std::process::exit(1);
            }
        }
        cli::Command::Status => {
            if is_server_running() {
                let args = HashMap::new();
                if let Err(e) = send_command_and_print_result("status", args) {
                    if e.contains("Connection refused") {
                        println!("Server not responding, removing stale socket...");
                        let _ = std::fs::remove_file(server::get_socket_path());
                        println!("Server is not running");
                    } else {
                        eprintln!("{}", e);
                    }
                }
            } else {
                println!("Server is not running");
            }
        }
        cli::Command::Stop => {
            if is_server_running() {
                let args = HashMap::new();
                if let Err(e) = send_command_and_print_result("stop", args) {
                    if e.contains("Connection refused") {
                        println!("Server not responding, removing stale socket...");
                        let _ = std::fs::remove_file(server::get_socket_path());
                    } else {
                        eprintln!("{}", e);
                    }
                }
            } else {
                println!("Server is not running");
            }
        }
        _ => {
            if is_server_running() {
                handle_via_server(&cli);
            } else {
                handle_local(&cli, &db_path);
            }
        }
    }
}

fn handle_via_server(cli: &Cli) {
    match &cli.command {
        cli::Command::Add { content } => {
            let mut args = HashMap::new();
            args.insert("content".to_string(), content.clone());
            send_command_and_print("add", args);
        }
        cli::Command::List { limit } => {
            let mut args = HashMap::new();
            if let Some(l) = limit {
                args.insert("limit".to_string(), l.to_string());
            }
            send_command_and_print("list", args);
        }
        cli::Command::Find { query, top_k } => {
            let mut args = HashMap::new();
            args.insert("query".to_string(), query.clone());
            if let Some(k) = top_k {
                args.insert("top_k".to_string(), k.to_string());
            }
            send_command_and_print("find", args);
        }
        cli::Command::Show { id } => {
            let mut args = HashMap::new();
            args.insert("id".to_string(), id.clone());
            send_command_and_print("show", args);
        }
        cli::Command::Modify { id, new_content } => {
            let mut args = HashMap::new();
            args.insert("id".to_string(), id.clone());
            args.insert("new_content".to_string(), new_content.clone());
            send_command_and_print("modify", args);
        }
        cli::Command::Delete { id } => {
            let mut args = HashMap::new();
            args.insert("id".to_string(), id.clone());
            send_command_and_print("delete", args);
        }
        _ => {}
    }
}

fn handle_local(cli: &Cli, db_path: &Path) {
    match &cli.command {
        cli::Command::Add { content } => {
            let id = {
                let db = Database::new(db_path.to_str().unwrap()).expect("Failed to open database");
                db.add_note(content, "text").expect("Failed to add note")
            };

            if let Err(e) = tokio::runtime::Runtime::new().unwrap().block_on(async {
                let db = Database::new(db_path.to_str().unwrap()).expect("Failed to open database");
                db.generate_note_embedding(id, content).await
            }) {
                eprintln!("Warning: Failed to generate embedding: {}", e);
                println!("Added note with id: {}", id);
            } else {
                println!("Added note with id: {} (embedding generated)", id);
            }
        }
        cli::Command::List { limit } => {
            let db = Database::new(db_path.to_str().unwrap()).expect("Failed to open database");
            let notes = db.list_notes(*limit).expect("Failed to list notes");
            for note in notes {
                println!("[{}] {} - {}", note.id, note.content, note.created_at);
            }
        }
        cli::Command::Find { query, top_k } => {
            let top_k = top_k.unwrap_or(5);
            let query = query.clone();
            let db_path = db_path.to_path_buf();

            match tokio::runtime::Runtime::new().unwrap().block_on(async {
                let db = Database::new(db_path.to_str().unwrap()).expect("Failed to open database");
                db.search_notes(&query, top_k).await
            }) {
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
            match db.update_note(note_id, new_content) {
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
            println!("Starting server...");
            if let Err(e) = server::start_server(db_path.to_str().unwrap()) {
                eprintln!("Failed to start server: {}", e);
            }
        }
        cli::Command::Status => {
            println!("Server is not running");
        }
        cli::Command::Stop => {
            println!("Server is not running");
        }
    }
}
