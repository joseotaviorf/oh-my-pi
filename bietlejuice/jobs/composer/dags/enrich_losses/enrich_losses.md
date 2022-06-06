## Enrich Losses

### Purpose

Creates enriched tables for the `Losses` context, which aims to analyze NPV for Rental Contracts, initially.

### Execution Interval

Daily. More information about run time [here]({chart_url}{dag_id}).

### Outputs

Produces the following output tables, via full load:

- `contract_rental_losses_npv`