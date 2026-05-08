# semantic-search
Developing semantic search for SUL


## Goal

We are attempting to create a semantic search prototype.

This currently depends on https://github.com/jcoyne/sdr-harvest for creating the index (and the solr config)

### Run the webapp
```
cd webapp
GEMINI_API_KEY=<key> bin/rails dev
```

## Deployment

The github workflow will build the docker image on each commit.

See https://docs.github.com/en/packages/working-with-a-github-packages-registry/working-with-the-container-registry

We deploy with kamal.

  * Get a GitHub token.
  * cd 'webapp'
  * Authenticate with kerberos: `kinit`
  * Get a one time key: `./bin/setup-otk`
  * Deploy: `KAMAL_REGISTRY_USERNAME=jcoyne \
    KAMAL_REGISTRY_PASSWORD=<github token> \
    KAMAL_OTK_KEY=~/.ssh/id_kamal_otk \
    GEMINI_API_KEY=<gemini api key> \
    bin/kamal deploy-main`
