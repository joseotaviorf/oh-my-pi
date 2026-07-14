SELECT
    id_contract,
    COUNT(DISTINCT id_nps_answer) AS number_of_responses,
    COUNT(
        DISTINCT CASE 
            WHEN customer_type = 'IQ' THEN id_nps_answer 
            ELSE NULL 
        END
    ) AS number_of_responses_iq,
    COUNT(
        DISTINCT CASE 
            WHEN customer_type = 'PP' THEN id_nps_answer 
            ELSE NULL 
        END
    ) AS number_of_responses_pp,
    SUM(
        CASE 
            WHEN customer_type = 'IQ' THEN score 
            ELSE NULL 
        END
    ) AS nps_iq,
    SUM(
        CASE 
            WHEN customer_type = 'PP' THEN score 
            ELSE NULL 
        END
    ) AS nps_pp
FROM 
    datalake_offboarding.nps
GROUP BY 1