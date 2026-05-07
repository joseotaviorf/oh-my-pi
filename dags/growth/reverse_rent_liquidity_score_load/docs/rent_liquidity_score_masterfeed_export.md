# Rent liquidity score export to Masterfeed

## Rent liquidity score source table

Rent liquidity scores are read from **`dw_liquidity.fact_house_rent_liquidity`**.

In that table you will find **`house_liquidity_score`**: it is the value stored in the **`rent_liquidity_score`** column. It represents the **probability that a house will be rented within 4 weeks after publication**.

Related columns:

- **`rent_liquidity_model_version`**: model version used to produce the rent liquidity score.
- **`sk_house`**: identifies the house; this value is published to Masterfeed as **`houseId`** in the SQS payload.

## Rent liquidity score pipelines

1. **`reverse_rent_liquidity_score_load`** — loads into **`reverse_rent_liquidity_score.rent_liquidity_score`** (`custom_schema: rent_liquidity_score` → catalog `reverse_rent_liquidity_score`). SQL: `dags/growth/reverse_rent_liquidity_score_load/queries/reverse/rent_liquidity_score.sql`.
2. **`reverse_rent_liquidity_score_access`** — reads **`reverse_rent_liquidity_score.rent_liquidity_score`** and sends one JSON message per row to the environment-specific **MasterfeedHouseRentLiquidityScore** SQS queue (Prod or Forno, via `spark_jobs/prod_conf.yml` and `spark_jobs/forno_conf.yml`).

For column-level lineage and ownership of the fact table, see `dags/fintech/dw_liquidity/metadata/dw/fact_house_rent_liquidity.yml`.
