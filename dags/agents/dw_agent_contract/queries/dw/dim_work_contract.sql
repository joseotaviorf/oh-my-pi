/* 
Note that the granularity of this table is not each row per work contract, but each row
per possible combination of data associated with the work contract.

This includes the work contract, but also the information if the agent user is marked as active or not
on Main, as well as the business context (Sale or Rent). That is because these last two are low-cardinality
flags, and having them as separate dimensions or flags in the fact table would not be good for simplicity
(in the first case) or good practice (second case).

That makes this table a junk dimension.
*/
WITH contract_with_default AS (
    SELECT
        wc.id,
        wc.contract_name,
        COALESCE(
            NULLIF(
                REGEXP_EXTRACT(wc.contract_name, '(?i)(?<=\\[3P\\-)(.+?)(?=\\])'),
                ''
            ),
            'N/A'
        ) AS 3p_partner,
        LOWER(wc.contract_name) LIKE '%[3p-%]%' AS is_3p_contract,
        wc.ts_created,
        wc.ts_updated
    FROM
        datalake_ebdb_clean.work_contract AS wc
    UNION ALL
    SELECT
        NULL AS id,
        'N/A' AS contract_name,
        'N/A' AS 3p_partner,
        FALSE AS is_3p_contract,
        NULL AS ts_created,
        NULL AS ts_updated
),
active_explosion AS (
    SELECT *,
        EXPLODE(ARRAY(TRUE, FALSE)) AS is_active
    FROM
        contract_with_default
),
sale_explosion AS (
    SELECT *,
        EXPLODE(ARRAY(TRUE, FALSE)) AS is_for_sale_contract
    FROM
        active_explosion
),
rent_explosion AS (
    SELECT *,
        EXPLODE(ARRAY(TRUE, FALSE)) AS is_for_rent_contract
    FROM
        sale_explosion
)
SELECT
    BIGINT(COALESCE(id, -1) || INT(is_active) || INT(is_for_sale_contract) || INT(is_for_rent_contract)) AS sk_work_contract,
    id AS id_work_contract,
    contract_name,
    3p_partner,
    is_active,
    is_3p_contract,
    is_for_sale_contract,
    is_for_rent_contract,
    ts_created,
    ts_updated,
    NOW() AS ts_load
FROM
    rent_explosion