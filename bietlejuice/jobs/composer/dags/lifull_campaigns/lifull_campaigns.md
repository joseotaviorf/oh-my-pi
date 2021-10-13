## Lifull Campaigns

### Purpose

Lifull Campaigns DAG creates incremental RAW and CLEAN tables with data extracted by a crawler from Thribee/Lifull reports, which summarize performance of classified ads campaigns from Mitula and Trovit platforms. Using an [AWSBatchOperator](https://airflow.apache.org/docs/apache-airflow/1.10.15/_api/airflow/contrib/operators/awsbatch_operator/index.html), it runs an [AWS Batch](https://docs.aws.amazon.com/batch/latest/userguide/what-is-batch.html) script stored at [trovit-spider repo](https://github.com/quintoandar/trovit-spider).
All AWS Batch resources were created using [Terraform structure](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/batch_compute_environment) in Infrastructure repo, available for [Forno](https://github.com/quintoandar/infrastructure/tree/master/cloud/aws-accounts/forno-data/batch) and [Production](https://github.com/quintoandar/infrastructure/tree/master/cloud/aws-accounts/data/batch) environments.

[Trovit](https://www.trovit.com.br/) is a search engine specializing in classified ads, while [Mitula](https://www.mitula.com.br/) is a real estate, employment and cars classified ad aggregator that shows its content to users for free. Both services have their ads optimized and managed at [Thribee](https://thribee.com/), a traffic acquisition service part of Lifull Connect enterprise.

​<details>
  <summary><strong> > DAG details (click to expand)</strong></summary>

### Execution Interval

Daily. More information about run time [here]({chart_url}{dag_id}).

### Outputs

This pipeline produces the following output tables in each layer: 
* raw:
    - datalake_lifull_campaigns_raw.trovit_report
    - datalake_lifull_campaigns_raw.mitula_report
* clean:
    - datalake_lifull_campaigns_clean.trovit_report
    - datalake_lifull_campaigns_clean.mitula_report

### Responsible Data Team

For any questions or concerns about this DAG, please contact the Data Engineering or Data Analytics team responsible listed in the [DAG owners](https://www.notion.so/productquintoandar/DAG-Owners-01810df413074722b014ac1cf033b7bd).
</details>