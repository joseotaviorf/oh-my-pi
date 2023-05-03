## Loft
### Purpose
This dag ingests data from loft crawler made by our partners. The data is placed on a s3 bucket and this day get the JSONs imputed with one week of interval(D-7).

E.G.:
   - DAG runs on 27/08 and reads the data from folder 20/08

<details>
  <summary><strong> > DAG details (click to expand)</strong></summary>

### Execution Interval
This DAG is triggered weakly.

More information about run time [here]({chart_url}{dag_id}).

### Outputs

This pipeline produces, in datalake raw and clean:

Via **full load**:
    - `loft`

</details>
