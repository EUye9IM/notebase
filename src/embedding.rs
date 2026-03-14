use serde::{Deserialize, Serialize};
use std::env;

#[derive(Debug, Serialize)]
pub struct EmbedRequest {
    pub model: String,
    pub input: Vec<String>,
}

#[derive(Debug, Deserialize)]
pub struct EmbedResponse {
    pub embeddings: Vec<Vec<f32>>,
}

#[derive(Debug, thiserror::Error)]
pub enum EmbedError {
    #[error("HTTP error: {0}")]
    HttpError(#[from] reqwest::Error),
    #[error("JSON error: {0}")]
    JsonError(#[from] serde_json::Error),
    #[error("API error: {0}")]
    ApiError(String),
    #[error("Empty embeddings returned")]
    EmptyEmbeddings,
}

pub type Result<T> = std::result::Result<T, EmbedError>;

pub async fn generate_embeddings(texts: &[&str]) -> Result<Vec<Vec<f32>>> {
    let model = env::var("OLLAMA_MODEL").unwrap_or_else(|_| "qwen3-embedding:4b".to_string());
    let base_url =
        env::var("OLLAMA_BASE_URL").unwrap_or_else(|_| "http://localhost:11434".to_string());

    let client = reqwest::Client::new();
    let url = format!("{}/api/embed", base_url);

    let request = EmbedRequest {
        model,
        input: texts.iter().map(|s| s.to_string()).collect(),
    };

    let response = client.post(&url).json(&request).send().await?;

    if !response.status().is_success() {
        let error_text = response.text().await.unwrap_or_default();
        return Err(EmbedError::ApiError(error_text));
    }

    let embed_response: EmbedResponse = response.json().await?;

    if embed_response.embeddings.is_empty() {
        return Err(EmbedError::EmptyEmbeddings);
    }

    Ok(embed_response.embeddings)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_embed_request_serialization() {
        let request = EmbedRequest {
            model: "test-model".to_string(),
            input: vec!["hello".to_string(), "world".to_string()],
        };

        let json = serde_json::to_string(&request).unwrap();
        assert!(json.contains("test-model"));
        assert!(json.contains("hello"));
        assert!(json.contains("world"));
    }
}
