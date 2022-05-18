## Trato Feito
### Purpose

Retrieves data from the Trato Feito database (PostgreSQL). [Trato Feito](https://github.com/quintoandar/trato-feito) is a microservice that manages the negotiation flows between QuintoAndar and its debtors.

<details>
  <summary><strong> > DAG details (click to expand)</strong></summary>

### Execution Interval

Daily. More information about run time [here]({chart_url}{dag_id}).

### Outputs

Load the following tables into the datalake clean (via full load):

- `accounting_installment`
- `bill`
- `collector`
- `debt`
- `debtor`
- `installment`
- `negotiation`
- `payment`

### Responsible Data Team
​
For any questions or concerns about this DAG, please contact its owner.

</details>