## Arquivo Confidencial - Integration Report

### Purpose

This DAG imports the table integration_report_aud from [Arquivo Confidencial](https://github.com/quintoandar/arquivo-confidencial), a service responsible to track user personal info using SaaS platforms. **This DAG was created as a short-term solution to process the data from integration_report_aud, which has an extremelly large JSON column (attributes) not compatible with CDC infrastructure. This DAG will be soon deprecated.**

<details>
  <summary><strong> > DAG details (click to expand)</strong></summary>

### Execution Interval

Daily. More information about run time [here]({chart_url}{dag_id}).

### Outputs

In datalake raw and clean, via incremental load:
- `integration_report_aud`
- `integration_report`

### Additional Information

Those tables are not viewed by every team. Right now, only Credit team has access.
</details>
