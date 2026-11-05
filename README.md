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

We deploy to semantic-search-demo.stanford.edu with [Kamal](https://kamal-deploy.org). The image is
built on the demo server itself and passed through Kamal's local registry, so no registry credentials
are needed.

### Continuous deployment

Jenkins deploys every merge to `main` (see `Jenkinsfile`), using the `jenkinsqa@sul-ci-prod` SSH key
that Puppet authorizes for the `semantic` user on the server.

### Deploying by hand

```
cd webapp
kinit
bin/kamal-otk deploy
```

`bin/kamal-otk` installs a one-time SSH key on the server using your Kerberos ticket, runs
`bin/kamal` with whatever arguments you give it, then removes the key. Use it for any Kamal command,
e.g. `bin/kamal-otk console` or `bin/kamal-otk logs`. It runs Kamal through `bin/with-deploy-env`,
which loads any deploy secrets missing from your environment from Vault (logging you in with
`vault login -method oidc` if needed).

### Adding a secret

1. Add it to Vault (as the `content` field), e.g.
   `vault kv put puppet/application/semantic-search/demo/<name> content=...`.
2. Add the environment variable to `env.secret` in `webapp/config/deploy.yml`.
3. Add `NAME=${NAME}` to `webapp/.kamal/secrets`.
4. Add its Vault path to `VAULT_SECRET_PATHS` in `webapp/bin/with-deploy-env`.
5. Add it to `secrets` in `Jenkinsfile`, using the same path without the `puppet/` prefix.
