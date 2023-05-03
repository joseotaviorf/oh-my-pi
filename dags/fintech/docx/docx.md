## Docx

### Purpose

Extraction of Docx tables into data lake. Docx is the backend application for documents and credit simulation.

<details>
  <summary><strong> > DAG details (click to expand)</strong></summary>

### Execution Interval

Daily. More information about run time [here]({chart_url}{dag_id}).

### Outputs

Produces the following output tables, through full load:

1. In datalake raw:
    - All tables available in source's database, except for Operationals (pg_stat_statements, flyway_schema_history).

2. In datalake clean:
    - `credit_evaluation`
    - `credit_evaluation_aud`
    - `credit_evaluation_proponent`
    - `credit_evaluation_proponent_aud`
    - `document`
    - `document_aud`
    - `document_context`
    - `document_type`
    - `folder`
    - `folder_aud`
    - `folder_reference`
    - `folder_reference_aud`
    - `folder_reference_type`
    - `folder_type`
    - `rev_info`
    - `simulation`
    - `simulation_user`
    - `user_tenant_flow`

</details>
