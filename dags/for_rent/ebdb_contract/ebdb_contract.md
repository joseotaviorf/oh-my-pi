## EBDB Contract

### Purpose

Extraction of EBDB tables related to Contract into data lake. EBDB is the main database for QuintoAndar.

<details>
  <summary><strong> > DAG details (click to expand)</strong></summary>

### Execution Interval

Daily. More information about run time [here]({chart_url}{dag_id}).

### Outputs

Produces the following output tables:

In datalake clean:
  - `contract`
  - `contract_aud`
  - `contract_negotiation`
  - `contract_partnership_data`
  - `contract_person`
  - `contract_person_aud`
  - `contract_version`
  - `full_contract`
  - `portability`
  - `portability_aud`
  - `signature`
  - `work_contract`