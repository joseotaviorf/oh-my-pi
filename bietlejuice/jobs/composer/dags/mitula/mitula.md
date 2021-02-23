## MITULA

### Purpose

This dag uses data extracted from Lifull in the old flow (EC2) and brings to the new clean layer.

### Dag Dependencies
This DAG depends on the old flow temporarily, the EC2 DAG is [bi-marketing-costs](https://airflow.quintoandar.com.br/admin/airflow/tree?dag_id=bi-marketing-costs). It runs an AWS Batch script that lives in [this repo](https://github.com/quintoandar/trovit-spider) and uses [this client](https://github.com/quintoandar/python-utils/blob/master/qa_python_utils/aws/batch.py).

### Dependent Dags
- [bietlejuice.dw_marketing_costs_mitula](https://k6ead11b55326f9c9-tp.appspot.com/admin/airflow/tree?dag_id=bietlejuice.dw_marketing_costs_mitula)

### Execution Interval
This dag is triggered once per day 6 AM BRT.

### Outputs

- datalake_mitula_clean.mitula_report

### Responsible Data Engineering Team

For any questions or concerns about this DAG, please contact the Data Engineering Team responsible listed in the 
[DAG owners](https://www.notion.so/productquintoandar/DAG-Owners-01810df413074722b014ac1cf033b7bd). 
