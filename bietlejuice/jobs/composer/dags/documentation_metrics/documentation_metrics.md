## Documentation Metrics

### Purpose

This DAG extracts data from our spark metastore and documentation bucket, so we can create metrics about documentation, 
lineage and tags coverage.


<details>

### Execution Interval

Weekly. More information about run time [here]({chart_url}{dag_id}).

### Outputs

This DAG compares data from our spark metastore with our documentation available in the data-documentation S3 bucket, 
as well as in the lineage and tag files created for our other DAGs.

Creates tables in schemas:

- `datalake_documentation_metrics_raw`
- `datalake_documentation_metrics_clean`

The following tables are created incrementally in the Raw and Clean layers:

- `tables_documentation_metrics`
- `columns_documentation_metrics`
- `categories_documentation_metrics`
- `lineage_and_tags_metrics`

### Responsible Data Team
For any questions or concerns about this DAG, please contact the Data Engineering or Data Analytics team responsible listed in the [DAG owners](https://www.notion.so/productquintoandar/DAG-Owners-01810df413074722b014ac1cf033b7bd).

</details>
