## Arquivo Confidencial

### Purpose

This DAG imports the tables from [Arquivo Confidencial](https://github.com/quintoandar/arquivo-confidencial), a service responsible to track user personal info using SaaS platforms.

<details>
  <summary><strong> > DAG details (click to expand)</strong></summary>

### Execution Interval

Daily. More information about run time [here]({chart_url}{dag_id}).

### Outputs

In datalake raw and clean, via full load:
- `presumed_income_report`
- `presumed_income_report_aud`

In datalake raw and clean, via incremental load:
- `documentation_report`
- `documentation_report_aud`
- `documents`
- `emailage_result`
- `emailage_result_aud`
- `integration_report`
- `integration_report_aud`
- `request_tracker`
- `rev_info`
- `unico_check_document`
- `unico_check_document_aud`
- `unico_check_process`
- `unico_check_process_aud`

### Additional Information

Those tables are not viewed by every team. Right now, only Credit team has access.
</details>
