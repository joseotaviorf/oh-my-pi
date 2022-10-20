SELECT 
    prospect_id AS id_prospect, 
    reference_id AS id_reference,
    round_count AS round_number,  
    max_tries AS round_max_tries, 
    created_at AS ts_created
FROM
    datalake_wololo_raw.round