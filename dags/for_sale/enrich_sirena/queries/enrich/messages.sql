with agents_class AS (
    SELECT
        gr.group_name,
        ag.id,
        row_number() OVER (
            PARTITION BY ag.id
            ORDER BY
                CASE
                    WHEN gr.group_name = 'QuintoAndar Admin' THEN 0
                    WHEN gr.group_name = 'Deal Making' THEN 1
                    WHEN gr.group_name = 'Closing' THEN 2
                    WHEN gr.group_name = 'Casa Mineira' THEN 4
                    WHEN gr.group_name = 'QuintoAndar' THEN 5
                    ELSE 6
                END DESC,
                gr.group_name,
                gr.display_name
            ) AS num_line
    FROM
        datalake_sirena_clean.agents as ag
    INNER JOIN
        datalake_sirena_clean.groups AS gr
            ON ag.id_group = gr.id
),
agent_info AS (
    SELECT
        ag.id,
        ag.first_name,
        ag.last_name,
        ag.phone,
        ag.email
    FROM
        datalake_sirena_clean.agents as ag
    GROUP BY
        ag.id,
        ag.first_name,
        ag.last_name,
        ag.phone,
        ag.email
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
    ac.group_name,
    ai.first_name AS agent_first_name,
    ai.last_name AS agent_last_name,
    ai.phone AS agent_phone,
    ai.email AS agent_email,
    intrc.via,
    CASE
        WHEN intrc.output.message.attachment.type IS NOT NULL
            THEN 'Anexo'
        ELSE 'Texto'
    END AS message_type,
    intrc.output.message.template,
    CASE intrc.output.message.attachment.type
        WHEN 'AUDIO'
            THEN 'ANEXO - áudio'
        WHEN 'FILE'
            THEN 'ANEXO - arquivo'
        WHEN 'IMAGE'
            THEN 'ANEXO - imagem'
        WHEN 'VIDEO'
            THEN 'ANEXO - vídeo'
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
LEFT JOIN
    agent_info AS ai
        ON intrc.id_agent = ai.id
WHERE
    intrc.via = 'whatsApp'
    AND ac.num_line = 1
    AND (intrc.output.message.content NOT LIKE '%Mensagem automática do QuintoAndar%'
        OR intrc.output.message.attachment.type IS NOT NULL)
    AND ts_created >= '2021-01-01'
