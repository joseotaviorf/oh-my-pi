## Reverse CCV Price Report Load

### Purpose

This DAG consolidates the sales price information for each id_region of the QuintoAndar. With this, we will report to the product so they can build a feature to assist the customers' marketplace process.

The logic of grouping regions is the responsibility of the ForSale Supply team. 

This data will create a chart directly in the product.

<details>
  <summary><strong> > DAG details (click to expand)</strong></summary>

### Execution Interval

The data will be updated every monthly. More information about run time [here]({chart_url}{dag_id}).

### Outputs

We will consolidate the following tables monthly with a full load:

- `ccv_price_by_region`

</details>