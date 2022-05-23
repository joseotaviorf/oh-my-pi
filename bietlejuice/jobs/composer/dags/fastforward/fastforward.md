## FastForward

### Purpose

Retrieves data from the FastForward database (postgresql). [FastForward](https://github.com/quintoandar/fast-forward) 
is the service responsible for handling rent anticipation from its offer creation 
and acceptance so our operations team can make the payment and SeuBarriga to 
notify that the rent has already been transferred. 

<details>
  <summary><strong> > DAG details (click to expand)</strong></summary>

### Execution Interval

Daily. More information about run time [here]({chart_url}{dag_id}).

### Outputs

We load the following tables into the datalake:

1. In datalake raw:
 
    - All tables available in source's database

2. In datalake clean

`anticipation_fee`, `anticipation_fee_aud`, `anticipation_promo_for_contract`, `anticipation_promo_for_contract_aud`, `brokerage_fee`, `brokerage_fee_aud`, `contract`, `contract_aud`, `house`, `house_aud`, `installment_plan`, `installment_plan_aud`, `long_term_anticipation`, `long_term_anticipation_aud`, `lra_installment`, `lra_installment_option`, `lra_installment_option_aud`, `promo_fee`, `promo_fee_aud`, `real_estate_agent_fee`, `real_estate_agent_fee_aud`, `rev_info`, `users`, `users_aud`
    
### Responsible Data Team

For any questions or concerns about this DAG, please contact the Dag Owner Team.

</details>