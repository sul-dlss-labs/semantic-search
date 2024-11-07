# semantic-search
Developing semantic search for SUL


## Goal

We are attempting to create a semantic search prototype.

### Get list of objects
The first step is getting data to index. I've elected to look at self-deposit files:
https://argo.stanford.edu/report?f%5Bcontent_type_ssim%5D%5B%5D=file&f%5Bnonhydrus_apo_title_ssim%5D%5B%5D=Hydrus+Ur-APO&f%5Breleased_to_searchworks%5D%5B%5D=ever
Make sure "Access Rights" and "Pub date" are in the selected columns.
These have been deposited via Hydrus or H2 and have been released to Searchworks, so the data is already on the public web.

This is saved to this repo as `report.csv`

### Get data for each
Run the harvest script to pull the data from PURL:
```
python download-purls.py
```

### Extract relevant data

```
jq -c '{ "id":input_filename | ltrimstr("purl-description/") | rtrimstr(".json"), "title":.title[].value, "abstract":.note | .[] | select(.type == "abstract").value}' purl-description/*.json > dataset.json
```

### Create an index
On Collab Enterprise, run the python script. <Semantic\ search\ chunking\ and\ embedding.ipynb>

### Download data from google cloud storage
The index script created this file <https://console.cloud.google.com/storage/browser/_details/cloud-ai-platform-e215f7f7-a526-4a66-902d-eb69384ef0c4/semantic-search/chunk_to_doc.json;tab=live_object?project=sul-ai-sandbox>.  We have downloaded it an put it into the webapp at `semantic-search_chunk_to_doc.json`.  This lets us look up which SDR item a particular text chunk works for.

### Run the webapp
```
cd webapp
bin/rails dev
```
