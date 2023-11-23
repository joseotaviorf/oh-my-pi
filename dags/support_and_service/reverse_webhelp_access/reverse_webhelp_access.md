## Reverse WebHelp Access

### Purpose

This dag pulls in the data saved in the datalake loaded by reverse_webhelp, then uses that data to write a parquet dataframe in the webhelp's azure environment. 
The data sent refers to the monitoring of the operation.

<details>
  <summary><strong> > DAG details (click to expand)</strong></summary>

### Execution Interval

Daily. More information about run time [here]({chart_url}{dag_id}).

### Outputs

This pipeline exports the following tables from the reverse_webhelp schema to an azure environment:

- `backlog_metric`
- `csat_front`
- `demand_metric`
- `fcr_metric`
- `general_metric`
- `listing_quality_tasks`
- `listing_quality_sla`
- `repair_tickets`
- `taxonomia_call`
- `taxonomia_chat`
- `taxonomia_email`
- `twilio_chat_aht`

</details>