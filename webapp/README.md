# Semantic search webapp

## Setup credentials

See https://cloud.google.com/docs/authentication/provide-credentials-adc#how-to

Go to https://console.cloud.google.com/iam-admin/serviceaccounts/details/102998824006089567844/keys and download the json key

set GOOGLE_APPLICATION_CREDENTIALS=<path to file.json>


## Deploy

1. Get a classic GH access token
1. ssh to the server
1. `export CR_PAT=<token>`
1. `echo $CR_PAT | docker login ghcr.io -u jcoyne --password-stdin`
1. `docker pull ghcr.io/sul-dlss-labs/semantic-search:main`
1. `docker run -e RAILS_MASTER_KEY=<master key> -p 80:80 ghcr.io/sul-dlss-labs/semantic-search:main`
