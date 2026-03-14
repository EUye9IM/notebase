# AGENTS.md - Notebase Development Guide

This document provides guidelines for AI agents working on the notebase codebase.

## Project Overview

Notebase is a Rust-based note-taking CLI application with RAG (Retrieval-Augmented Generation) capabilities. It uses SQLite for storage, clap for CLI parsing, and serde for serialization.

## Build Commands

```bash
# Build the project
cargo build

# Build in release mode
cargo build --release

# Run the application
cargo run -- [args]

# Run with debug output
RUST_BACKTRACE=1 cargo run -- [args]
```

## Linting & Code Quality

```bash
# Run clippy for linting
cargo clippy

# Run clippy with all warnings as errors
cargo clippy -- -D warnings

# Format code
cargo fmt

# Check formatting
cargo fmt -- --check

# Run all checks (fmt + clippy)
cargo check
```

## Testing

```bash
# Run all tests
cargo test

# Run tests with output
cargo test -- --nocapture

# Run a single test by name
cargo test test_database_operations
cargo test test_cosine_similarity
cargo test test_add_command

# Run tests in a specific module
cargo test db::tests
cargo test cli::tests

# Run doc tests
cargo test --doc

# Run tests with logging
RUST_LOG=debug cargo test
```

## Code Style Guidelines

### Formatting

- Use `cargo fmt` for automatic formatting
- Maximum line width: 100 characters (default)
- Use 4 spaces for indentation (Rust standard)

### Imports

- Group imports: std → external crates → local modules
- Use explicit imports: `use std::path::PathBuf;`
- Avoid wildcard imports except for test modules

### Naming Conventions

- **Types**: PascalCase (`Database`, `Command`, `Note`)
- **Functions & Methods**: snake_case (`get_db_path`, `add_note`)
- **Variables**: snake_case (`db_path`, `note_id`)
- **Constants**: SCREAMING_SNAKE_CASE (`VECTOR_DIMENSION`)
- **Modules**: snake_case (`cli`, `db`)

### Type Annotations

- Specify types in function signatures for public APIs
- Use generic types with clear trait bounds
- Example: `pub fn add_note(&self, content: &str) -> Result<i64>`

### Error Handling

- Use `rusqlite::Result<T>` for database operations
- Use `?` operator for error propagation
- Use `expect()` only for unrecoverable errors (e.g., CLI parsing)

### Structs & Enums

- Use `#[derive(Debug, Clone, Serialize, Deserialize)]` for data structures
- Use `#[derive(Parser, Subcommand)]` for CLI types
- Example:
  ```rust
  #[derive(Debug, Serialize, Deserialize, Clone)]
  pub struct Note {
      pub id: i64,
      pub content: String,
      pub content_type: String,
      pub created_at: String,
      pub updated_at: String,
  }
  ```

### Database Operations

- Use parameterized queries with `params![]` macro
- Handle `Option<T>` for nullable fields (e.g., `get_note` returns `Result<Option<Note>>`)

### Testing

- Place unit tests in `#[cfg(test)]` modules within each source file
- Use descriptive test names: `test_add_command`, `test_database_operations`
- Clean up test files using `/tmp/` or temp directories
- Example:
  ```rust
  #[cfg(test)]
  mod tests {
      use super::*;
      
      #[test]
      fn test_cosine_similarity() {
          let a = vec![1.0, 0.0, 0.0];
          let b = vec![1.0, 0.0, 0.0];
          assert!((cosine_similarity(&a, &b) - 1.0).abs() < 1e-6);
      }
  }
  ```

### CLI Design (using clap)

- Use `#[derive(Parser)]` for CLI struct
- Use `#[derive(Subcommand)]` for commands
- Add doc comments for command help text

## Project Structure

```
notebase/
├── src/
│   ├── main.rs       # Entry point, command dispatch
│   ├── cli.rs        # CLI argument parsing
│   └── db.rs         # Database operations, models
├── Cargo.toml        # Project configuration
└── Cargo.lock        # Dependency lock file
```

## Common Development Tasks

```bash
# Add a new dependency
cargo add <crate>

# Update dependencies
cargo update

# View dependency tree
cargo tree

# Generate documentation
cargo doc --open
```

## Pre-commit Checklist

Before submitting code:
1. Run `cargo fmt`
2. Run `cargo clippy -- -D warnings`
3. Run `cargo test`
4. Verify build with `cargo build --release`
