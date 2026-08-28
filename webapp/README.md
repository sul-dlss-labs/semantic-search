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

## Chat quality evaluations

The black-box evaluation task asks the deployed `/chat` endpoint a set of questions,
then uses an independent LiteLLM model to judge each answer against a semantic reference
answer and rubric. It also verifies that cases marked `require_citations` return at least
one verified source with a clickable HTTP(S) URL. Cases live in
`lib/chat_evaluation/chat_evaluations.yml`; ordinary test runs do not make network requests.

Configure the standard `LITELLM_API_BASE` and `LITELLM_API_KEY` variables, then run:

```sh
LITELLM_EVAL_MODEL=claude-sonnet-5 \
  bin/rails chat:evaluate
```

The target defaults to `https://semantic-search-demo.stanford.edu`. Useful overrides are:

- `CHAT_EVAL_TARGET_URL`: deployment to test
- `CHAT_EVAL_CASE`: run only one case ID
- `CHAT_EVAL_RUNS`: attempts per case (default `1`)
- `CHAT_EVAL_PASS_RATE`: required fraction of passing attempts (default `1.0`)
- `CHAT_EVAL_MIN_SCORE`: minimum judge score (default `0.8`)
- `CHAT_EVAL_REPORT`: output JSON path; otherwise reports go under `tmp/chat_evaluations`

For a less noisy periodic regression check, three attempts with two required passes can
be run as:

```sh
CHAT_EVAL_RUNS=3 CHAT_EVAL_PASS_RATE=0.66 \
LITELLM_EVAL_MODEL=claude-sonnet-5 \
  bin/rails chat:evaluate
```

To exercise the Mount Damavand retrieval regression repeatedly in both fresh and retry
contexts, run:

```sh
CHAT_EVAL_CASE=kathleen_namphy_mount_damavand CHAT_EVAL_RUNS=5 \
LITELLM_EVAL_MODEL=claude-sonnet-5 bin/rails chat:evaluate

CHAT_EVAL_CASE=kathleen_namphy_retry_after_miss CHAT_EVAL_RUNS=5 \
LITELLM_EVAL_MODEL=claude-sonnet-5 bin/rails chat:evaluate
```

## Deployment

After the Docker GitHub Actions workflow has successfully built and published the
current commit using its short SHA tag, deploy that CI-built image with the following process.

Get a one-time-key
```sh
./bin/setup-otk
```

Sign into vault
```sh
vault login -method oidc
```

Then run kamal deploy
```sh
VERSION="$(git rev-parse --short=7 HEAD)" \
KAMAL_REGISTRY_USERNAME=<github user> \
KAMAL_REGISTRY_PASSWORD=<github token> \
KAMAL_OTK_KEY=~/.ssh/id_kamal_otk \
  bin/kamal deploy --skip-push
```
