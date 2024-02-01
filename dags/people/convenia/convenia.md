## Convenia
### Purpose
Retrieves data from [Convenia API](https://github.com/quintoandar/convenia-api-client-python).

Convenia is a platform to manage employees and provide data to People Analytics team, such as employee's salary history and other personal information.

<details>
  <summary><strong> > DAG details (click to expand)</strong></summary>

### Execution Interval
Daily. More information about run time [here]({chart_url}{dag_id}).

## Sources
The data retrieved are from the following API keys:
- Quinto Andar SP
- Quinto Andar MG
- Quinto Andar SC
- Atta
- Benvi Mx
- Benv Pt

### Outputs
We fully load the following tables into the datalake Raw and Clean:

- `active_employees`
- `employee_salary_history`
- `inactive_employees`

</details>
