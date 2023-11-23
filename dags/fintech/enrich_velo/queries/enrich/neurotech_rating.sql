WITH neurotech_aux AS (
    SELECT
        TRY_CAST(proposal_number AS INTEGER) AS id_propose,
        proposal_rating AS rating,
        ts_operation
    FROM
        datalake_velo_neurotech_clean.logs_credit_granting
    WHERE
        proposal_number <> 'NaN'
        AND LENGTH(proposal_number) <= 8
    QUALIFY ROW_NUMBER() OVER (PARTITION BY TRY_CAST(proposal_number AS INTEGER) ORDER BY ts_operation DESC) = 1
)
SELECT
    id_propose,
    CASE
        WHEN rating IS NULL THEN 'missing'
        WHEN rating = 'NaN' THEN 'missing'
        ELSE rating
    END AS rating,
    ts_operation
FROM
    neurotech_aux
