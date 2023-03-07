## Convenia Details
### Purpose
Retrieves data from [Convenia API](https://github.com/quintoandar/convenia-api-client-python).

Convenia is a platform to manage employee's and provide data to People Analytics team. This DAG will retrieve employee details such as employee's supervisor, salary, benefits and others.

<details>
  <summary><strong> > DAG details (click to expand)</strong></summary>

### Execution Interval
Daily. More information about run time [here]({chart_url}{dag_id}).

## Sources
The data retrieved are from the following API keys:
- `Quinto Andar SP`
- `Quinto Andar MG`
- `Quinto Andar SC`
- `Atta`
- `Benvi Mx`
- `Benvi Pt`

### Outputs
We fully load the following tables into the datalake Raw and Clean:

- `active_employee_details`

### Responsible Data Team
For any questions or concerns about this DAG, please contact the Data Engineering team responsible.
</details>
