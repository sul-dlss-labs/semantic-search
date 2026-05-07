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

* SSH to the host.
* Pull the image:
```
docker pull ghcr.io/sul-dlss-labs/semantic-search:main
```
* `docker run -d -e SOLR_URL=https://sul-solr-test.stanford.edu/solr/semantic-search-demo -e RAILS_MASTER_KEY=<master key> -p 3000:80 ghcr.io/sul-dlss-labs/semantic-search:main`
