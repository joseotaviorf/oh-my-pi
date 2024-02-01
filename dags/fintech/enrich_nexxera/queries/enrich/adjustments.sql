WITH base AS (
          SELECT DISTINCT
              COALESCE(
                  hd.work_day,
                  CASE
                      WEEKDAY(a0.dt_adjustment_launch)
                      WHEN 6 THEN a0.dt_adjustment_launch + 2
                      WHEN 7 THEN a0.dt_adjustment_launch + 1
                      ELSE a0.dt_adjustment_launch
                  END) AS dt_adjustment_launch,
              a0.dt_sale_adjustment,
              CASE
                  CAST(a0.id_flag AS INT)
                  WHEN 1 THEN 'Visa'
                  WHEN 2 THEN 'Mastercard'
                  WHEN 3 THEN 'Hipercard'
                  WHEN 4 THEN 'Banricompras'
                  WHEN 5 THEN 'Amex'
                  WHEN 6 THEN 'Cabal'
                  WHEN 7 THEN 'Elo'
                  WHEN 8 THEN 'Sorocred'
                  WHEN 9 THEN 'Diners'
                  WHEN 10 THEN 'DiscOVER'
                  WHEN 11 THEN 'Aura'
                  WHEN 12 THEN 'Sicredi'
                  WHEN 13 THEN 'Mais'
                  WHEN 14 THEN 'CUP'
                  WHEN 15 THEN 'Ticket'
                  WHEN 16 THEN 'Sodexo'
                  WHEN 17 THEN 'Planvale'
                  WHEN 18 THEN 'Goodcard'
                  WHEN 19 THEN 'Greencard'
                  WHEN 20 THEN 'Agiplan'
                  WHEN 21 THEN 'Banescard'
                  WHEN 22 THEN 'Credsystem'
                  WHEN 23 THEN 'Esplanada'
                  WHEN 24 THEN 'CredZ'
                  WHEN 25 THEN 'Alelo'
                  WHEN 26 THEN 'Alelo'
                  WHEN 27 THEN 'Elo'
                  WHEN 28 THEN 'Elo'
                  WHEN 29 THEN 'Ticket'
                  WHEN 30 THEN 'Ticket'
                  WHEN 31 THEN 'Sodexo'
                  WHEN 32 THEN 'Sodexo'
                  WHEN 33 THEN 'Sodexo'
                  WHEN 34 THEN 'DMCard'
                  WHEN 35 THEN 'Verocheque'
                  WHEN 36 THEN 'VR'
                  WHEN 37 THEN 'Policard'
                  WHEN 38 THEN 'Valecard'
                  WHEN 39 THEN 'BIN'
                  WHEN 40 THEN 'Personalcard'
                  WHEN 41 THEN 'Flex'
                  WHEN 42 THEN 'Libercard'
                  WHEN 43 THEN 'Fancard'
                  WHEN 44 THEN 'Vegascard'
                  WHEN 45 THEN 'Convcard'
                  WHEN 46 THEN 'Tendência'
                  WHEN 47 THEN 'Alelo'
                  WHEN 48 THEN 'Avista'
                  WHEN 49 THEN 'Calcard'
                  WHEN 50 THEN 'Bahamascard'
                  WHEN 51 THEN 'Sodexo'
                  WHEN 52 THEN 'JCB'
                  WHEN 53 THEN 'Verdecard'
                  WHEN 54 THEN 'Hiper'
                  WHEN 55 THEN 'Tricard'
                  WHEN 56 THEN 'Hiper/Hipercard'
                  WHEN 57 THEN 'Valemais'
                  WHEN 59 THEN 'Refeisul'
                  WHEN 60 THEN 'Senff'
                  WHEN 61 THEN 'Abrapetite'
                  WHEN 62 THEN 'Valeshop'
                  WHEN 63 THEN 'Bradescard'
                  WHEN 64 THEN 'Brasilcard'
                  WHEN 65 THEN 'Coopercred'
                  WHEN 66 THEN 'Maxxcard'
                  WHEN 67 THEN 'BIQ'
                  WHEN 68 THEN 'Siscred'
                  WHEN 69 THEN 'Convenios'
                  WHEN 70 THEN 'Use'
                  WHEN 71 THEN 'Orgcard'
                  WHEN 72 THEN 'Sincard'
                  WHEN 73 THEN 'ECXCard'
                  WHEN 74 THEN 'Banestes'
                  WHEN 75 THEN 'DaCasa'
                  WHEN 76 THEN 'Comprocard'
                  WHEN 77 THEN 'Nutricash'
                  WHEN 78 THEN 'Club+'
                  WHEN 79 THEN 'Algorix'
                  WHEN 80 THEN 'Bigcard'
                  WHEN 81 THEN 'Credicesta'
                  WHEN 82 THEN 'Fortbrasil'
                  WHEN 83 THEN 'Convênios'
                  WHEN 84 THEN 'Ourocard'
                  WHEN 85 THEN 'Infocards'
                  WHEN 86 THEN 'Banricard'
                  WHEN 87 THEN 'Mvcard'
                  WHEN 88 THEN 'Banese'
                  WHEN 89 THEN 'Usecred'
                  WHEN 90 THEN 'Brasil'
                  WHEN 91 THEN 'Familly'
                  WHEN 92 THEN 'Banestik'
                  WHEN 93 THEN 'Credishop'
                  WHEN 94 THEN 'Romcard'
                  WHEN 95 THEN 'Sindplus'
                  WHEN 96 THEN 'Eucard'
                  WHEN 97 THEN 'Addmeal'
                  WHEN 98 THEN '008'
                  WHEN 99 THEN 'Visa'
                  WHEN 100 THEN 'Vidalink'
                  WHEN 101 THEN 'Unocard'
                  WHEN 0 THEN NULL
                  WHEN 999 THEN NULL
                  ELSE NULL
              END AS flag,
              CASE
                  CAST(a0.id_flag AS INT)
                  WHEN 1 THEN 'VISA'
                  WHEN 2 THEN 'MAST'
                  WHEN 3 THEN 'HIPE'
                  WHEN 4 THEN 'BANR'
                  WHEN 5 THEN 'AMEX'
                  WHEN 6 THEN 'CABA'
                  WHEN 7 THEN 'ELO'
                  WHEN 8 THEN 'SORO'
                  WHEN 9 THEN 'DINE'
                  WHEN 10 THEN 'DISC'
                  WHEN 11 THEN 'AURA'
                  WHEN 12 THEN 'SICR'
                  WHEN 13 THEN 'MAIS'
                  WHEN 14 THEN 'CUP'
                  WHEN 15 THEN 'TICK'
                  WHEN 16 THEN 'SODE'
                  WHEN 17 THEN 'PLAN'
                  WHEN 18 THEN 'GOOD'
                  WHEN 19 THEN 'GREE'
                  WHEN 20 THEN 'AGIP'
                  WHEN 21 THEN 'BANE'
                  WHEN 22 THEN 'CRED'
                  WHEN 23 THEN 'ESPL'
                  WHEN 24 THEN 'CRED'
                  WHEN 25 THEN 'ALEL'
                  WHEN 26 THEN 'ALEL'
                  WHEN 27 THEN 'ELO'
                  WHEN 28 THEN 'ELO'
                  WHEN 29 THEN 'TICK'
                  WHEN 30 THEN 'TICK'
                  WHEN 31 THEN 'SODE'
                  WHEN 32 THEN 'SODE'
                  WHEN 33 THEN 'SODE'
                  WHEN 34 THEN 'DMCA'
                  WHEN 35 THEN 'VERO'
                  WHEN 36 THEN 'VR'
                  WHEN 37 THEN 'POLI'
                  WHEN 38 THEN 'VALE'
                  WHEN 39 THEN 'BIN'
                  WHEN 40 THEN 'PERS'
                  WHEN 41 THEN 'FLEX'
                  WHEN 42 THEN 'LIBE'
                  WHEN 43 THEN 'FANC'
                  WHEN 44 THEN 'VEGA'
                  WHEN 45 THEN 'CONV'
                  WHEN 46 THEN 'TEND'
                  WHEN 47 THEN 'ALEL'
                  WHEN 48 THEN 'AVIS'
                  WHEN 49 THEN 'CALC'
                  WHEN 50 THEN 'BAHA'
                  WHEN 51 THEN 'SODE'
                  WHEN 52 THEN 'JCB'
                  WHEN 53 THEN 'VERD'
                  WHEN 54 THEN 'HIPE'
                  WHEN 55 THEN 'TRIC'
                  WHEN 56 THEN 'HIPE'
                  WHEN 57 THEN 'VALE'
                  WHEN 59 THEN 'REFE'
                  WHEN 60 THEN 'SENF'
                  WHEN 61 THEN 'ABRA'
                  WHEN 62 THEN 'VALE'
                  WHEN 63 THEN 'BRAD'
                  WHEN 64 THEN 'BRAS'
                  WHEN 65 THEN 'COOP'
                  WHEN 66 THEN 'MAXX'
                  WHEN 67 THEN 'BIQ'
                  WHEN 68 THEN 'SISC'
                  WHEN 69 THEN 'CONV'
                  WHEN 70 THEN 'USE'
                  WHEN 71 THEN 'ORGC'
                  WHEN 72 THEN 'SINC'
                  WHEN 73 THEN 'ECXC'
                  WHEN 74 THEN 'BANE'
                  WHEN 75 THEN 'DACA'
                  WHEN 76 THEN 'COMP'
                  WHEN 77 THEN 'NUTR'
                  WHEN 78 THEN 'CLUB'
                  WHEN 79 THEN 'ALGO'
                  WHEN 80 THEN 'BIGC'
                  WHEN 81 THEN 'CRED'
                  WHEN 82 THEN 'FORT'
                  WHEN 83 THEN 'CONV'
                  WHEN 84 THEN 'OURO'
                  WHEN 85 THEN 'INFO'
                  WHEN 86 THEN 'BANR'
                  WHEN 87 THEN 'MVCA'
                  WHEN 88 THEN 'BANE'
                  WHEN 89 THEN 'USEC'
                  WHEN 90 THEN 'BRAS'
                  WHEN 91 THEN 'FAMI'
                  WHEN 92 THEN 'BANE'
                  WHEN 93 THEN 'CRED'
                  WHEN 94 THEN 'ROMC'
                  WHEN 95 THEN 'SIND'
                  WHEN 96 THEN 'EUCA'
                  WHEN 97 THEN 'ADDM'
                  WHEN 98 THEN '008'
                  WHEN 99 THEN 'VISA'
                  WHEN 100 THEN 'VIDA'
                  WHEN 101 THEN 'UNOC'
                  WHEN 0 THEN NULL
                  WHEN 999 THEN NULL
                  ELSE NULL
              END AS id_flag,
              CAST(a0.installment_number AS INT) AS installment_number,
              CAST(a0.total_installments AS INT) AS total_installments,
              CAST(a0.id_bank_grouper AS INT) AS id_bank_grouper,
              CASE
                  CAST(a0.current_summary_number AS INT)
                  WHEN 0 THEN -1
                  ELSE CAST(a0.current_summary_number AS INT)
              END AS current_summary_number,
              a0.id_authorization,
              CASE
                  CAST(a0.nsu_cv AS INT)
                  WHEN 0 THEN -1
                  ELSE CAST(a0.nsu_cv AS INT)
              END AS nsu_cv,
              a0.adjustment_original_reason,
              CAST(a0.original_pos AS INT) AS original_pos,
              a0.launch_type,
              a0.adjustment_value,
              a0.ts_ingested,
              a0.year,
              a0.month,
              a0.day
          FROM
              datalake_nexxera_clean.adjustments a0
            LEFT JOIN
                datalake_gsheets_clean.nexxera_holly_days hd
                ON hd.holly_day = a0.dt_adjustment_launch
)

   SELECT
      id_flag,
      id_bank_grouper,
      id_authorization,
      ROW_NUMBER() OVER(
          ORDER BY
              dt_adjustment_launch,
              id_flag,
              original_pos,
              adjustment_original_reason,
              installment_number,
              total_installments,
              id_bank_grouper,
              current_summary_number,
              nsu_cv,
              id_authorization
      ) AS rn_adjustments,
      original_pos AS id_ec,
      flag,
      adjustment_original_reason,
      installment_number,
      total_installments,
      current_summary_number,
      nsu_cv,
      SUM(IF(launch_type = 'D', adjustment_value, 0.00)) AS adjustment_value,
      SUM(IF(launch_type = 'D', adjustment_value, 0.00)) - SUM(IF(launch_type = 'C', adjustment_value, 0.00)) AS net_adjustment_value,
      SUM(IF(launch_type = 'C', adjustment_value, 0.00)) AS adjustment_value_tax,
      COUNT(*) AS counter_adjustments,
      dt_adjustment_launch,
      dt_sale_adjustment,
      ts_ingested,
      year,
      month,
      day
  FROM
      base
  GROUP BY dt_adjustment_launch,
      dt_sale_adjustment,
      original_pos,
      adjustment_original_reason,
      installment_number,
      total_installments,
      id_bank_grouper,
      current_summary_number,
      nsu_cv,
      id_authorization,
      flag,
      id_flag,
      ts_ingested,
      year,
      month,
      day
