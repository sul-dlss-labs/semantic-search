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

## Chat configuration

The `/chat` page uses the same LiteLLM proxy through its OpenAI-compatible streaming
`POST /v1/chat/completions` endpoint. In addition to `LITELLM_API_BASE` and
`LITELLM_API_KEY`, configure:

- `LITELLM_CHAT_MODEL`: the LiteLLM model alias used for chat completions. The model
  must support OpenAI-compatible tool calling and streaming.

The system prompt and conversation, tool, and output limits are server-controlled Rails settings
under `config.x.chat` in `config/application.rb`. The assistant can invoke only this
application's read-only MCP tool definitions. Conversations are held in the browser
and are not persisted by Rails.

Each MCP tool invocation writes two structured log events. `start.mcp_tool` records
the tool name and input immediately before execution; `call.mcp_tool` records its
outcome, duration, and bounded result metadata afterward. Both include the Rails
request ID for correlation.
