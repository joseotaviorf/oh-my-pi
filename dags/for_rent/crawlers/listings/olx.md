## OLX
### Purpose
This DAG ingests data from OLX crawled data made by our partners. The data is placed on a S3 bucket and this day gets the JSONs imputed with one week of interval (D-7).

<details>
  <summary><strong> > DAG details (click to expand)</strong></summary>

### Execution Interval
This DAG is triggered weekly, at Saturday.

More information about run time [here]({chart_url}{dag_id}).

### Outputs

This pipeline produces, via **incremental load**, on raw layer:
    - `datalake_crawlers_listings_raw.olx`

And on clean layer:
    - `datalake_crawlers_listings_clean.olx`

</details>
