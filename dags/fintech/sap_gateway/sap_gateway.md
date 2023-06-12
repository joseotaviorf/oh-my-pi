## Sap Gateway

### Purpose

This DAG creates the raw and clean layer to import data from SAP Gateway. SAP Gateway is an structure used to connect devices, environments, and platforms to SAP systems.


<details>
  <summary><strong> > DAG details (click to expand)</strong></summary>

### Execution Interval
This DAG is triggered daily, via Mediator. More information about run time [here]({chart_url}{dag_id}).

### Outputs

In datalake RAW, via full load:

- `account`
- `address`
- `business_partner`
- `card_code`
- `person`
- `rule`
- `rule_account_type`
- `consolidated_journal_entry_lines`
- `consolidated_journal_entry`
- `journal_entry_lines`
- `journal_entry`



In datalake RAW, via incremental load:

- `feature`
- `operation`
- `sync_sap_job`



In datalake CLEAN, via full load:

- `account`
- `address`
- `business_partner`
- `card_code`
- `person`
- `rule`
- `rule_account_type`
- `rule_special_condition`
- `special_condition`
- `consolidated_journal_entry_lines`
- `consolidated_journal_entry`
- `journal_entry_lines`
- `journal_entry`



In datalake CLEAN, via incremental load:

- `feature`
- `operation`
- `sync_sap_job`
