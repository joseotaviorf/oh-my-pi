## Cypress
### Purpose

Cypress is an End to End testing framework used by the product team here at Quinto Andar. This DAG retrieves JSON data from Cypress' S3 source bucket and make it available for the QAs to analyse.

### Disclaimer

This DAG contains enrichment transformations inside its Spark job which demands a future adequancy to our standards.

​<details>
  <summary><strong> > DAG details (click to expand)</strong></summary>

### Execution Interval

Daily. More information about run time [here]({chart_url}{dag_id}).

### Outputs

This pipeline produces the following output tables for both our raw and clean layers: 

- `suites`
- `tests`

### Responsible Data Team

For any questions or concerns about this DAG, please contact the Data Engineering or Data Analytics team responsible listed in the [DAG owners](https://www.notion.so/productquintoandar/DAG-Owners-01810df413074722b014ac1cf033b7bd).
</details>