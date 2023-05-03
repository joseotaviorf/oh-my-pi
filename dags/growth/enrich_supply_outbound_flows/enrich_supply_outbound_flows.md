## Enrich Supply Outbound Flows

### Purpose

Creates an enrich that aggregates the data from the Outbound flow of Supply, Inside Sales, connecting the databases of the micro-services that are part of the Omnichannel - Braze, Jaiminho and Wololo - to map the contacts made to a prospect throughout the P2O stage.

<details>
  <summary><strong> > DAG details (click to expand)</strong></summary>

### Execution Interval

Daily. More information about run time [here]({chart_url}{dag_id}).

### Outputs

Produces the following output table:

- `supply_outbound_contacts` - a compilation of all the request of contacts made to the prospect along the Prospect-to-Oportunity flow.

</details>
