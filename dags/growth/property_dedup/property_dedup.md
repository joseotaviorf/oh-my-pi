## Property Dedup

### Purpose

This DAG handles the ingestion of our raw and clean data for our Property Dedup Microservice. For more information about the Database please refer to [the repository](https://github.com/quintoandar/property-dedup).
<details>
  <summary><strong> > DAG details (click to expand)</strong></summary>

### Execution Interval

This DAG is triggered daily.

More information about run time [here]({chart_url}{dag_id}).

### Outputs

1. In datalake raw:
    - All tables which are available in the source's database.

2. In datalake clean:
  - `duplicity_output`
  - `duplicity_output_aud`
  - `revinfo`
  - `similar_property`
  - `similar_property_aud`

</details>
