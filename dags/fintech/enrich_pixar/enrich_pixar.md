## Enrich Pixar

### Purpose

Creates enriched tables for Pixar data from Clean layer. This enrich layer is mostly on purpose to remove duplicated data from Clean.

### Execution Interval

Daily. More information about run time [here]({chart_url}{dag_id}).

### Outputs

Produces the following output tables, via full load:

- `account`
- `charge`
- `refund`
