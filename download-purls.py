import csv
import requests
import json
from pathlib import Path

with open('report.csv', 'r') as csvfile:
    reader = csv.DictReader(csvfile)
    for row in reader:
        outfile = f'purl-description/{row['Druid']}.json'
        if not Path(outfile).is_file() and row['Access Rights'] != 'dark' and row['Pub. Date'] != '':
          print(row['Druid'])
          r = requests.get(f'https://purl.stanford.edu/{row['Druid']}.json')
          with open(outfile, 'w', encoding='utf-8') as out:
            json.dump(r.json()['description'], out, ensure_ascii=False, indent=4)
