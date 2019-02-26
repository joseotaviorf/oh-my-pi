DROP VIEW if exists public.vw_dim_user_doorman;

CREATE VIEW public.vw_dim_user_doorman as
    select
        id as sk_user_doorman,
        id as id_user_doorman,
        workAddress	as work_address,
        workHouseNumber as work_house_number,
        workNeighbourhood as work_neighbourhood,
        workCity as work_city,
        code as code,
        atualizadoEm as ts_updated,
        criadoEm as ts_created,
        joinedProgramAt as ts_joined_program,
        coalesce(id_dados_afiliado, -1) as sk_user_affiliate,
        is_active,
        now() as ts_load
    from
        user_doorman
;

  