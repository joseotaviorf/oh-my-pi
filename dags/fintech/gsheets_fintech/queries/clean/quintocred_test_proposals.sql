SELECT
    CAST(NULLIF(sk_propose, '') AS INTEGER) AS sk_propose,
    NULLIF(name, '') AS name,
    NULLIF(email, '') AS email
FROM
    datalake_gsheets_raw.quintocred_test_proposals
