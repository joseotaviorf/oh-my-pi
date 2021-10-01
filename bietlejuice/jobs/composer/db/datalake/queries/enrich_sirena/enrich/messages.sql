with agents_class AS (
    SELECT
        gr.group_name,
        ag.id,
        ag.first_name,
        ag.last_name,
        ag.phone,
        ag.email
    FROM
        datalake_sirena_clean.agents as ag
    INNER JOIN
        datalake_sirena_clean.groups AS gr
            ON ag.id_group = gr.id
    WHERE
        gr.group_name IN ('Closing', 'Deal Making')
),
client_info AS (
    SELECT
        id,
        CASE
            WHEN pr.last_name REGEXP '[0-9]{{9}}'
                THEN regexp_extract(pr.last_name, '[0-9]{{9}}', 0)
        END AS id_house,
        CASE label
            WHEN 'warm' THEN 'Seller'
            WHEN 'cold' THEN 'Buyer'
        ELSE
            CASE pr.last_name
                WHEN LOWER(pr.last_name) LIKE '%buy%'
                    THEN 'Buyer'
                WHEN LOWER(pr.last_name) LIKE '%by%'
                    THEN 'Buyer'
                WHEN LOWER(pr.last_name) LIKE '%sell%'
                    THEN 'Seller'
                WHEN LOWER(pr.last_name) LIKE '%sl%'
                    THEN 'Seller'
                ELSE NULL
            END
        END AS prospect_type,
        CASE
            WHEN LOWER(pr.last_name) LIKE '%parceiro%'
                THEN false
            ELSE true
        END AS is_client
    FROM
        datalake_sirena_clean.prospects AS pr
)
SELECT
    intrc.id,
    intrc.id_prospect,
    ci.id_house,
    intrc.id_agent,
    ci.prospect_type,
    CASE
        WHEN intrc.is_proactive = false
            THEN intrc.output.message.sender
        ELSE intrc.output.message.recipient
    END AS prospect_phone,
    CASE
        WHEN ac.group_name IS NULL
            THEN 'QuintoAndar Admin'
        ELSE ac.group_name
    END AS group_name,
    ac.first_name AS agent_first_name,
    ac.last_name AS agent_last_name,
    ac.phone AS agent_phone,
    ac.email AS agent_email,
    intrc.via,
    CASE intrc.output.message.content
        WHEN ''
            THEN 'Anexo'
        WHEN NULL
            THEN 'Anexo'
        ELSE 'Texto'
    END AS message_type,
    intrc.output.message.template,
    CASE intrc.output.message.content
        WHEN ''
            THEN
                CASE intrc.output.message.attachment.type
                    WHEN 'AUDIO'
                        THEN 'ANEXO - áudio'
                    WHEN 'FILE'
                        THEN 'ANEXO - arquivo'
                    WHEN 'IMAGE'
                        THEN 'ANEXO - imagem'
                    WHEN 'VIDEO'
                        THEN 'ANEXO - vídeo'
                END
        WHEN NULL
            THEN
                CASE intrc.output.message.attachment.type
                    WHEN 'AUDIO'
                        THEN 'ANEXO - áudio'
                    WHEN 'FILE'
                        THEN 'ANEXO - arquivo'
                    WHEN 'IMAGE'
                        THEN 'ANEXO - imagem'
                    WHEN 'VIDEO'
                        THEN 'ANEXO - vídeo'
                END
        ELSE intrc.output.message.content
    END AS message_content,
    ci.is_client,
    intrc.is_proactive,
    TO_TIMESTAMP(intrc.ts_created) AS ts_created
FROM
    datalake_sirena_clean.interactions AS intrc
LEFT JOIN
    agents_class AS ac
        ON intrc.id_agent = ac.id
LEFT JOIN
    client_info AS ci
        ON intrc.id_prospect = ci.id
WHERE
    intrc.via = 'whatsApp'
    AND intrc.output.message.content NOT LIKE '%Mensagem automática do QuintoAndar%'
    AND ts_created LIKE '2021%'