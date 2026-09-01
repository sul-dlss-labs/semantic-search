# semantic-search
Developing semantic search for SUL


## Goal

We are attempting to create a semantic search prototype.

This currently depends on https://github.com/sul-dlss-labs/sdr-harvest for creating the index (and the solr config)

### Run the webapp
```
cd webapp
LITELLM_API_KEY=<key> bin/rails dev
```

### MCP server

The Rails application exposes a Model Context Protocol endpoint at:

```text
POST http://localhost:3000/mcp
Content-Type: application/json
```

The `catalog_search_tool` searches the catalog with `keyword`, `vector`, or
`hybrid` search (the default). It accepts an optional result count and filters
derived from the catalog's configured facets.

To list the available tools:

```bash
curl -X POST http://localhost:3000/mcp \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":"1","method":"tools/list"}'
```

To search the catalog:

```bash
curl -X POST http://localhost:3000/mcp \
  -H "Content-Type: application/json" \
  -d '{
    "jsonrpc": "2.0",
    "id": "2",
    "method": "tools/call",
    "params": {
      "name": "catalog_search_tool",
      "arguments": {
        "query": "historic maps",
        "search_type": "hybrid",
        "rows": 5
      }
    }
  }'
```

## Deployment

The github workflow will build the docker image on each commit.

See https://docs.github.com/en/packages/working-with-a-github-packages-registry/working-with-the-container-registry

We deploy with kamal.

  * Get a GitHub token.
  * cd 'webapp'
  * Authenticate with kerberos: `kinit`
  * Get a one time key: `./bin/setup-otk`
  * Login to vault (use SSO): `vault login -method oidc`
  * Deploy: `KAMAL_REGISTRY_USERNAME=jcoyne \
    KAMAL_REGISTRY_PASSWORD=<github token> \
    KAMAL_OTK_KEY=~/.ssh/id_kamal_otk \
    bin/kamal deploy-main`
