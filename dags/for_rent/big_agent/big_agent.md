## Big Agent
### Purpose

This DAG imports data from [Big Agent](https://github.com/quintoandar/big-agent), which is an internal microservice responsible for handling the agent and house relationship.

### Execution Interval

Daily. More information about run time [here]({chart_url}{dag_id}).

### Outputs

This pipeline produces, via incremental load:

- In datalake raw:
    - All tables available in database, except for the operationals.

- In datalake clean:
    - `agency`
    - `agency_aud`
    - `agent`
    - `agent_aud`
    - `earnings`
    - `earnings_aud`
    - `enrollment`
    - `enrollment_aud`
    - `external_invoice`
    - `external_invoice_aud`
    - `house`
    - `house_aud`
    - `installment`
    - `installment_aud`
    - `program`
    - `program_aud`
    - `user_revision_entity`
