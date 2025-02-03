SELECT
    CAST(NULLIF(id_propose, '') AS INTEGER) AS id_propose
FROM
    datalake_gsheets_raw.quintocred_excluded_proposals
