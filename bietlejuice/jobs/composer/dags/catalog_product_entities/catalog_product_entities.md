## Catalog Product Entities

### Purpose

BigID is a data governance tool used to catalog product databases and automatically classify if 
their data is PII, sensitive, etc.

This DAG pulls data from `datalake_bigid.bigid_product_entities_access_level`
and sends it to Metadata Propagator. Then, Metadata Propagator will create those entities in our
Data Catalog.

The data used from `bigid_product_entities_access_level` is:

* Database, table and column names,
* If the columns have PII or sensitive information
* The columns access level (Public, Restricted or Confidential)

<details>
  <summary><strong> > DAG details (click to expand)</strong></summary>

### Execution Interval

Weekly. More information about run time [here]({chart_url}{dag_id}).

### Outputs

Sends requests to Metadata Propagator with extracted data. The expected outputs are new entities in Apache Atlas.

There is no output in the Datalake or in the DW.

### Responsible Data Engineering Team

For any questions or concerns about this DAG, please contact the Data Engineering Team responsible listed in the 
[DAG owners](https://www.notion.so/productquintoandar/DAG-Owners-01810df413074722b014ac1cf033b7bd).

</details>
