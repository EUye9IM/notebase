use rusqlite::{Connection, Result, params};
use serde::{Deserialize, Serialize};

#[allow(dead_code)]
pub const VECTOR_DIMENSION: usize = 2560;

#[derive(Debug, Serialize, Deserialize, Clone)]
pub struct Note {
    pub id: i64,
    pub content: String,
    pub content_type: String,
    pub created_at: String,
    pub updated_at: String,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct Embedding {
    pub id: i64,
    pub note_id: i64,
    pub vector: Vec<f32>,
}

pub struct Database {
    conn: Connection,
}

impl Database {
    pub fn new(path: &str) -> Result<Self> {
        let conn = Connection::open(path)?;
        let db = Database { conn };
        db.init_tables()?;
        Ok(db)
    }

    fn init_tables(&self) -> Result<()> {
        self.conn.execute(
            "CREATE TABLE IF NOT EXISTS notes (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                content TEXT NOT NULL,
                content_type TEXT NOT NULL DEFAULT 'text',
                created_at TEXT NOT NULL DEFAULT (datetime('now')),
                updated_at TEXT NOT NULL DEFAULT (datetime('now'))
            )",
            [],
        )?;

        self.conn.execute(
            "CREATE TABLE IF NOT EXISTS embeddings (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                note_id INTEGER NOT NULL,
                vector BLOB NOT NULL,
                FOREIGN KEY (note_id) REFERENCES notes(id) ON DELETE CASCADE
            )",
            [],
        )?;

        self.conn.execute(
            "CREATE INDEX IF NOT EXISTS idx_embeddings_note_id ON embeddings(note_id)",
            [],
        )?;

        Ok(())
    }

    pub fn add_note(&self, content: &str, content_type: &str) -> Result<i64> {
        self.conn.execute(
            "INSERT INTO notes (content, content_type) VALUES (?1, ?2)",
            params![content, content_type],
        )?;
        Ok(self.conn.last_insert_rowid())
    }

    pub fn get_note(&self, id: i64) -> Result<Option<Note>> {
        let mut stmt = self.conn.prepare(
            "SELECT id, content, content_type, created_at, updated_at FROM notes WHERE id = ?1",
        )?;

        let mut rows = stmt.query(params![id])?;

        if let Some(row) = rows.next()? {
            Ok(Some(Note {
                id: row.get(0)?,
                content: row.get(1)?,
                content_type: row.get(2)?,
                created_at: row.get(3)?,
                updated_at: row.get(4)?,
            }))
        } else {
            Ok(None)
        }
    }

    pub fn list_notes(&self, limit: Option<usize>) -> Result<Vec<Note>> {
        let limit = limit.unwrap_or(10);
        let mut stmt = self.conn.prepare(
            "SELECT id, content, content_type, created_at, updated_at 
             FROM notes ORDER BY created_at DESC LIMIT ?1",
        )?;

        let notes = stmt
            .query_map(params![limit], |row| {
                Ok(Note {
                    id: row.get(0)?,
                    content: row.get(1)?,
                    content_type: row.get(2)?,
                    created_at: row.get(3)?,
                    updated_at: row.get(4)?,
                })
            })?
            .collect::<Result<Vec<_>>>()?;

        Ok(notes)
    }

    pub fn update_note(&self, id: i64, new_content: &str) -> Result<bool> {
        let rows = self.conn.execute(
            "UPDATE notes SET content = ?1, updated_at = datetime('now') WHERE id = ?2",
            params![new_content, id],
        )?;
        Ok(rows > 0)
    }

    pub fn delete_note(&self, id: i64) -> Result<bool> {
        self.conn
            .execute("DELETE FROM embeddings WHERE note_id = ?1", params![id])?;
        let rows = self
            .conn
            .execute("DELETE FROM notes WHERE id = ?1", params![id])?;
        Ok(rows > 0)
    }

    #[allow(dead_code)]
    pub fn add_embedding(&self, note_id: i64, vector: &[f32]) -> Result<i64> {
        let vector_bytes: Vec<u8> = vector.iter().flat_map(|f| f.to_le_bytes()).collect();

        self.conn.execute(
            "INSERT INTO embeddings (note_id, vector) VALUES (?1, ?2)",
            params![note_id, vector_bytes],
        )?;
        Ok(self.conn.last_insert_rowid())
    }

    #[allow(dead_code)]
    pub fn get_embedding(&self, note_id: i64) -> Result<Option<Embedding>> {
        let mut stmt = self
            .conn
            .prepare("SELECT id, note_id, vector FROM embeddings WHERE note_id = ?1")?;

        let mut rows = stmt.query(params![note_id])?;

        if let Some(row) = rows.next()? {
            let vector_bytes: Vec<u8> = row.get(2)?;
            let vector: Vec<f32> = vector_bytes
                .chunks_exact(4)
                .map(|chunk| f32::from_le_bytes([chunk[0], chunk[1], chunk[2], chunk[3]]))
                .collect();

            Ok(Some(Embedding {
                id: row.get(0)?,
                note_id: row.get(1)?,
                vector,
            }))
        } else {
            Ok(None)
        }
    }

    pub fn get_all_embeddings(&self) -> Result<Vec<Embedding>> {
        let mut stmt = self
            .conn
            .prepare("SELECT id, note_id, vector FROM embeddings")?;

        let embeddings = stmt
            .query_map([], |row| {
                let vector_bytes: Vec<u8> = row.get(2)?;
                let vector: Vec<f32> = vector_bytes
                    .chunks_exact(4)
                    .map(|chunk| f32::from_le_bytes([chunk[0], chunk[1], chunk[2], chunk[3]]))
                    .collect();

                Ok(Embedding {
                    id: row.get(0)?,
                    note_id: row.get(1)?,
                    vector,
                })
            })?
            .collect::<Result<Vec<_>>>()?;

        Ok(embeddings)
    }

    #[allow(dead_code)]
    pub fn delete_embedding(&self, note_id: i64) -> Result<bool> {
        let rows = self.conn.execute(
            "DELETE FROM embeddings WHERE note_id = ?1",
            params![note_id],
        )?;
        Ok(rows > 0)
    }
}

pub fn cosine_similarity(a: &[f32], b: &[f32]) -> f32 {
    if a.len() != b.len() || a.is_empty() {
        return 0.0;
    }

    let dot: f32 = a.iter().zip(b.iter()).map(|(x, y)| x * y).sum();
    let norm_a: f32 = a.iter().map(|x| x * x).sum::<f32>().sqrt();
    let norm_b: f32 = b.iter().map(|x| x * x).sum::<f32>().sqrt();

    if norm_a == 0.0 || norm_b == 0.0 {
        return 0.0;
    }

    dot / (norm_a * norm_b)
}

#[derive(Debug, Serialize, Deserialize)]
pub struct SearchResult {
    pub note: Note,
    pub similarity: f32,
}

impl Database {
    #[allow(dead_code)]
    pub async fn generate_note_embedding(
        &self,
        note_id: i64,
        content: &str,
    ) -> Result<(), Box<dyn std::error::Error>> {
        use crate::embedding::generate_embeddings;

        let embeddings = generate_embeddings(&[content]).await?;

        if embeddings.is_empty() {
            return Err("No embedding generated".into());
        }

        self.add_embedding(note_id, &embeddings[0])?;
        Ok(())
    }

    pub async fn search_notes(
        &self,
        query: &str,
        top_k: usize,
    ) -> Result<Vec<SearchResult>, Box<dyn std::error::Error>> {
        use crate::embedding::generate_embeddings;

        let query_embedding = generate_embeddings(&[query]).await?;

        if query_embedding.is_empty() {
            return Err("Failed to generate query embedding".into());
        }

        let embeddings = self.get_all_embeddings()?;
        let notes_map: std::collections::HashMap<i64, Note> = embeddings
            .iter()
            .filter_map(|e| {
                self.get_note(e.note_id)
                    .ok()
                    .flatten()
                    .map(|note| (e.note_id, note))
            })
            .collect();

        let mut results: Vec<(i64, f32)> = embeddings
            .iter()
            .map(|emb| {
                let sim = cosine_similarity(&query_embedding[0], &emb.vector);
                (emb.note_id, sim)
            })
            .filter(|(_, sim)| *sim > 0.0)
            .collect();

        results.sort_by(|a, b| b.1.partial_cmp(&a.1).unwrap_or(std::cmp::Ordering::Equal));
        results.truncate(top_k);

        let search_results = results
            .into_iter()
            .filter_map(|(note_id, similarity)| {
                notes_map.get(&note_id).map(|note| SearchResult {
                    note: note.clone(),
                    similarity,
                })
            })
            .collect();

        Ok(search_results)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::fs;

    #[test]
    fn test_database_operations() {
        let path = "/tmp/test_notebase.db";
        let _ = fs::remove_file(path);

        let db = Database::new(path).unwrap();

        let note_id = db.add_note("test content", "text").unwrap();
        assert!(note_id > 0);

        let note = db.get_note(note_id).unwrap();
        assert!(note.is_some());
        assert_eq!(note.unwrap().content, "test content");

        let notes = db.list_notes(Some(5)).unwrap();
        assert_eq!(notes.len(), 1);

        let updated = db.update_note(note_id, "new content").unwrap();
        assert!(updated);

        let note = db.get_note(note_id).unwrap();
        assert_eq!(note.unwrap().content, "new content");

        let deleted = db.delete_note(note_id).unwrap();
        assert!(deleted);

        let note = db.get_note(note_id).unwrap();
        assert!(note.is_none());

        let _ = fs::remove_file(path);
    }

    #[test]
    fn test_cosine_similarity() {
        let a = vec![1.0, 0.0, 0.0];
        let b = vec![1.0, 0.0, 0.0];
        let c = vec![0.0, 1.0, 0.0];
        let d = vec![0.0, 0.0, 0.0];

        assert!((cosine_similarity(&a, &b) - 1.0).abs() < 1e-6);
        assert!(cosine_similarity(&a, &c).abs() < 1e-6);
        assert!(cosine_similarity(&a, &d).abs() < 1e-6);
    }
}
