## Enrich Hubspot

### Purpose

Creates enriched tables for `hubspot`.

​<details>

Every object other than `team` in `datalake_hubspot_clean` is ingested incrementally, which makes them history tables. They are all copied to `datalake_hubspot` with the suffix `_history`, extracting all of the jsons to make them easier to use.

However, for most use cases, we need to know how HubSpot is right now, not the history. So all the history tables are filtered by the most recent update for each ID, and the archived rows are also removed. For example, `company_history` originates `company`.

The tables `datalake_hubspot_clean.deal_pipeline` and `datalake_hubspot_clean.ticket_pipeline` are merged into `pipeline_history`, except for their stage arrays, which are exploded and give rise to the `stage_history` table.

The table `datalake_hubspot_clean.team` is broken into `datalake_hubspot.team`, which has their name and IDs, and `datalake_hubspot.team_user`, in which every line corresponds to an association between a user and a team.

To make lead time analysis easier, we have `company_status`, `contact_status`, `deal_stage` and `ticket_stage`. Each row represents a change in lead_status (company and contact) or stage (deal and ticket).

### Execution Interval

Daily. More information about run time [here]({chart_url}{dag_id}).

### Outputs

Produces the following output tables in `datalake_hubspot`:

**Incrementally:**
- `company_history`
- `contact_history`
- `deal_history`
- `ticket_history`
- `owner_history`

**Fully:**
- `company`
- `company_status`
- `contact`
- `contact_status`
- `deal`
- `deal_stage`
- `ticket`
- `ticket_stage`
- `pipeline`
- `pipeline_history`
- `stage`
- `stage_history`
- `owner`
- `team`
- `team_user`

### Responsible Data Engineering Team

For any questions or concerns about this DAG, please contact the Data For Brokers Team.

</details>