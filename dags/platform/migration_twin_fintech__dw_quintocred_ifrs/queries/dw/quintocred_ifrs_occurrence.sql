WITH base_inadimplecia_garantia AS (
    WITH cpf_cnpj_person AS (
        SELECT
            sk_propose,
            document,
            ROW_NUMBER() OVER (PARTITION BY sk_propose ORDER BY document) AS rn
        FROM
            dw_velo.bridge_velo_propose_person AS ps
        LEFT JOIN
            dw_velo.dim_velo_propose_person AS per
                ON per.sk_person = ps.sk_person
        WHERE
            ps.is_primary_person
    ),
    delinquency_entry AS (
        SELECT
        d.id AS id_delinquency,
        entry.id AS id_delinquency_entry,
        entry.bill_item,
        entry.value AS entry_value,
        CASE
            WHEN d.amount_paid - d.original_value >= 0 THEN entry.value
            WHEN d.amount_paid>0 THEN (entry.value/d.original_value)*d.amount_paid
        END AS paid_amount_entry
    FROM
        datalake_rental_guarantee_platform_clean.delinquency d
    LEFT JOIN
        datalake_rental_guarantee_platform_clean.delinquency_entry entry
            ON d.id = entry.id_delinquency
    WHERE
        is_active = true

        AND (d.id < 15 OR d.id >= 5000000)
        AND id_type IN (1,2)
    ),
    delinquency_20_ajustada AS (
        SELECT
            d.id,
            d.id_propose,
            IF( round(value) = round(original_value), original_value - ((d.original_value*11)/111), original_value ) AS original_value_ajustado
        FROM
            datalake_rental_guarantee_platform_clean.delinquency d
        WHERE
            is_active
            AND id_type IN (1,2)
            AND id > 15
            AND d.id < 5000000
    )
    SELECT DISTINCT
        d.id_propose AS sk_propose,
        d.id AS sk_delinquency,
        entry.id_delinquency_entry AS sk_delinquency_entry,
        d.id_status,
        d.id_type,
        doc.document AS client_cpf_cnpj,
        DATE_TRUNC('day',d.ts_created) AS dt_register,
        d.dt_due,
        d.dt_paid,
        DATE_DIFF(COALESCE(d.dt_paid,current_date),d.dt_due) AS dias_atraso,

        d.original_value AS due_amount_delinquency,
        d.amount_paid AS paid_amount_delinquency,
        IF( d.id_status IN (3,7) OR d.original_value - d.amount_paid < 0, 0, d.original_value - d.amount_paid) AS net_amount_delinquency,
        IF( d.id_status IN (3,7) AND amount_paid < original_value, original_value - amount_paid,NULL) AS discount_value_delinquency,
        IF( d.id_type = 0, d.original_value, COALESCE(entry.entry_value,d.original_value)) AS due_amount_entry,
        IF( d.id_type = 0, d.original_value, COALESCE(entry.entry_value,COALESCE(d2.original_value_ajustado,d.original_value))) AS due_amount_entry_ajustado,
        IF( d.id_type = 0, d.amount_paid, COALESCE(entry.paid_amount_entry, d.amount_paid)) AS paid_amount_entry,
        CASE
            WHEN d.id_status IN (3,7) OR d.original_value - d.amount_paid < 0 THEN 0
            WHEN d.id_type = 0 THEN d.original_value - d.amount_paid
            ELSE (COALESCE(entry.entry_value,d.original_value) - COALESCE(COALESCE(entry.paid_amount_entry,d.amount_paid ),0))
        END AS net_amount_entry,
        CASE
            WHEN d.id_status IN (3,7) OR d.original_value - d.amount_paid < 0 THEN 0
            WHEN d.id_type = 0 THEN d.original_value - d.amount_paid
            ELSE (COALESCE(entry.entry_value,COALESCE(d2.original_value_ajustado,d.original_value)) - COALESCE(COALESCE(entry.paid_amount_entry,d.amount_paid ),0))
        END AS net_amount_entry_ajustado,
        CASE
            WHEN d.id_status IN (3,7) AND amount_paid < original_value THEN abs(original_value - amount_paid)
            WHEN d.id_status IN (3,7) AND COALESCE(entry.paid_amount_entry,0) < entry.entry_value THEN abs(entry.entry_value - COALESCE(entry.paid_amount_entry,0))
        END AS discount_value_entry,
        CASE
            WHEN id_type = 0 THEN 'Assinatura'
            WHEN id_type = 1 THEN 'Garantia'
            WHEN id_type = 2 THEN 'Rescisão'
        END AS provisional_group,
        entry.bill_item,
        IF( d.id_status = 7, true, false) AS is_perdao_divida,
        IF( entry.bill_item = 'REALTY_DAMAGE', true, false) AS is_danos_imovel,
        IF( p.is_contract AND p.dt_ended is null, true, false) AS is_contract_active,
        p.dt_contract_started,
        p.dt_ended_official AS dt_contract_ended,
        vp.total_package_amount AS valor_pacote
    FROM
        datalake_rental_guarantee_platform_clean.delinquency d
    LEFT JOIN
        delinquency_entry entry
            ON d.id = entry.id_delinquency
    LEFT JOIN
        delinquency_20_ajustada d2
            ON d2.id = d.id
    LEFT JOIN
        datalake_rental_guarantee_platform_clean.delinquency_has_agreement da
            ON d.id = da.id_delinquency
    LEFT JOIN
        datalake_rental_guarantee_platform_clean.agreement a
            ON da.id_agreement = a.id
    LEFT JOIN
        datalake_rental_guarantee_platform_clean.agreement_payment ap
            ON ap.id_agreement = a.id
    LEFT JOIN
        cpf_cnpj_person doc
            ON doc.sk_propose = d.id_propose AND rn = 1
    LEFT JOIN
        dw_velo.fact_velo_propose	p
            ON d.id_propose = p.sk_propose
    LEFT JOIN
        dw_velo.dim_velo_propose_values vp
            ON p.sk_propose_values = vp.sk_propose_values
    WHERE
        d.is_active = true
)
SELECT DISTINCT
    "delinquency" AS origin_table,
    CAST(sk_propose AS STRING) AS sk_propose,
    CAST(NULL AS LONG) AS sk_propose_20,
    sk_delinquency,
    CAST(COALESCE(sk_delinquency_entry, sk_delinquency) AS STRING) AS sk_transaction,
    client_cpf_cnpj,
    dt_register,
    IF( (sk_delinquency< 15 OR sk_delinquency >= 5000000), dt_register, dt_due) AS dt_register_ajustada,
    dt_due,
    dt_paid,
    dias_atraso,
    CAST(due_amount_entry AS DOUBLE) AS due_amount,
    CAST(due_amount_entry_ajustado AS DOUBLE) AS due_amount_ajustado,
    CAST(paid_amount_entry AS DOUBLE) AS paid_amount,
    CAST(net_amount_entry AS DOUBLE) AS open_amount,
    CAST(net_amount_entry_ajustado AS DOUBLE) AS open_amount_ajustado,
    CAST(discount_value_entry AS DOUBLE) AS discount_value,
    bill_item,
    provisional_group,
    is_danos_imovel,
    is_contract_active,
    dt_contract_started,
    dt_contract_ended,
    valor_pacote,
    CAST('false' AS BOOLEAN) AS is_delinquency_renovacao,
    is_perdao_divida,
    NOW() AS ts_load
FROM
    base_inadimplecia_garantia
WHERE
    provisional_group IN ('Garantia','Rescisão')
