## Trovit

### Purpose

Creates incremental CLEAN tables with data extracted by a crawler from Thribee/Lifull reports at [`bi-marketing-costs`](https://airflow.quintoandar.com.br/admin/airflow/tree?dag_id=bi-marketing-costs) DAG in the old Airflow pipeline. It runs an AWS Batch script stored at [trovit-spider repo](https://github.com/quintoandar/trovit-spider) and triggered using [this Python 2 AWS Batch client](https://github.com/quintoandar/python-utils/blob/master/qa_python_utils/aws/batch.py). [Trovit](https://www.trovit.com.br/) is a search engine specializing in classified ads. Its ads are optimized and managed at [Thribee](https://thribee.com/), a traffic acquisition service part of Lifull Connect enterprise.

<details>
    <summary><strong> > DAG details (click to expand)</strong></summary>

### Execution Interval
This dag is triggered once per day at 6 AM BRT.

### Outputs
This pipeline produces the following output tables in each layer: 
* raw:
    - datalake_trovit_raw.trovit_report
* clean:
    - datalake_trovit_clean.trovit_report

### Responsible Data Engineering Team
For any questions or concerns about this DAG, please contact the Data Engineering Team responsible listed in the 
[DAG owners](https://www.notion.so/productquintoandar/DAG-Owners-01810df413074722b014ac1cf033b7bd).
</details>