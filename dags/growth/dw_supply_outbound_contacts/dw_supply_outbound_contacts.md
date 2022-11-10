## DW Supply Outbound Contacts

### Purpose

Creates DW dimensional model tables for the Outbound flow of Supply, Inside Sales, connecting the databases of the micro-services that are part of the Omnichannel - Braze, Jaiminho and Wololo - to map the contacts made to a prospect throughout the Prospect-2-Oportunity stage.

<details>
  <summary><strong> > DAG details (click to expand)</strong></summary>

### Execution Interval

Daily. More information about run time [here]({chart_url}{dag_id}).

### Outputs
This pipeline produces the following output tables in DW layer:

- `dw_supply_outbound_contacts.fact_outbound_contacts`
- `dw_supply_outbound_contacts.dim_call`
- `dw_supply_outbound_contacts.dim_whatsapp`
- `dw_supply_outbound_contacts.dim_sms`
### Responsible Data Engineering Team

For any questions or concerns about this DAG, please contact its owner.
</details>