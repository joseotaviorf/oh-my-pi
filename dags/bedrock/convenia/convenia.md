## Convenia
### Purpose
Retrieves data from [Convenia API](https://github.com/quintoandar/convenia-api-client-python).

Convenia is a platform to manage employees and provide data to People Analytics team, such as employee's salary history and other personal information.

<details>
  <summary><strong> > DAG details (click to expand)</strong></summary>

### Execution Interval
Daily. More information about run time [here]({chart_url}{dag_id}).

### Outputs
We fully load the following tables into the datalake Raw and Clean:

- `active_employees`
- `employee_salary_history`
- `inactive_employees`

### Responsible Data Team
For any questions or concerns about this DAG, please contact the Data Engineering team responsible.
</details>