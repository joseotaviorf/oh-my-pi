WITH unnested_dispatches AS (
    SELECT
        id AS id_dispatch,
        EXPLODE(FROM_JSON(customers,'array<string>')) AS customer
    FROM datalake_tracksale.dispatch
),
clean_unnested_dispatches AS (
    SELECT
        id_dispatch,
        LOWER(GET_JSON_OBJECT(customer,'$.name')) AS customer_name,
        LOWER(GET_JSON_OBJECT(customer,'$.email')) AS customer_email,
        REGEXP_REPLACE(REGEXP_REPLACE(GET_JSON_OBJECT(customer,'$.phone'),'\\D+',''),'^55','') AS customer_phone
    FROM unnested_dispatches
),
answer_keys AS (
  SELECT
    id_answer,
    MAX(CASE 
          WHEN tag_name = 'User Id' THEN CAST(tag_value AS BIGINT)
        END
    ) AS id_user,
    MAX(CASE 
          WHEN tag_name = 'CPF' THEN tag_value
        END
    ) AS cpf
  FROM 
    datalake_tracksale.answer_tags
  WHERE
    tag_name IN ('User Id','CPF')
  GROUP BY 1
),
ebdb_user AS (
  SELECT DISTINCT
    ak.id_answer,
    ak.id_user,
    u.uuid_person
  FROM 
    answer_keys AS ak
  INNER JOIN 
    datalake_ebdb_clean.user u
      ON ak.id_user = u.id
),
ebdb_cpf AS (
  SELECT DISTINCT
    ak.id_answer,
    ak.cpf
  FROM
    answer_keys ak
  INNER JOIN datalake_ebdb_customer_contact_identification.customer_contact_identification cci
    ON ak.cpf = cci.cpf
), 
dispatch_customers_user_id AS (
    SELECT DISTINCT
      id_dispatch,
      customer_name,
      customer_email,
      customer_phone,
      COALESCE(du.id, cci_e.id_user, cci_p.id_user, '-1') as id_user
    FROM clean_unnested_dispatches AS cud
    LEFT JOIN datalake_ebdb_user.user AS du
      ON LOWER(du.email) = LOWER(cud.customer_email)
      AND SUBSTRING(du.main_phone, 4) = COALESCE(REGEXP_REPLACE(COALESCE(cud.customer_phone),'\\D+',''),'')
      AND LOWER(du.name) = LOWER(cud.customer_name)
    LEFT JOIN datalake_ebdb_customer_contact_identification.customer_contact_identification cci_p
      ON REGEXP_REPLACE(REGEXP_REPLACE(cci_p.customer_contact,'\\D+',''),'^55','') = COALESCE(REGEXP_REPLACE(COALESCE(cud.customer_phone),'\\D+',''),'')
      AND cci_p.channel = 'phone'
    LEFT JOIN datalake_ebdb_customer_contact_identification.customer_contact_identification cci_e
      ON LOWER(cci_e.customer_contact) = LOWER(cud.customer_email)
      AND cci_e.channel = 'email'
), 
dispatch_customers AS (
  SELECT 
    f.id_dispatch,
    f.customer_email,
    f.customer_name,
    f.customer_phone,
    CASE 
      WHEN CONCAT(
                COALESCE(f.customer_email,''),
                COALESCE(f.customer_phone,''),
                COALESCE(f.customer_name,'')
                ) = '' 
        THEN '-1'
		  ELSE CONCAT(
		  COALESCE(f.customer_email,''),
		  COALESCE(f.customer_phone,''),
		  COALESCE(f.customer_name,'')
		  )
		END AS id_customer,
    f.id_user,
    u.uuid_person
  FROM 
    dispatch_customers_user_id AS f
  LEFT JOIN 
    datalake_ebdb_user.user AS u
    ON f.id_user = u.id), 
answers_user_id AS (
  SELECT
    a.id AS id_answer,
    a.lot_code AS id_dispatch,
    CASE WHEN CONCAT(
                  COALESCE(LOWER(a.email),''),
                  COALESCE(REGEXP_REPLACE(COALESCE(NULLIF(a.phone,''), a.alternative_phone),'\\D+',''),''),
                  COALESCE(LOWER(a.name),'')
                  ) = '' THEN '-1'
		ELSE CONCAT(
                  COALESCE(LOWER(a.email),''),
                  COALESCE(REGEXP_REPLACE(COALESCE(NULLIF(a.phone,''),a.alternative_phone),'\\D+',''),''),
                  COALESCE(LOWER(a.name),'')
                  )
		END AS id_customer,
		a.email,
		phone,
    MAX(COALESCE(du.id, eu.id_user, cci_e.id_user, cci_p.id_user, '-1')) as id_user
  FROM 
    datalake_tracksale.answer AS a
  LEFT JOIN datalake_ebdb_user.user AS du
    ON LOWER(du.email) = LOWER(a.email)
    AND SUBSTRING(du.main_phone, 4) = COALESCE(REGEXP_REPLACE(COALESCE(NULLIF(a.phone,''),a.alternative_phone),'\\D+',''),'')
    AND LOWER(du.name) = LOWER(a.name)
  LEFT JOIN ebdb_user eu
    ON eu.id_answer = a.id
  LEFT JOIN ebdb_cpf ec
    ON ec.id_answer = a.id
  LEFT JOIN datalake_ebdb_customer_contact_identification.customer_contact_identification cci_p
    ON REGEXP_REPLACE(REGEXP_REPLACE(cci_p.customer_contact,'\\D+',''),'^55','') = COALESCE(REGEXP_REPLACE(COALESCE(NULLIF(a.phone,''),a.alternative_phone),'\\D+',''),'')
    AND cci_p.channel = 'phone'
  LEFT JOIN datalake_ebdb_customer_contact_identification.customer_contact_identification cci_e
    ON LOWER(cci_e.customer_contact) = LOWER(a.email)
    AND cci_e.channel = 'email'
  GROUP BY
  1, 2, 3, 4, 5),
  answers AS (
  SELECT 
  	f.id_answer,
    f.id_dispatch,
    f.id_customer,
    f.id_user,
	  u.uuid_person
  FROM 
    answers_user_id AS f
  LEFT JOIN datalake_ebdb_user.user AS u
    ON f.id_user = u.id), 
-- consider only the last answer for each customer in a dispatch that was identified
last_dispatch_answers AS (
      SELECT
        id_dispatch,
        uuid_person,
        id_customer,
        id_user AS id_user,
        MAX(id_answer) AS id_last_answer
  FROM 
    answers
  WHERE 
    WHERE id_customer != '-1'
  GROUP BY 
    1, 2, 3, 4),
  answer_customers AS (
SELECT
    a.id_answer,
    a.id_dispatch,
    a.uuid_person,
    a.id_user,
    a.id_customer
  FROM
    answers a
  INNER JOIN last_dispatch_answers lda
    ON lda.id_last_answer = a.id_answer),
all_answers AS (
  SELECT 
    * 
  FROM 
    answer_customers
  UNION ALL
  SELECT 
    id_answer,
    id_dispatch,
    uuid_person,
    id_user,
    id_customer
  FROM 
    answers
  WHERE 
    id_customer = '-1')
  SELECT
    CONCAT(
      dc.id_dispatch,
      COALESCE(dc.id_customer,CAST(ac.id_answer AS STRING))
      ) AS id_dispatch,
    CONCAT(
          dc.id_dispatch,
          COALESCE(dc.uuid_person,CAST(ac.id_answer AS STRING), '-1')
          ) AS id_dispatch_user,
    COALESCE(dc.id_dispatch, d.id, '-1') AS id_dispatch_lot,
    dc.uuid_person,
    dc.id_user,
    dc.id_customer,
    dc.customer_email,
    dc.customer_phone,
    ac.id_answer,
    COALESCE(dc.uuid_person != '-1',false) AS is_customer_identified,
    c.customer_type,
    CASE
      WHEN d.ts_created IS NOT NULL 
      THEN 'Finalizado'
      ELSE d.status
    END AS status,
    d.id_campaign,
    d.ts_created AS ts_dispatch_created
  FROM 
    all_answers AS ac
FULL JOIN dispatch_customers dc
	ON dc.id_dispatch = ac.id_dispatch
	AND dc.id_customer = ac.id_customer
LEFT JOIN datalake_tracksale.dispatch d -- complete dispatch information in answers that could not relate to dispatches
	ON d.id = ac.id_dispatch
LEFT JOIN datalake_tracksale.campaign AS c
  ON c.id = d.id_campaign
