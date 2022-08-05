## Enrich Jira

### Purpose

This DAG creates the full table for Jira issues status change.

<details>
  <summary><strong> > DAG details (click to expand)</strong></summary>

### Execution Interval

This DAG is triggered daily, via Mediator.

More information about run time [here]({chart_url}{dag_id}).

### Outputs

This pipeline produces the following output table:

1. In data lake enrich:

- `issues`
- `issues_itops`
- `issue_status_changes`

</details>
