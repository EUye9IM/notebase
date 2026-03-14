use crate::server::{Request, Response, get_socket_path};
use std::collections::HashMap;
use std::io::Write;
use std::os::unix::net::UnixStream;

pub fn is_server_running() -> bool {
    get_socket_path().exists()
}

pub fn send_request(command: &str, args: HashMap<String, String>) -> Result<Response, String> {
    let socket_path = get_socket_path();

    let mut stream = UnixStream::connect(&socket_path)
        .map_err(|e| format!("Failed to connect to server: {}", e))?;

    let request = Request {
        command: command.to_string(),
        args,
    };

    let request_bytes =
        serde_json::to_vec(&request).map_err(|e| format!("Failed to serialize request: {}", e))?;

    stream
        .write_all(&request_bytes)
        .map_err(|e| format!("Failed to send request: {}", e))?;

    let mut response_bytes = Vec::new();
    use std::io::Read;
    stream
        .read_to_end(&mut response_bytes)
        .map_err(|e| format!("Failed to read response: {}", e))?;

    let response: Response = serde_json::from_slice(&response_bytes)
        .map_err(|e| format!("Failed to parse response: {}", e))?;

    Ok(response)
}

pub fn send_command_and_print(command: &str, args: HashMap<String, String>) {
    if let Err(e) = send_command_and_print_result(command, args) {
        eprintln!("{}", e);
        std::process::exit(1);
    }
}

pub fn send_command_and_print_result(
    command: &str,
    args: HashMap<String, String>,
) -> Result<(), String> {
    match send_request(command, args) {
        Ok(response) => {
            if response.success {
                if let Some(data) = response.data {
                    println!("{}", data);
                }
                Ok(())
            } else {
                Err(response.error.unwrap_or_default())
            }
        }
        Err(e) => Err(format!("Failed to communicate with server: {}", e)),
    }
}
