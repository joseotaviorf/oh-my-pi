WITH
amenities AS (
  WITH
  most_recent_amenities AS (
    SELECT
      i.id_house AS imovel_id,
      i.id_amenities AS amenidades_id ,
      i.has_characteristic AS temcaracteristica,
      a.slug,
      ROW_NUMBER() OVER(PARTITION BY i.id_house, i.id_amenities ORDER BY i.ts_updated DESC) AS rn
    FROM datalake_ebdb_clean.info_amenities i
    JOIN datalake_ebdb_clean.amenities a ON i.id_amenities = a.id
  )
  SELECT
    imovel_id as id_house,
    filter(collect_list(CASE WHEN temcaracteristica = true THEN amenidades_id ELSE NULL END), x -> x IS NOT NULL) as amenities_with,
    filter(collect_list(CASE WHEN temcaracteristica = false THEN amenidades_id ELSE NULL END), x -> x IS NOT NULL) as amenities_without
  FROM most_recent_amenities
  WHERE rn = 1
  GROUP BY 1
),

condo_amenities AS (
  WITH
  most_recent_condo_amenities AS (
    SELECT
      i.id_house AS imovel_id,
      i.id_condo_amenities AS instalacao_id,
      i.has_characteristic AS temcaracteristica,
      a.slug,
      ROW_NUMBER() OVER(PARTITION BY i.id_house, i.id_condo_amenities ORDER BY i.ts_updated DESC) AS rn
    FROM datalake_ebdb_clean.info_condo_amenities i
    JOIN datalake_ebdb_clean.condo_amenities a ON i.id_condo_amenities = a.id_condo_amenity
  )
  SELECT
    imovel_id as id_house,
    filter(collect_list(CASE WHEN temcaracteristica = true THEN instalacao_id ELSE NULL END), x -> x IS NOT NULL) as condo_amenities_with,
    filter(collect_list(CASE WHEN temcaracteristica = false THEN instalacao_id ELSE NULL END), x -> x IS NOT NULL) as condo_amenities_without
  FROM most_recent_condo_amenities
  WHERE rn = 1
  GROUP BY 1
)

SELECT
    CAST(COALESCE(a.id_house,
             ca.id_house,
             house_condition.id_house) AS STRING )   AS id_house,
    CAST(CASE
        WHEN array_contains(amenities_with, 1)
        THEN 1
        ELSE CASE
                WHEN array_contains(amenities_without, 1)
                THEN 0
                ELSE NULL
                END
        END AS STRING) AS  hidromassagem,
   CAST(CASE
        WHEN array_contains(amenities_with, 2)
        THEN 1
        ELSE CASE
                WHEN array_contains(amenities_without, 2)
                THEN 0
                ELSE NULL
                END
        END AS STRING)AS  box_blindex,
    CAST(CASE
        WHEN array_contains(amenities_with, 3)
        THEN 1
        ELSE CASE
                WHEN array_contains(amenities_without, 3)
                THEN 0
                ELSE NULL
                END
        END                               AS STRING )AS  varanda,
    CAST(CASE
        WHEN array_contains(amenities_with, 4)
        THEN 1
        ELSE CASE
                WHEN array_contains(amenities_without, 4)
                THEN 0
                ELSE NULL
                END
        END                               AS STRING )AS  fogao_geladeira,
    CAST(CASE
        WHEN array_contains(amenities_with, 5)
        THEN 1
        ELSE CASE
                WHEN array_contains(amenities_without, 5)
                THEN 0
                ELSE NULL
                END
        END                               AS STRING )AS  piscina_privativa,
    CAST(CASE
        WHEN array_contains(amenities_with, 6)
        THEN 1
        ELSE CASE
                WHEN array_contains(amenities_without, 6)
                THEN 0
                ELSE NULL
                END
        END                               AS STRING )AS  churrasqueira_privativa,
    CAST(CASE
        WHEN array_contains(amenities_with, 7)
        THEN 1
        ELSE CASE
                WHEN array_contains(amenities_without, 7)
                THEN 0
                ELSE NULL
                END
        END                               AS STRING )AS  armarios_no_quarto,
    CAST(CASE
        WHEN array_contains(amenities_with, 8)
        THEN 1
        ELSE CASE
                WHEN array_contains(amenities_without, 8)
                THEN 0
                ELSE NULL
                END
        END                               AS STRING )AS  armarios_no_banheiro,
    CAST(CASE
        WHEN array_contains(amenities_with, 9)
        THEN 1
        ELSE CASE
                WHEN array_contains(amenities_without, 9)
                THEN 0
                ELSE NULL
                END
        END                               AS STRING )AS  armarios_na_cozinha,
    CAST(CASE
        WHEN array_contains(amenities_with, 10)
        THEN 1
        ELSE CASE
                WHEN array_contains(amenities_without, 10)
                THEN 0
                ELSE NULL
                END
        END                               AS STRING )AS  ar_condicionado,
    CAST(CASE
        WHEN array_contains(amenities_with, 11)
        THEN 1
        ELSE CASE
                WHEN array_contains(amenities_without, 11)
                THEN 0
                ELSE NULL
                END
        END                               AS STRING )AS  internet,
    CAST(CASE
        WHEN array_contains(amenities_with, 12)
        THEN 1
        ELSE CASE
                WHEN array_contains(amenities_without, 12)
                THEN 0
                ELSE NULL
                END
        END                               AS STRING )AS  chuveiro_a_gas,
    CAST(CASE
        WHEN array_contains(amenities_with, 13)
        THEN 1
        ELSE CASE
                WHEN array_contains(amenities_without, 13)
                THEN 0
                ELSE NULL
                END
        END                               AS STRING )AS  animais_de_estimacao,
    CAST(CASE
        WHEN array_contains(amenities_with, 14)
        THEN 1
        ELSE CASE
                WHEN array_contains(amenities_without, 14)
                THEN 0
                ELSE NULL
                END
        END                               AS STRING )AS  quarto_de_servico,
    CAST(CASE
        WHEN array_contains(amenities_with, 15)
        THEN 1
        ELSE CASE
                WHEN array_contains(amenities_without, 15)
                THEN 0
                ELSE NULL
                END
        END                               AS STRING )AS  banheiro_de_servico,
    CAST(CASE
        WHEN array_contains(amenities_with, 16)
        THEN 1
        ELSE CASE
                WHEN array_contains(amenities_without, 16)
                THEN 0
                ELSE NULL
                END
        END                               AS STRING )AS  garagem_fixa,
    CAST(CASE
        WHEN array_contains(amenities_with, 17)
        THEN 1
        ELSE CASE
                WHEN array_contains(amenities_without, 17)
                THEN 0
                ELSE NULL
                END
        END                               AS STRING )AS  varanda_gourmet,
    CAST(CASE
        WHEN array_contains(amenities_with, 18)
        THEN 1
        ELSE CASE
                WHEN array_contains(amenities_without, 18)
                THEN 0
                ELSE NULL
                END
        END                               AS STRING )AS  apartamento_cobertura,
    CAST(CASE
        WHEN array_contains(amenities_with, 19)
        THEN 1
        ELSE CASE
                WHEN array_contains(amenities_without, 19)
                THEN 0
                ELSE NULL
                END
        END                               AS STRING )AS  quarto_extra_reversivel,
    CAST(CASE
        WHEN array_contains(amenities_with, 20)
        THEN 1
        ELSE CASE
                WHEN array_contains(amenities_without, 20)
                THEN 0
                ELSE NULL
                END
        END                               AS STRING )AS  fogao,
    CAST(CASE
        WHEN array_contains(amenities_with, 21)
        THEN 1
        ELSE CASE
                WHEN array_contains(amenities_without, 21)
                THEN 0
                ELSE NULL
                END
        END                               AS STRING )AS  geladeira,
    CAST(CASE
        WHEN array_contains(amenities_with, 22)
        THEN 1
        ELSE CASE
                WHEN array_contains(amenities_without, 22)
                THEN 0
                ELSE NULL
                END
        END                               AS STRING )AS  sol_da_manha,
    CAST(CASE
        WHEN array_contains(amenities_with, 23)
        THEN 1
        ELSE CASE
                WHEN array_contains(amenities_without, 23)
                THEN 0
                ELSE NULL
                END
        END                               AS STRING )AS  sol_da_tarde,
    CAST(CASE
        WHEN array_contains(amenities_with, 24)
        THEN 1
        ELSE CASE
                WHEN array_contains(amenities_without, 24)
                THEN 0
                ELSE NULL
                END
        END                               AS STRING )AS  cortinas_black_out,
    CAST(CASE
        WHEN array_contains(amenities_with, 25)
        THEN 1
        ELSE CASE
                WHEN array_contains(amenities_without, 25)
                THEN 0
                ELSE NULL
                END
        END                               AS STRING )AS  cortinas_decorativas,
    CAST(CASE
        WHEN array_contains(amenities_with, 26)
        THEN 1
        ELSE CASE
                WHEN array_contains(amenities_without, 26)
                THEN 0
                ELSE NULL
                END
        END                               AS STRING )AS  janela_anti_ruido,
    CAST(CASE
        WHEN array_contains(amenities_with, 27)
        THEN 1
        ELSE CASE
                WHEN array_contains(amenities_without, 27)
                THEN 0
                ELSE NULL
                END
        END                               AS STRING )AS  ventilador_de_teto,
    CAST(CASE
        WHEN array_contains(amenities_with, 28)
        THEN 1
        ELSE CASE
                WHEN array_contains(amenities_without, 28)
                THEN 0
                ELSE NULL
                END
        END                               AS STRING )AS  luminosidade_natural,
    CAST(CASE
        WHEN array_contains(amenities_with, 29)
        THEN 1
        ELSE CASE
                WHEN array_contains(amenities_without, 29)
                THEN 0
                ELSE NULL
                END
        END                               AS STRING )AS  vista_livre,
    CAST(CASE
        WHEN array_contains(amenities_with, 30)
        THEN 1
        ELSE CASE
                WHEN array_contains(amenities_without, 30)
                THEN 0
                ELSE NULL
                END
        END                               AS STRING )AS  rua_silenciosa,
    CAST(CASE
        WHEN array_contains(amenities_with, 31)
        THEN 1
        ELSE CASE
                WHEN array_contains(amenities_without, 31)
                THEN 0
                ELSE NULL
                END
        END                               AS STRING )AS  chuveiro_eletrico,
    CAST(CASE
        WHEN array_contains(amenities_with, 32)
        THEN 1
        ELSE CASE
                WHEN array_contains(amenities_without, 32)
                THEN 0
                ELSE NULL
                END
        END                               AS STRING )AS  microondas,
    CAST(CASE
        WHEN array_contains(amenities_with, 33)
        THEN 1
        ELSE CASE
                WHEN array_contains(amenities_without, 33)
                THEN 0
                ELSE NULL
                END
        END                               AS STRING )AS  sofa,
    CAST(CASE
        WHEN array_contains(amenities_with, 34)
        THEN 1
        ELSE CASE
                WHEN array_contains(amenities_without, 34)
                THEN 0
                ELSE NULL
                END
        END                               AS STRING )AS  maquina_de_lavar,
    CAST(CASE
        WHEN array_contains(amenities_with, 35)
        THEN 1
        ELSE CASE
                WHEN array_contains(amenities_without, 35)
                THEN 0
                ELSE NULL
                END
        END                               AS STRING )AS  secadora,
    CAST(CASE
        WHEN array_contains(amenities_with, 36)
        THEN 1
        ELSE CASE
                WHEN array_contains(amenities_without, 36)
                THEN 0
                ELSE NULL
                END
        END                               AS STRING )AS  lava_e_seca,
    CAST(CASE
        WHEN array_contains(amenities_with, 37)
        THEN 1
        ELSE CASE
                WHEN array_contains(amenities_without, 37)
                THEN 0
                ELSE NULL
                END
        END                               AS STRING )AS  tanque,
    CAST(CASE
        WHEN array_contains(amenities_with, 38)
        THEN 1
        ELSE CASE
                WHEN array_contains(amenities_without, 38)
                THEN 0
                ELSE NULL
                END
        END                               AS STRING )AS  rede_de_protecao,
    CAST(CASE
        WHEN array_contains(amenities_with, 39)
        THEN 1
        ELSE CASE
                WHEN array_contains(amenities_without, 39)
                THEN 0
                ELSE NULL
                END
        END                               AS STRING )AS  varal_de_roupas,
    CAST(CASE
        WHEN array_contains(amenities_with, 40)
        THEN 1
        ELSE CASE
                WHEN array_contains(amenities_without, 40)
                THEN 0
                ELSE NULL
                END
        END                               AS STRING )AS  tomadas_novas,
    CAST(CASE
        WHEN array_contains(amenities_with, 41)
        THEN 1
        ELSE CASE
                WHEN array_contains(amenities_without, 41)
                THEN 0
                ELSE NULL
                END
        END                               AS STRING )AS  televisao,
    CAST(CASE
        WHEN array_contains(amenities_with, 42)
        THEN 1
        ELSE CASE
                WHEN array_contains(amenities_without, 42)
                THEN 0
                ELSE NULL
                END
        END                               AS STRING )AS  mesa_e_cadeiras,
    CAST(CASE
        WHEN array_contains(amenities_with, 43)
        THEN 1
        ELSE CASE
                WHEN array_contains(amenities_without, 43)
                THEN 0
                ELSE NULL
                END
        END                               AS STRING )AS  cafeteira,
    CAST(CASE
        WHEN array_contains(amenities_with, 44)
        THEN 1
        ELSE CASE
                WHEN array_contains(amenities_without, 44)
                THEN 0
                ELSE NULL
                END
        END                               AS STRING )AS  churrasqueira,
    CAST(CASE
        WHEN array_contains(amenities_with, 45)
        THEN 1
        ELSE CASE
                WHEN array_contains(amenities_without, 45)
                THEN 0
                ELSE NULL
                END
        END                               AS STRING )AS  acesso_sem_degraus,
    CAST(CASE
        WHEN array_contains(amenities_with, 46)
        THEN 1
        ELSE CASE
                WHEN array_contains(amenities_without, 46)
                THEN 0
                ELSE NULL
                END
        END                               AS STRING )AS  cooktop,
    CAST(CASE
        WHEN array_contains(amenities_with, 47)
        THEN 1
        ELSE CASE
                WHEN array_contains(amenities_without, 47)
                THEN 0
                ELSE NULL
                END
        END                               AS STRING )AS  utensilios_de_cozinha,
    CAST(CASE
        WHEN array_contains(amenities_with, 48)
        THEN 1
        ELSE CASE
                WHEN array_contains(amenities_without, 48)
                THEN 0
                ELSE NULL
                END
        END                               AS STRING )AS  cama_de_casal,
    CAST(CASE
        WHEN array_contains(amenities_with, 49)
        THEN 1
        ELSE CASE
                WHEN array_contains(amenities_without, 49)
                THEN 0
                ELSE NULL
                END
        END                               AS STRING )AS  cama_de_solteiro,
    CAST(CASE
        WHEN array_contains(amenities_with, 50)
        THEN 1
        ELSE CASE
                WHEN array_contains(amenities_without, 50)
                THEN 0
                ELSE NULL
                END
        END                               AS STRING )AS  espelho_no_banheiro,
    CAST(CASE
        WHEN array_contains(amenities_with, 51)
        THEN 1
        ELSE CASE
                WHEN array_contains(amenities_without, 51)
                THEN 0
                ELSE NULL
                END
        END                               AS STRING )AS  fechadura_eletronica,
    CAST(CASE
        WHEN array_contains(amenities_with, 52)
        THEN 1
        ELSE CASE
                WHEN array_contains(amenities_without, 52)
                THEN 0
                ELSE NULL
                END
        END                               AS STRING )AS  energia,
    CAST(CASE
        WHEN array_contains(condo_amenities_with, 1)
        THEN 1
        ELSE CASE
                WHEN array_contains(condo_amenities_without, 1)
                THEN 0
                ELSE NULL
                END
        END                               AS STRING )AS  playground,
    CAST(CASE
        WHEN array_contains(condo_amenities_with, 2)
        THEN 1
        ELSE CASE
                WHEN array_contains(condo_amenities_without, 2)
                THEN 0
                ELSE NULL
                END
        END                               AS STRING )AS  piscina_no_condominio,
    CAST(CASE
        WHEN array_contains(condo_amenities_with, 3)
        THEN 1
        ELSE CASE
                WHEN array_contains(condo_amenities_without, 3)
                THEN 0
                ELSE NULL
                END
        END                               AS STRING )AS  churrasqueira_no_condominio,
    CAST(CASE
        WHEN array_contains(condo_amenities_with, 4)
        THEN 1
        ELSE CASE
                WHEN array_contains(condo_amenities_without, 4)
                THEN 0
                ELSE NULL
                END
        END                               AS STRING )AS  quadra_esportiva,
    CAST(CASE
        WHEN array_contains(condo_amenities_with, 5)
        THEN 1
        ELSE CASE
                WHEN array_contains(condo_amenities_without, 5)
                THEN 0
                ELSE NULL
                END
        END                               AS STRING )AS  academia,
    CAST(CASE
        WHEN array_contains(condo_amenities_with, 6)
        THEN 1
        ELSE CASE
                WHEN array_contains(condo_amenities_without, 6)
                THEN 0
                ELSE NULL
                END
        END                               AS STRING )AS  salao_de_festas,
    CAST(CASE
        WHEN array_contains(condo_amenities_with, 7)
        THEN 1
        ELSE CASE
                WHEN array_contains(condo_amenities_without, 7)
                THEN 0
                ELSE NULL
                END
        END                               AS STRING )AS  sauna,
    CAST(CASE
        WHEN array_contains(condo_amenities_with, 8)
        THEN 1
        ELSE CASE
                WHEN array_contains(condo_amenities_without, 8)
                THEN 0
                ELSE NULL
                END
        END                               AS STRING )AS  lavanderia,
    CAST(CASE
        WHEN array_contains(condo_amenities_with, 9)
        THEN 1
        ELSE CASE
                WHEN array_contains(condo_amenities_without, 9)
                THEN 0
                ELSE NULL
                END
        END                               AS STRING )AS  gas_encanado,
    CAST(CASE
        WHEN array_contains(condo_amenities_with, 10)
        THEN 1
        ELSE CASE
                WHEN array_contains(condo_amenities_without, 10)
                THEN 0
                ELSE NULL
                END
        END                               AS STRING )AS  portao_automatico,
    CAST(CASE
        WHEN array_contains(condo_amenities_with, 11)
        THEN 1
        ELSE CASE
                WHEN array_contains(condo_amenities_without, 11)
                THEN 0
                ELSE NULL
                END
        END                               AS STRING )AS  espaco_gourmet,
    CAST(CASE
        WHEN array_contains(condo_amenities_with, 12)
        THEN 1
        ELSE CASE
                WHEN array_contains(condo_amenities_without, 12)
                THEN 0
                ELSE NULL
                END
        END                               AS STRING ) AS  perto_do_metro,
    house_condition.maintenance_condition  AS  house_condition,
    CAST(NOW() AS STRING) AS ts_load
FROM amenities a
FULL JOIN condo_amenities ca
  ON a.id_house = ca.id_house
FULL JOIN datalake_ebdb_clean.house_maintenance_condition house_condition
  ON COALESCE(a.id_house, ca.id_house) = house_condition.id_house
