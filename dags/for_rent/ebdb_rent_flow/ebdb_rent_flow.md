## EBDB Rent Flow

### Purpose

Extraction of EBDB tables related to Rent Flow into data lake. EBDB is the main database for QuintoAndar.

<details>
  <summary><strong> > DAG details (click to expand)</strong></summary>

### Execution Interval

Daily. More information about run time [here]({chart_url}{dag_id}).

### Outputs

Produces the following output tables:

In datalake clean:
  - `agent_rent_flow`
  - `onboarding`
  - `rent_flow`
  - `rent_flow_aud`