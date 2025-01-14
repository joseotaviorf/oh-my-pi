SELECT
    NULLIF(code_status, '') AS code_status,
    NULLIF(desc_status, '') AS desc_status,
    NULLIF(tab, '') AS tab,
    NULLIF(effort, '') AS effort,
    NULLIF(massive, '') AS massive,
    NULLIF(channel, '') AS channel
FROM
    datalake_gsheets_raw.quintocred_iaf_occurences
