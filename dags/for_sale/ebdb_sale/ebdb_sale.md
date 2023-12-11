## EBDB Sale

### Purpose

Extraction of EBDB tables related to Sale into data lake. EBDB is the main database for QuintoAndar.

<details>
  <summary><strong> > DAG details (click to expand)</strong></summary>

### Execution Interval

Daily. More information about run time [here]({chart_url}{dag_id}).

### Outputs

Produces the following output tables:

In datalake clean:
  - `sale_operation_management`
  - `shop_window_aud`
  - `shop_window_listing_business_context_aud`
  - `shop_window_listing_business_context`
  - `shop_window`