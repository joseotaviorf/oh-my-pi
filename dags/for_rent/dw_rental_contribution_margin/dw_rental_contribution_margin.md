## DW Rental Contribution Margin

### Purpose

​
This DAG load the DW tables for UNCM (Unit Economics) data.
​

### Execution​ Interval

This DAG is triggered once per day via Mediator.

### Outputs

​
This pipeline produces the following output tables:
​

- `fact_house_listing_revenues` – Contains the revenue of each contract, segmented by rent, administration fee, brokerage fee, home insurance, service fee, month rental antecipation (MRA), long term rental antecipation (LRA), late payments, brokerage finance. Each row represents the revenues of the contract in a month.
  ​
