## DW Proposal

### Purpose

Full load of the context `Proposal` models into DW
with enriched data of docx (credit evaluation) and proposals from sorting hat and ebdb.

​<details>
  <summary><strong> > DAG details (click to expand)</strong></summary>

### Execution Interval

Daily. More information about run time [here]({chart_url}{dag_id}).

### Outputs

Produces the following output tables:

- `dim_proposal`
- `quintoandar.dim_proposal_person`
- `quintoandar.fact_proposal_people`
