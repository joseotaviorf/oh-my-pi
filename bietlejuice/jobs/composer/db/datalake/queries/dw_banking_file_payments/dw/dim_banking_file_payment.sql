with
    boleto as (
        select
            b.id,
            b.company_use,
            b.status,
            bk.name,
            'charge' as type,
            b.related_document_type,
            b.id_related_document,
            b.related_document_status,
            b.occurrence_code,
            b.payer_document,
            null as payee_document,
            null as payee_name,
            null as has_payee_savings_acc,
            b.ts_created,
            b.ts_issued,
            b.ts_updated,
            b.dt_due,
            b.dt_fine_due,
            b.dt_paid,
            b.due_amount,
            b.paid_amount,
            b.fine_amount,
            b.one_day_interest,
            b.interest
        from datalake_vans_clean.boleto b
        left join datalake_vans_clean.bank_boleto bb 
            on b.id_bank_boleto = bb.id
        left join datalake_vans_clean.bank bk
            on bb.id_bank = bk.id
    ),
    payment as (
        select
            p.id,
            p.company_use,
            p.status,
            ba.name,
            'transfer' as type,
            p.related_document_type,
            p.id_related_document,
            p.related_document_status,
            p.occurrence_code,
            null as payer_document,
            p.payee_document,
            null as payee_name,
            p.has_payee_savings_acc,
            p.ts_created,
            p.ts_issued,
            p.ts_updated,
            p.dt_dued as dt_due,
            null as dt_fine_due,
            p.dt_paid,
            p.due_amount,
            p.paid_amount,
            null as fine_amount,
            null as one_day_interest,
            null as interest
        from datalake_vans_clean.payment p
        left join datalake_vans_clean.bank_payment bp
            on p.id_bank_payment = bp.id
        left join datalake_vans_clean.bank ba
            on bp.id_bank = ba.id
    ),
    payment_boleto as (
        select
            pb.id,
            pb.company_use,
            pb.status,
            bk.name,
            'account payable' as type,
            pb.related_document_type,
            pb.id_related_document,
            pb.related_document_status,
            pb.occurrence_code,
            null as payer_document,
            null as payee_document,
            pb.payee_name,
            null as has_payee_savings_acc,
            pb.ts_created,
            null as ts_issued,
            pb.ts_updated,
            null as dt_due,
            null as dt_fine_due,
            pb.dt_paid,
            null as due_amount,
            pb.paid_amount,
            null as fine_amount,
            null as one_day_interest,
            null as interest
        from datalake_vans_clean.payment_boleto pb
        left join datalake_vans_clean.bank bk
            on pb.bank_payment_code = bk.code
    ),
    consolidation_table as (
        select * from boleto
        union all
        select * from payment
        union all
        select * from payment_boleto
    ),
    delete_documents_repeated as (
        select
            max(cons.id) as max_id,
            nullif(regexp_extract(cons.company_use, '(\\d+\\D\\d{{4}})\d*', 1), '') as id_company_use,
            company_use,
            cons.ts_created,
            cons.ts_issued,
            cons.dt_paid
        from consolidation_table cons
        group by 2,3,4,5,6
    ),
    vans_payments as (
        select 
            cons.*,
            nullif(cons.company_use, '') as company_use_code,
            del.id_company_use
        from consolidation_table cons
        join delete_documents_repeated del
            on cons.id=del.max_id
            -- <=> return TRUE when both key values are null 
            and del.company_use<=>cons.company_use
            and del.ts_created<=>cons.ts_created
            and del.ts_issued<=>cons.ts_issued
            and del.dt_paid<=>cons.dt_paid
    ),
    -- enriched dim_banking table --> mapping values and extract values
    enriched_vans_payments as (
        select 
            *,
            string(id) as primary_key,
            nullif(regexp_extract(id_company_use, '([BRKEPT])', 1), '') as frequency,
            case
                when type = 'account payable' then 'not applicable'
                when related_document_type = 'invoice' then
                   nullif(regexp_extract(related_document_status, '/?(.+)', 1), '')
                else 'not applicable'
            end as invoice_status,
            nullif(regexp_extract(status, '/(\\w+)', 1), '') as status_type,
            case 
                when related_document_type = 'payment-request' and type = 'transfer' then 
                    nullif(regexp_extract(related_document_status, '/?(.+)', 1), '')
                else 'not applicable'
			end as payment_request_status,
            case 
                when id_company_use is null and company_use is not null then 
                    nullif(regexp_extract(company_use, '^\\d+(\\D+)', 1), '') 
                else null
            end as rental_user,
            nullif(regexp_extract(id_company_use, '\\d+\\D(\\d{{4}})', 1), '') as accrual_year_month
        from vans_payments
    ),
    map_column_values as (
        select
            primary_key,
            type as tp,
            id_company_use,
            case 
                when frequency = 'B' then 'monthly'
                when frequency = 'R' then 'early termination'
                when frequency = 'K' then 'onboarding'
                when frequency = 'E' then 'manual'
                when frequency = 'T' then 'condominium'
                when frequency = 'P' then 'landlord'
            end as payment_type,
            case 
                when rental_user = 'INQ' then 'tenant'
                when rental_user = 'PP' then 'landlord'
                when rental_user in ('CR','Corretor') then 'estate agent'
                when rental_user in ('CondoDep','Dep - Cond') then 'condominium'
                else 'unknown' 
            end as user_type 
        from enriched_vans_payments
        where id_company_use is not null
    ),
    -- sometimes there may be 13 months by mistake
    fix_year_month as (
        select
            *,
            -- for ex: 1914 --> (1900+100)+(14-2)-10 = 2000+12-10 = 2002
            case 
                when month > 12 then (year*100+100)+(month-2)-10
                else cast(accrual_year_month as int)
            end as fixed_accrual_year_month
        from (
            select
                primary_key, 
                id_company_use,
                type as tp,
                accrual_year_month,
                cast(regexp_extract(accrual_year_month, '(\\d{{2}})(\\d{{2}})', 1) as int) as year,
                cast(regexp_extract(accrual_year_month, '(\\d{{2}})(\\d{{2}})', 2) as int) as month
            from enriched_vans_payments
        )
        where accrual_year_month is not null
    ), 
    -- fact model - it's generating sk_banking_file_payment, the pk of the fact table
    index_version as (
        select
            primary_key,
            id_company_use,
            company_use_code,
            type as tp,
            case 
                when id_company_use is not null then 'DEFAULT'
                when company_use_code is null then 'INVALID'
                when (id_company_use is null and company_use_code is not null) then 'CUSTOM' 
            end as format,
            string(row_number() over (partition by id_company_use order by ts_issued, ts_created, dt_paid)) as version_index
        from enriched_vans_payments
    ),
    generate_key as (
    select
        *,
        case 
            when format = 'DEFAULT' then lpad(version_index, 3, '0')
            else null
        end as version,
        case
            when format = 'DEFAULT' and tp = 'charge' then concat(id_company_use, '1', lpad(version_index, 3, '0'))
            when format = 'DEFAULT' and tp = 'transfer' then concat(id_company_use, '2', lpad(version_index, 3, '0'))
            when format = 'DEFAULT' and tp = 'account payable' then concat(id_company_use, '3', lpad(version_index, 3, '0'))
            when format = 'INVALID' then concat(format, primary_key)
            when format = 'CUSTOM' then concat(company_use_code, primary_key)
        end as sk_banking_file_payment
    from index_version
    )
    select
        key.sk_banking_file_payment,
        key.format,
        vans.type,
        key.version,
        coalesce(vans.name, 'unknown') as bank_name,
        mapping.user_type,
        mapping.payment_type,
        vans.related_document_type,
        vans.invoice_status,
        vans.payment_request_status,
        vans.status_type as status,
        fix.fixed_accrual_year_month as accrual_year_month,
        vans.ts_created,
        vans.ts_issued,
        vans.ts_updated,
        vans.dt_due,
        vans.dt_fine_due,
        vans.dt_paid,
        now() as ts_load
    from generate_key key
    join enriched_vans_payments vans
        on key.primary_key=vans.primary_key
        and key.tp=vans.type
        and key.id_company_use<=>vans.id_company_use
    left join map_column_values mapping
        on key.primary_key=mapping.primary_key
        and key.tp=mapping.tp
        and key.id_company_use=mapping.id_company_use
    left join fix_year_month fix
        on key.primary_key=fix.primary_key
        and key.tp=fix.tp
        and key.id_company_use=fix.id_company_use