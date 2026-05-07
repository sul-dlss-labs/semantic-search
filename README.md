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

* SSH to the host.
* Pull the image:
```
docker pull ghcr.io/sul-dlss-labs/semantic-search:main
```
