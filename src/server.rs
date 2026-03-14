use crate::db::Database;
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::io::{Read, Write};
use std::os::unix::net::UnixListener;
use std::path::PathBuf;
use std::sync::{Arc, Mutex};
use tokio::runtime::Runtime;

pub const SOCKET_NAME: &str = "notebase.sock";

#[derive(Debug, Serialize, Deserialize)]
pub struct Request {
    pub command: String,
    pub args: HashMap<String, String>,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct Response {
    pub success: bool,
    pub data: Option<String>,
    pub error: Option<String>,
}

pub struct ServerState {
    pub db: Database,
    pub runtime: Runtime,
}

pub fn get_socket_path() -> PathBuf {
    let home = std::env::var("HOME").unwrap_or_else(|_| ".".to_string());
    PathBuf::from(home)
        .join(".config")
        .join("notebase")
        .join(SOCKET_NAME)
}

pub fn start_server(db_path: &str) -> Result<(), Box<dyn std::error::Error>> {
    let socket_path = get_socket_path();

    if socket_path.exists() {
        std::fs::remove_file(&socket_path)?;
    }

    if let Some(parent) = socket_path.parent() {
        std::fs::create_dir_all(parent)?;
    }

    let listener = UnixListener::bind(&socket_path)?;
    listener.set_nonblocking(true)?;

    let db = Database::new(db_path)?;
    let runtime = Runtime::new()?;
    let state = Arc::new(Mutex::new(ServerState { db, runtime }));

    println!("Server started at {}", socket_path.display());

    loop {
        match listener.accept() {
            Ok((mut stream, _)) => {
                let mut buffer = vec![0u8; 8192];
                match stream.read(&mut buffer) {
                    Ok(size) => {
                        let request: Request = match serde_json::from_slice(&buffer[..size]) {
                            Ok(r) => r,
                            Err(e) => {
                                let response = Response {
                                    success: false,
                                    data: None,
                                    error: Some(format!("Invalid request: {}", e)),
                                };
                                let _ = stream.write_all(&serde_json::to_vec(&response).unwrap());
                                continue;
                            }
                        };

                        let command = request.command.clone();
                        let response = handle_request(request, &state);
                        if command == "stop" {
                            let _ = std::fs::remove_file(get_socket_path());
                            let response_bytes = serde_json::to_vec(&response).unwrap();
                            let _ = stream.write_all(&response_bytes);
                            println!("Server stopped");
                            return Ok(());
                        }
                        let response_bytes = serde_json::to_vec(&response).unwrap();
                        let _ = stream.write_all(&response_bytes);
                    }
                    Err(e) => {
                        eprintln!("Read error: {}", e);
                    }
                }
            }
            Err(ref e) if e.kind() == std::io::ErrorKind::WouldBlock => {
                std::thread::sleep(std::time::Duration::from_millis(50));
            }
            Err(e) => {
                eprintln!("Accept error: {}", e);
            }
        }
    }
}

fn handle_request(request: Request, state: &Arc<Mutex<ServerState>>) -> Response {
    let state = match state.lock() {
        Ok(s) => s,
        Err(e) => {
            return Response {
                success: false,
                data: None,
                error: Some(format!("Failed to lock state: {}", e)),
            };
        }
    };

    match request.command.as_str() {
        "add" => {
            let content = request.args.get("content").cloned().unwrap_or_default();
            match state.db.add_note(&content, "text") {
                Ok(id) => {
                    if let Err(e) = state
                        .runtime
                        .block_on(state.db.generate_note_embedding(id, &content))
                    {
                        Response {
                            success: true,
                            data: Some(format!(
                                "{{\"id\":{}, \"warning\":\"embedding failed: {}\"}}",
                                id, e
                            )),
                            error: None,
                        }
                    } else {
                        Response {
                            success: true,
                            data: Some(format!(r#"{{"id":{}}}"#, id)),
                            error: None,
                        }
                    }
                }
                Err(e) => Response {
                    success: false,
                    data: None,
                    error: Some(e.to_string()),
                },
            }
        }
        "list" => {
            let limit = request.args.get("limit").and_then(|l| l.parse().ok());
            match state.db.list_notes(limit) {
                Ok(notes) => {
                    let json = serde_json::to_string(&notes).unwrap();
                    Response {
                        success: true,
                        data: Some(json),
                        error: None,
                    }
                }
                Err(e) => Response {
                    success: false,
                    data: None,
                    error: Some(e.to_string()),
                },
            }
        }
        "find" => {
            let query = request.args.get("query").cloned().unwrap_or_default();
            let top_k = request
                .args
                .get("top_k")
                .and_then(|k| k.parse().ok())
                .unwrap_or(5);

            match state.runtime.block_on(state.db.search_notes(&query, top_k)) {
                Ok(results) => {
                    let json = serde_json::to_string(&results).unwrap();
                    Response {
                        success: true,
                        data: Some(json),
                        error: None,
                    }
                }
                Err(e) => Response {
                    success: false,
                    data: None,
                    error: Some(e.to_string()),
                },
            }
        }
        "show" => {
            let id: i64 = match request.args.get("id").and_then(|id| id.parse().ok()) {
                Some(id) => id,
                None => {
                    return Response {
                        success: false,
                        data: None,
                        error: Some("Invalid id".to_string()),
                    };
                }
            };
            match state.db.get_note(id) {
                Ok(note) => {
                    let json = serde_json::to_string(&note).unwrap();
                    Response {
                        success: true,
                        data: Some(json),
                        error: None,
                    }
                }
                Err(e) => Response {
                    success: false,
                    data: None,
                    error: Some(e.to_string()),
                },
            }
        }
        "modify" => {
            let id: i64 = match request.args.get("id").and_then(|id| id.parse().ok()) {
                Some(id) => id,
                None => {
                    return Response {
                        success: false,
                        data: None,
                        error: Some("Invalid id".to_string()),
                    };
                }
            };
            let new_content = request.args.get("new_content").cloned().unwrap_or_default();
            match state.db.update_note(id, &new_content) {
                Ok(true) => Response {
                    success: true,
                    data: Some(r#"{"updated":true}"#.to_string()),
                    error: None,
                },
                Ok(false) => Response {
                    success: false,
                    data: None,
                    error: Some("Note not found".to_string()),
                },
                Err(e) => Response {
                    success: false,
                    data: None,
                    error: Some(e.to_string()),
                },
            }
        }
        "delete" => {
            let id: i64 = match request.args.get("id").and_then(|id| id.parse().ok()) {
                Some(id) => id,
                None => {
                    return Response {
                        success: false,
                        data: None,
                        error: Some("Invalid id".to_string()),
                    };
                }
            };
            match state.db.delete_note(id) {
                Ok(true) => Response {
                    success: true,
                    data: Some(r#"{"deleted":true}"#.to_string()),
                    error: None,
                },
                Ok(false) => Response {
                    success: false,
                    data: None,
                    error: Some("Note not found".to_string()),
                },
                Err(e) => Response {
                    success: false,
                    data: None,
                    error: Some(e.to_string()),
                },
            }
        }
        "status" => Response {
            success: true,
            data: Some(r#"{"status":"running"}"#.to_string()),
            error: None,
        },
        "stop" => Response {
            success: true,
            data: Some("Server stopped".to_string()),
            error: None,
        },
        _ => Response {
            success: false,
            data: None,
            error: Some(format!("Unknown command: {}", request.command)),
        },
    }
}
