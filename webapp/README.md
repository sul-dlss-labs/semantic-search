# Semantic Search Webapp

## Embedding configuration

Embedding requests are sent to a [LiteLLM proxy](https://docs.litellm.ai/blog/gemini_embedding_2_ga)
using its OpenAI-compatible `POST /v1/embeddings` endpoint. Configure:

- `LITELLM_API_BASE`: proxy API base URL, with or without `/v1` (production uses
  `https://dlss-aigateway-prod.stanford.edu/v1/`)
- `LITELLM_API_KEY`: proxy master or virtual key
- `LITELLM_EMBEDDING_MODEL`: optional proxy model alias; defaults to `gemini-embedding-2`

The configured LiteLLM proxy must expose that alias for `gemini/gemini-embedding-2`.
The application requests 768-dimensional embeddings to match the Solr vector field.
