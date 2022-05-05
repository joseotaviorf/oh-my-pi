## Enrich Documentation Metrics

### Purpose

This DAG uses data extracted from dags, our spark metastore and from the documentation bucket to calculate metrics about our tables documentation, lineage and tags.

<details>

### Execution Interval

Weekly. More information about run time [here]({chart_url}{dag_id}).

### Outputs

This DAG compares data from our spark metastore with our documentation available in the data-documentation S3 bucket, 
as well as in the lineage and tag files created for our other DAGs.

Creates tables in schemas:

- `datalake_documentation_metrics`

The following tables are created incrementally:

- `tables_documentation_metrics`
- `columns_documentation_metrics`
- `categories_documentation_metrics`
- `lineage_and_tags_metrics`

### Responsible Data Team

For any questions or concerns about this DAG, please contact its owner.

</details>
