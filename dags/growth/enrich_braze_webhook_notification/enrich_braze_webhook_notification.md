## Enrich Braze Webhook Notification

### Purpose

Creates an enriched table to calculate the volume of `Braze` notifications grouped by day.

### Execution Interval

Daily. More information about run time [here]({chart_url}{dag_id}).

### Outputs

Produces the following output tables, via incremental load:

- `webhook_notification_volumes`
