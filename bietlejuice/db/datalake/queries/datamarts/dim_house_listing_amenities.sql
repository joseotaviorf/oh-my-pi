WITH
amenities AS (
  WITH
  most_recent_amenities AS (
    SELECT
      i.imovel_id,
      i.amenidades_id,
      i.temcaracteristica,
      a.slug,
      ROW_NUMBER() OVER(PARTITION BY i.imovel_id, i.amenidades_id ORDER BY i.atualizadoem DESC) AS rn
    FROM datalake_ebdb_raw_prod.amenidadesinfo i
    JOIN datalake_ebdb_raw_prod.amenidades a ON i.amenidades_id = a.id
  )
  SELECT
    imovel_id as id_house,
    filter(array_agg(CASE WHEN temcaracteristica = true THEN amenidades_id ELSE NULL END), x -> x IS NOT NULL) as amenities_with,
    filter(array_agg(CASE WHEN temcaracteristica = false THEN amenidades_id ELSE NULL END), x -> x IS NOT NULL) as amenities_without
  FROM most_recent_amenities
  WHERE rn = 1
  GROUP BY 1
),

condo_amenities AS (
  WITH
  most_recent_condo_amenities AS (
    SELECT
      i.imovel_id,
      i.instalacao_id,
      i.temcaracteristica,
      a.slug,
      ROW_NUMBER() OVER(PARTITION BY i.imovel_id, i.instalacao_id ORDER BY i.atualizadoem DESC) AS rn
    FROM datalake_ebdb_raw_prod.instalacaoinfo i
    JOIN datalake_ebdb_raw_prod.instalacao a ON i.instalacao_id = a.id
  )
  SELECT
    imovel_id as id_house,
    filter(array_agg(CASE WHEN temcaracteristica = true THEN instalacao_id ELSE NULL END), x -> x IS NOT NULL) as condo_amenities_with,
    filter(array_agg(CASE WHEN temcaracteristica = false THEN instalacao_id ELSE NULL END), x -> x IS NOT NULL) as condo_amenities_without
  FROM most_recent_condo_amenities
  WHERE rn = 1
  GROUP BY 1
)

SELECT
    COALESCE(a.id_house, 
             ca.id_house,
             house_condition.houseid)     AS id_house,
    CASE
        WHEN CONTAINS(amenities_with, 1)
        THEN 1
        ELSE CASE
                WHEN CONTAINS(amenities_without, 1)
                THEN 0
                ELSE NULL
                END
        END                               AS  hidromassagem,
    CASE
        WHEN CONTAINS(amenities_with, 2)
        THEN 1
        ELSE CASE
                WHEN CONTAINS(amenities_without, 2)
                THEN 0
                ELSE NULL
                END
        END                               AS  box_blindex,
    CASE
        WHEN CONTAINS(amenities_with, 3)
        THEN 1
        ELSE CASE
                WHEN CONTAINS(amenities_without, 3)
                THEN 0
                ELSE NULL
                END
        END                               AS  varanda,
    CASE
        WHEN CONTAINS(amenities_with, 4)
        THEN 1
        ELSE CASE
                WHEN CONTAINS(amenities_without, 4)
                THEN 0
                ELSE NULL
                END
        END                               AS  fogao_geladeira,
    CASE
        WHEN CONTAINS(amenities_with, 5)
        THEN 1
        ELSE CASE
                WHEN CONTAINS(amenities_without, 5)
                THEN 0
                ELSE NULL
                END
        END                               AS  piscina_privativa,
    CASE
        WHEN CONTAINS(amenities_with, 6)
        THEN 1
        ELSE CASE
                WHEN CONTAINS(amenities_without, 6)
                THEN 0
                ELSE NULL
                END
        END                               AS  churrasqueira_privativa,
    CASE
        WHEN CONTAINS(amenities_with, 7)
        THEN 1
        ELSE CASE
                WHEN CONTAINS(amenities_without, 7)
                THEN 0
                ELSE NULL
                END
        END                               AS  armarios_no_quarto,
    CASE
        WHEN CONTAINS(amenities_with, 8)
        THEN 1
        ELSE CASE
                WHEN CONTAINS(amenities_without, 8)
                THEN 0
                ELSE NULL
                END
        END                               AS  armarios_no_banheiro,
    CASE
        WHEN CONTAINS(amenities_with, 9)
        THEN 1
        ELSE CASE
                WHEN CONTAINS(amenities_without, 9)
                THEN 0
                ELSE NULL
                END
        END                               AS  armarios_na_cozinha,
    CASE
        WHEN CONTAINS(amenities_with, 10)
        THEN 1
        ELSE CASE
                WHEN CONTAINS(amenities_without, 10)
                THEN 0
                ELSE NULL
                END
        END                               AS  ar_condicionado,
    CASE
        WHEN CONTAINS(amenities_with, 11)
        THEN 1
        ELSE CASE
                WHEN CONTAINS(amenities_without, 11)
                THEN 0
                ELSE NULL
                END
        END                               AS  internet,
    CASE
        WHEN CONTAINS(amenities_with, 12)
        THEN 1
        ELSE CASE
                WHEN CONTAINS(amenities_without, 12)
                THEN 0
                ELSE NULL
                END
        END                               AS  chuveiro_a_gas,
    CASE
        WHEN CONTAINS(amenities_with, 13)
        THEN 1
        ELSE CASE
                WHEN CONTAINS(amenities_without, 13)
                THEN 0
                ELSE NULL
                END
        END                               AS  animais_de_estimacao,
    CASE
        WHEN CONTAINS(amenities_with, 14)
        THEN 1
        ELSE CASE
                WHEN CONTAINS(amenities_without, 14)
                THEN 0
                ELSE NULL
                END
        END                               AS  quarto_de_servico,
    CASE
        WHEN CONTAINS(amenities_with, 15)
        THEN 1
        ELSE CASE
                WHEN CONTAINS(amenities_without, 15)
                THEN 0
                ELSE NULL
                END
        END                               AS  banheiro_de_servico,
    CASE
        WHEN CONTAINS(amenities_with, 16)
        THEN 1
        ELSE CASE
                WHEN CONTAINS(amenities_without, 16)
                THEN 0
                ELSE NULL
                END
        END                               AS  garagem_fixa,
    CASE
        WHEN CONTAINS(amenities_with, 17)
        THEN 1
        ELSE CASE
                WHEN CONTAINS(amenities_without, 17)
                THEN 0
                ELSE NULL
                END
        END                               AS  varanda_gourmet,
    CASE
        WHEN CONTAINS(amenities_with, 18)
        THEN 1
        ELSE CASE
                WHEN CONTAINS(amenities_without, 18)
                THEN 0
                ELSE NULL
                END
        END                               AS  apartamento_cobertura,
    CASE
        WHEN CONTAINS(amenities_with, 19)
        THEN 1
        ELSE CASE
                WHEN CONTAINS(amenities_without, 19)
                THEN 0
                ELSE NULL
                END
        END                               AS  quarto_extra_reversivel,
    CASE
        WHEN CONTAINS(amenities_with, 20)
        THEN 1
        ELSE CASE
                WHEN CONTAINS(amenities_without, 20)
                THEN 0
                ELSE NULL
                END
        END                               AS  fogao,
    CASE
        WHEN CONTAINS(amenities_with, 21)
        THEN 1
        ELSE CASE
                WHEN CONTAINS(amenities_without, 21)
                THEN 0
                ELSE NULL
                END
        END                               AS  geladeira,
    CASE
        WHEN CONTAINS(amenities_with, 22)
        THEN 1
        ELSE CASE
                WHEN CONTAINS(amenities_without, 22)
                THEN 0
                ELSE NULL
                END
        END                               AS  sol_da_manha,
    CASE
        WHEN CONTAINS(amenities_with, 23)
        THEN 1
        ELSE CASE
                WHEN CONTAINS(amenities_without, 23)
                THEN 0
                ELSE NULL
                END
        END                               AS  sol_da_tarde,
    CASE
        WHEN CONTAINS(amenities_with, 24)
        THEN 1
        ELSE CASE
                WHEN CONTAINS(amenities_without, 24)
                THEN 0
                ELSE NULL
                END
        END                               AS  cortinas_black_out,
    CASE
        WHEN CONTAINS(amenities_with, 25)
        THEN 1
        ELSE CASE
                WHEN CONTAINS(amenities_without, 25)
                THEN 0
                ELSE NULL
                END
        END                               AS  cortinas_decorativas,
    CASE
        WHEN CONTAINS(amenities_with, 26)
        THEN 1
        ELSE CASE
                WHEN CONTAINS(amenities_without, 26)
                THEN 0
                ELSE NULL
                END
        END                               AS  janela_anti_ruido,
    CASE
        WHEN CONTAINS(amenities_with, 27)
        THEN 1
        ELSE CASE
                WHEN CONTAINS(amenities_without, 27)
                THEN 0
                ELSE NULL
                END
        END                               AS  ventilador_de_teto,
    CASE
        WHEN CONTAINS(amenities_with, 28)
        THEN 1
        ELSE CASE
                WHEN CONTAINS(amenities_without, 28)
                THEN 0
                ELSE NULL
                END
        END                               AS  luminosidade_natural,
    CASE
        WHEN CONTAINS(amenities_with, 29)
        THEN 1
        ELSE CASE
                WHEN CONTAINS(amenities_without, 29)
                THEN 0
                ELSE NULL
                END
        END                               AS  vista_livre,
    CASE
        WHEN CONTAINS(amenities_with, 30)
        THEN 1
        ELSE CASE
                WHEN CONTAINS(amenities_without, 30)
                THEN 0
                ELSE NULL
                END
        END                               AS  rua_silenciosa,
    CASE
        WHEN CONTAINS(amenities_with, 31)
        THEN 1
        ELSE CASE
                WHEN CONTAINS(amenities_without, 31)
                THEN 0
                ELSE NULL
                END
        END                               AS  chuveiro_eletrico,
    CASE
        WHEN CONTAINS(amenities_with, 32)
        THEN 1
        ELSE CASE
                WHEN CONTAINS(amenities_without, 32)
                THEN 0
                ELSE NULL
                END
        END                               AS  microondas,
    CASE
        WHEN CONTAINS(amenities_with, 33)
        THEN 1
        ELSE CASE
                WHEN CONTAINS(amenities_without, 33)
                THEN 0
                ELSE NULL
                END
        END                               AS  sofa,
    CASE
        WHEN CONTAINS(amenities_with, 34)
        THEN 1
        ELSE CASE
                WHEN CONTAINS(amenities_without, 34)
                THEN 0
                ELSE NULL
                END
        END                               AS  maquina_de_lavar,
    CASE
        WHEN CONTAINS(amenities_with, 35)
        THEN 1
        ELSE CASE
                WHEN CONTAINS(amenities_without, 35)
                THEN 0
                ELSE NULL
                END
        END                               AS  secadora,
    CASE
        WHEN CONTAINS(amenities_with, 36)
        THEN 1
        ELSE CASE
                WHEN CONTAINS(amenities_without, 36)
                THEN 0
                ELSE NULL
                END
        END                               AS  lava_e_seca,
    CASE
        WHEN CONTAINS(amenities_with, 37)
        THEN 1
        ELSE CASE
                WHEN CONTAINS(amenities_without, 37)
                THEN 0
                ELSE NULL
                END
        END                               AS  tanque,
    CASE
        WHEN CONTAINS(amenities_with, 38)
        THEN 1
        ELSE CASE
                WHEN CONTAINS(amenities_without, 38)
                THEN 0
                ELSE NULL
                END
        END                               AS  rede_de_protecao,
    CASE
        WHEN CONTAINS(amenities_with, 39)
        THEN 1
        ELSE CASE
                WHEN CONTAINS(amenities_without, 39)
                THEN 0
                ELSE NULL
                END
        END                               AS  varal_de_roupas,
    CASE
        WHEN CONTAINS(amenities_with, 40)
        THEN 1
        ELSE CASE
                WHEN CONTAINS(amenities_without, 40)
                THEN 0
                ELSE NULL
                END
        END                               AS  tomadas_novas,
    CASE
        WHEN CONTAINS(amenities_with, 41)
        THEN 1
        ELSE CASE
                WHEN CONTAINS(amenities_without, 41)
                THEN 0
                ELSE NULL
                END
        END                               AS  televisao,
    CASE
        WHEN CONTAINS(amenities_with, 42)
        THEN 1
        ELSE CASE
                WHEN CONTAINS(amenities_without, 42)
                THEN 0
                ELSE NULL
                END
        END                               AS  mesa_e_cadeiras,
    CASE
        WHEN CONTAINS(amenities_with, 43)
        THEN 1
        ELSE CASE
                WHEN CONTAINS(amenities_without, 43)
                THEN 0
                ELSE NULL
                END
        END                               AS  cafeteira,
    CASE
        WHEN CONTAINS(amenities_with, 44)
        THEN 1
        ELSE CASE
                WHEN CONTAINS(amenities_without, 44)
                THEN 0
                ELSE NULL
                END
        END                               AS  churrasqueira,
    CASE
        WHEN CONTAINS(amenities_with, 45)
        THEN 1
        ELSE CASE
                WHEN CONTAINS(amenities_without, 45)
                THEN 0
                ELSE NULL
                END
        END                               AS  acesso_sem_degraus,
    CASE
        WHEN CONTAINS(amenities_with, 46)
        THEN 1
        ELSE CASE
                WHEN CONTAINS(amenities_without, 46)
                THEN 0
                ELSE NULL
                END
        END                               AS  cooktop,
    CASE
        WHEN CONTAINS(amenities_with, 47)
        THEN 1
        ELSE CASE
                WHEN CONTAINS(amenities_without, 47)
                THEN 0
                ELSE NULL
                END
        END                               AS  utensilios_de_cozinha,
    CASE
        WHEN CONTAINS(amenities_with, 48)
        THEN 1
        ELSE CASE
                WHEN CONTAINS(amenities_without, 48)
                THEN 0
                ELSE NULL
                END
        END                               AS  cama_de_casal,
    CASE
        WHEN CONTAINS(amenities_with, 49)
        THEN 1
        ELSE CASE
                WHEN CONTAINS(amenities_without, 49)
                THEN 0
                ELSE NULL
                END
        END                               AS  cama_de_solteiro,
    CASE
        WHEN CONTAINS(amenities_with, 50)
        THEN 1
        ELSE CASE
                WHEN CONTAINS(amenities_without, 50)
                THEN 0
                ELSE NULL
                END
        END                               AS  espelho_no_banheiro,
    CASE
        WHEN CONTAINS(amenities_with, 51)
        THEN 1
        ELSE CASE
                WHEN CONTAINS(amenities_without, 51)
                THEN 0
                ELSE NULL
                END
        END                               AS  fechadura_eletronica,
    CASE
        WHEN CONTAINS(amenities_with, 52)
        THEN 1
        ELSE CASE
                WHEN CONTAINS(amenities_without, 52)
                THEN 0
                ELSE NULL
                END
        END                               AS  energia,
    CASE
        WHEN CONTAINS(condo_amenities_with, 1)
        THEN 1
        ELSE CASE
                WHEN CONTAINS(condo_amenities_without, 1)
                THEN 0
                ELSE NULL
                END
        END                               AS  playground,
    CASE
        WHEN CONTAINS(condo_amenities_with, 2)
        THEN 1
        ELSE CASE
                WHEN CONTAINS(condo_amenities_without, 2)
                THEN 0
                ELSE NULL
                END
        END                               AS  piscina_no_condominio,
    CASE
        WHEN CONTAINS(condo_amenities_with, 3)
        THEN 1
        ELSE CASE
                WHEN CONTAINS(condo_amenities_without, 3)
                THEN 0
                ELSE NULL
                END
        END                               AS  churrasqueira_no_condominio,
    CASE
        WHEN CONTAINS(condo_amenities_with, 4)
        THEN 1
        ELSE CASE
                WHEN CONTAINS(condo_amenities_without, 4)
                THEN 0
                ELSE NULL
                END
        END                               AS  quadra_esportiva,
    CASE
        WHEN CONTAINS(condo_amenities_with, 5)
        THEN 1
        ELSE CASE
                WHEN CONTAINS(condo_amenities_without, 5)
                THEN 0
                ELSE NULL
                END
        END                               AS  academia,
    CASE
        WHEN CONTAINS(condo_amenities_with, 6)
        THEN 1
        ELSE CASE
                WHEN CONTAINS(condo_amenities_without, 6)
                THEN 0
                ELSE NULL
                END
        END                               AS  salao_de_festas,
    CASE
        WHEN CONTAINS(condo_amenities_with, 7)
        THEN 1
        ELSE CASE
                WHEN CONTAINS(condo_amenities_without, 7)
                THEN 0
                ELSE NULL
                END
        END                               AS  sauna,
    CASE
        WHEN CONTAINS(condo_amenities_with, 8)
        THEN 1
        ELSE CASE
                WHEN CONTAINS(condo_amenities_without, 8)
                THEN 0
                ELSE NULL
                END
        END                               AS  lavanderia,
    CASE
        WHEN CONTAINS(condo_amenities_with, 9)
        THEN 1
        ELSE CASE
                WHEN CONTAINS(condo_amenities_without, 9)
                THEN 0
                ELSE NULL
                END
        END                               AS  gas_encanado,
    CASE
        WHEN CONTAINS(condo_amenities_with, 10)
        THEN 1
        ELSE CASE
                WHEN CONTAINS(condo_amenities_without, 10)
                THEN 0
                ELSE NULL
                END
        END                               AS  portao_automatico,
    CASE
        WHEN CONTAINS(condo_amenities_with, 11)
        THEN 1
        ELSE CASE
                WHEN CONTAINS(condo_amenities_without, 11)
                THEN 0
                ELSE NULL
                END
        END                               AS  espaco_gourmet,
    CASE
        WHEN CONTAINS(condo_amenities_with, 12)
        THEN 1
        ELSE CASE
                WHEN CONTAINS(condo_amenities_without, 12)
                THEN 0
                ELSE NULL
                END
        END                               AS  perto_do_metro,
    house_condition.maintenancecondition  AS  house_condition
FROM amenities a
FULL JOIN condo_amenities ca
  ON a.id_house = ca.id_house
FULL JOIN datalake_ebdb_raw_prod.housemaintenancecondition house_condition
  ON COALESCE(a.id_house, ca.id_house) = house_condition.houseid