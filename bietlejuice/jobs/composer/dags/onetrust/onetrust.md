## Onetrust
### Purpose

Extracts the onetrust information using [onetrust api](https://developer.onetrust.com/onetrust)

### Execution Interval

Daily. More information about run time [here]({chart_url}{dag_id}).

### Outputs

Load the table for both our raw and clean layers (incrementally):

- `audit`
- `organizations`
- `user_groups`