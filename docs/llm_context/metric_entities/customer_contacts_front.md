# Customer Contacts Front

## Ownership

**Data Owner:**

- [joao.mariani@quintoandar.com.br](mailto:joao.mariani@quintoandar.com.br)

**Data Steward:**

- [victor.prado@quintoandar.com.br](mailto:victor.prado@quintoandar.com.br)
- [alef.vieira@quintoandar.com.br](mailto:alef.vieira@quintoandar.com.br)
- [diego.carvalho@quintoandar.com.br](mailto:diego.carvalho@quintoandar.com.br)
- [romario.nascimento@quintoandar.com.br](mailto:romario.nascimento@quintoandar.com.br)

## Overview

**Customer Contacts Front** is a family of Front Office service-quality metrics built on `dw_bpo_performance.customer_contacts_session`, which aggregates the different interactions of a single support journey around `sk_support_session_fallback_ticket`. The dataset's scope covers **chat and call only**.

Front and Back departments **coexist in the same table** — `front_or_back` varies row by row. Despite that, every metric in this family is Front Office only.

The metrics are: post-service satisfaction (**DSat Front**), perceived resolution effectiveness (**Resolution Rate**), and contact recurrence for the same theme within 0- and 4-day windows (**Recontato D0**, **Recontato D4**).

**"Front" in the name "DSat Front" is a reporting/naming convention, not a channel or layer filter** — none of the four documented formulas restrict by `channel` or `front_or_back`. If an indicator needs to be restricted to a specific channel or layer, the filter must be added by the user.

## Related Business Entities

- Contact
- Ticket
- Satisfaction
- Department

## Catalog

| Metric | Type |
| :---- | :---- |
| DSat Front | OKR |
| Resolution Rate | Health Metric |
| Recontato D4 | Health Metric |
| Recontato D0 | Health Metric |

## MBR

**Name** Post Contract
**Category** CS Quality

## Glossary and Synonyms

- **DSat**, **DSat Front**, **Dissatisfaction Rate**, **taxa de insatisfação** → % DSat Front
- **Resolution Rate**, **taxa de resolução**, **% resolvido** → Resolution Rate
- **Recontato**, **Recontato D4**, **reabertura em 4 dias** → % Recontato D4
- **Recontato D0**, **reabertura no mesmo dia** → % Recontato D0

## Scope

**Included**: support sessions registered in `dw_bpo_performance.customer_contacts_session`, restricted to the **chat and call** channels. Within that universe: satisfaction-survey response (DSat and Resolution Rate) or service completed within the same department/taxonomy (Recontato). For every metric, filter `front_or_back IN ('front')` and `pre_and_post_contract IN ('post-rental')` — see `pre_and_post_contract` in "Nuances" below (it is a derived expression, not a stored column).

**Excluded**: for Recontato D4/D0, only `agent_organization IN ('atento', 'aec')` counts in the numerator and denominator — the other operators (`webhelp`, `quintoandar`, `action line`, `actionline`, `ext`) are out of scope, since only the Atento and AeC BPOs perform Front service.

### Temporal reference axis

Confirmed by the team: each metric uses a distinct axis — there is no single cutoff field for the whole table.

| Metric | Axis | Rationale |
| :---- | :---- | :---- |
| DSat Front | `CAST(ts_submitted AS DATE)` | Date the satisfaction survey was answered |
| Resolution Rate | `CAST(ts_submitted AS DATE)` | Same — comes from the same survey |
| Recontato D4 / D0 | `CAST(dt_created AS DATE)` | Creation date of the original session/ticket that generated (or not) a recontact |

**Warning**: `year`, `month`, `day` are **not** the reference axis — a sample confirms they are **load-partition columns** (100% of the 1000 sampled rows carry `year=2026, month=7, day=7`, matching the `ts_load` date, not the business-event date). Using them for the indicator's temporal cut would produce a systematically wrong result — the entire history stamped with the most recent load month.

## Calculation

This family covers four independently-computed ratios, all keyed on `sk_support_session_fallback_ticket`:

```
DSat Front = COUNT(DISTINCT sk_support_session_fallback_ticket WHERE satisfaction_score IN (1,2))
             / COUNT(DISTINCT sk_support_session_fallback_ticket WHERE satisfaction_score IS NOT NULL)

Resolution Rate = COUNT(DISTINCT sk_support_session_fallback_ticket WHERE resolution_survey = true)
                  / COUNT(DISTINCT sk_support_session_fallback_ticket WHERE resolution_survey IS NOT NULL)

Recontato D4 = COUNT(DISTINCT sk_support_session_fallback_ticket WHERE theme_recontact_flag = 1 AND agent_organization IN ('atento','aec'))
               / COUNT(DISTINCT sk_support_session_fallback_ticket WHERE theme_recontact_flag IS NOT NULL AND agent_organization IN ('atento','aec'))

Recontato D0 = COUNT(DISTINCT sk_support_session_fallback_ticket WHERE theme_recontact_flag_d0 = 1 AND agent_organization IN ('atento','aec'))
               / COUNT(DISTINCT sk_support_session_fallback_ticket WHERE theme_recontact_flag_d0 IS NOT NULL AND agent_organization IN ('atento','aec'))
```

where `satisfaction_score`, `resolution_survey`, `theme_recontact_flag`, and `theme_recontact_flag_d0` are the per-metric outcome flags, and `sk_support_session_fallback_ticket` is the session/ticket key deduplicated in every numerator and denominator.

### Canonical Filter

Apply on `dw_bpo_performance.customer_contacts_session`:

```sql
front_or_back = 'front'
AND pre_and_post_contract = 'post-rental'  -- derived expression, not a stored column — see Nuances
-- Recontato D4/D0 only:
AND agent_organization IN ('atento', 'aec')
```

**Warning**: dropping `front_or_back = 'front'` lets Back Office rows into the base — Front and Back departments coexist in the same table and `front_or_back` varies row by row. For Recontato D4/D0 specifically, dropping the `agent_organization IN ('atento', 'aec')` restriction pulls in `webhelp`, `quintoandar`, `action line`, `actionline`, and `ext` volumes, which do not perform Front service and would dilute the recontact rate. This restriction is **specific to Recontato** — do not apply it to DSat Front or Resolution Rate unless explicitly requested.

### Nuances

There is no GSheets weight or parameter table for this family — every ratio reads directly from `customer_contacts_session`. Three concepts used for scoping (`pre_and_post_contract`, plus the reporting sub- and macro-categorizations `last_team` and `last_team_adjusted`) are **not stored columns** — they are `CASE` expressions derived from `last_department` / `last_team` that the analyst must compute inline (or copy from below):

**`pre_and_post_contract`** — splits departments into Pre-Contract and Post-Contract journeys. This family always filters to `post-rental`:

```sql
CASE
    WHEN last_department IN (
        'CX Partners Tarefas [PRE] [BACK]', 'CX Propostas Tarefas [PRE] [BACK]',
        'OPS - FUP Documentação Rental OA2DS [CLO] [PRE]', 'FUP Carteirização B2C [CLO] [PRE] [BACK]',
        'EARLY DEMAND [CLOSING] [BACK]', 'Closing PP Multi [CLO] [PRE] [BACK]',
        'CX Parceiros Compra e Venda [FRONT]', 'CX Parceiros [FRONT] [PRE]',
        'CX Parceiros da Portaria [FRONT] [PRE]', 'CX Propostas [FRONT] [PRE]',
        'CX Visitas [FRONT] [PRE]', 'Consultores imobiliários 5A',
        '[WH] Credito [FRONT]', '[WH] Closing [FRONT]'
    ) THEN 'pre_rental'
    WHEN last_department IN (
        'CX Mudança [FRONT] [POS]', 'CX Pagamentos [FRONT] [POS]', 'CX Reparos [FRONT] [POS]',
        'CX Rescisão [FRONT] [POS]', 'Aditivos [REP] [POS] [BACK]', 'Entrada no imóvel [ONB] [POS] [BACK]',
        'CX Pagamentos Ativo [POS] [BACK] [PAY]', 'Alteração de dados bancários [BACK]',
        '[WH] Alteração de dados bancários [Front]', 'Atendimento Escalado [OFF] [POS] [BACK]',
        'Onboarding Back', 'Ongoing Back', '[AeC] CX Ongoing [FRONT] [POS]', 'CX Ongoing [FRONT] [POS]'
    ) THEN 'post-rental'
    WHEN last_team IN (
        'Onboarding ForRent', 'Ongoing FR - Geral', 'Ongoing FR - Informe de Rendimentos',
        'Payment FR - Aluguel', 'Payment FR - Dados Bancários', 'Payment FR - Condomínio Geral',
        'Payment FR - Reembolso de Condomínio', 'Payment FR - Condomínio Interno',
        'Payment_FR_GeneralCondominium', 'Payment FR - PP Multi', 'Payment FR - Dados Bancários Front',
        'Onboarding Back', 'Payments', 'Ongoing Back', 'Payments Ativo Back', 'Offboarding Front',
        'Offboarding Reparos Back', 'Offboarding - AEC', 'Offboarding - CNX', 'Offboarding Back', 'Payments - DB'
    ) THEN 'post-rental'
    WHEN last_department IN (
        'Notificação Extrajudicial [CE] [POS] [BACK]', 'CX Conta Comigo [POS] [BACK]',
        'Dados Bancários [CE] [POS] [BACK]', 'Casos Especiais [CE] [POS] [BACK]', 'Midias Ops [POS] [BACK]'
    ) THEN 'CSI'
    -- WHEN last_department IN ('Onboarding') AND front_or_back = 'Back' THEN 'post-rental' -- inactive/commented in source
    ELSE 'others'
END
```

**`last_team`** — reporting sub-categorization of `last_department` / `last_team` (not used directly by the four formulas, but part of the family's standard reporting cuts):

```sql
CASE
    WHEN last_department = 'Reembolso de Reparos [Back]' THEN 'Reembolso Reparos Back'
    WHEN last_department = 'Rescisão por Inadimplência [OFF][POS][BACK]' THEN 'Offboarding Rescisão Back'
    WHEN last_department = 'CX Offboarding Reparos Receptivo [OFF] [POS] [BACK]' THEN 'Offboarding Reparos Back'
    WHEN last_team IN ('Onboarding ForRent') THEN 'Onboarding Back'
    WHEN last_team IN ('Ongoing FR - Geral', 'Ongoing FR - Informe de Rendimentos') THEN 'Ongoing Back'
    WHEN last_team IN (
        'Payment FR - Aluguel', 'Payment FR - Condomínio Geral', 'Payment FR - Reembolso de Condomínio',
        'Payment_FR_GeneralCondominium', 'Payment FR - PP Multi'
    ) THEN 'Payments Ativo Back'
    ELSE last_team
END
```

**`last_team_adjusted`** — macro-categorization of `last_team` (reporting only):

```sql
CASE
    WHEN last_team IN ('Repairs/Ongoing Front', 'Repairs/Ongoing Back') THEN 'Repairs/Ongoing'
    WHEN last_team IN ('Rental Manager', 'Rental Manager Gold', 'Rental Manager CTL') THEN 'Rental Manager'
    WHEN last_team IN (
        'Payments', 'Payments Ativo Back', 'Payment FR - Aluguel', 'Payment FR - Dados Bancários',
        'Payment FR - Condomínio Geral', 'Payment FR - Reembolso de Condomínio',
        'Payment_FR_GeneralCondominium', 'Payment FR - PP Multi',
        'Payment FR - Dados Bancários Front', 'Payments - DB'
    ) THEN 'Payments'
    WHEN last_team IN ('CX Partners', 'CX Compra e Venda', 'CX Partners For Sale') THEN 'Partners'
    WHEN last_team IN ('Ongoing Back', 'Ong Back', 'Ongoing FR - Geral', 'Ongoing FR - Informe de Rendimentos') THEN 'Ongoing'
    WHEN last_team IN ('Onboarding Back', 'Moving', 'Onboarding ForRent') THEN 'Onboarding'
    WHEN last_team IN ('Offboarding Front', 'Offboarding Back', 'Offboarding - AEC', 'Offboarding - CNX') THEN 'Offboarding'
    WHEN last_team IN (
        'ReclameAqui', 'Privacy', 'Casos Especiais', 'PROCON', 'Dados Bancários', 'Conta Comigo',
        'Subsídios', 'Consumidor.Gov', 'Notificação Extrajudicial', 'Midias Ops',
        'ReclameAqui - Grupo5A', 'Reversão de NPS'
    ) THEN 'CSI'
    ELSE last_team
END
```

**Join key**: none — the family is computed from a single table, `dw_bpo_performance.customer_contacts_session`, at the `sk_support_session_fallback_ticket` grain.

**Fallback**: not applicable — there is no external parameter table to fall back to.

## Dos and Don'ts

**Do:**

- Use `COUNT(DISTINCT sk_support_session_fallback_ticket)` (never `COUNT(*)`) in every numerator/denominator.
- Restrict Recontato D4/D0 to `agent_organization IN ('atento', 'aec')` in both numerator and denominator.
- Restrict every metric to `front_or_back = 'front'`.
- Treat `year`/`month`/`day` as **load-partition** columns, not event dates — never use them for the indicator's temporal cut.

**Don't:**

- Don't group by `year`, `month`, `day` as if they were the contact date — in the sample, these three columns are constant (load date), not the business-event date.
- Don't treat the Recontato `agent_organization` filter as universal — it is specific to these two metrics; do not apply it to DSat Front or Resolution Rate unless explicitly requested.
- Don't filter the `post-rental` scope with only `last_team IN (...)` — the `pre_and_post_contract` `CASE` (Nuances) classifies `post-rental` via **two independent branches**: a `last_department IN (...)` branch (e.g. `'CX Reparos [FRONT] [POS]'`) and a separate `last_team IN (...)` branch. Filtering on just one silently drops eligible sessions and skews DSat Front, Resolution Rate, and Recontato D0/D4 low versus the stated canonical scope — always replicate the full `CASE` (see Golden Queries).

## Golden Queries

Temporal axis confirmed by the team: `ts_submitted` for DSat/Resolution, `dt_created` for Recontato D4/D0 (see "Temporal reference axis" above). `pre_and_post_contract` is not a stored column, so both queries materialize it in a `scoped` CTE using the **full** `CASE` documented under "Nuances" — not just its `last_team` branch. The `CASE` classifies `post-rental` via **two independent branches**: a `last_department IN (...)` branch (e.g. `'CX Reparos [FRONT] [POS]'`) and a separate `last_team IN (...)` branch; filtering on only one of the two silently drops eligible sessions and skews every metric in this family low. Trino dialect.

### Query 1 — DSat Front and Resolution Rate (monthly)

```sql
WITH scoped AS (
    SELECT
        ccs.*,
        CASE
            WHEN ccs.last_department IN (
                'CX Partners Tarefas [PRE] [BACK]', 'CX Propostas Tarefas [PRE] [BACK]',
                'OPS - FUP Documentação Rental OA2DS [CLO] [PRE]', 'FUP Carteirização B2C [CLO] [PRE] [BACK]',
                'EARLY DEMAND [CLOSING] [BACK]', 'Closing PP Multi [CLO] [PRE] [BACK]',
                'CX Parceiros Compra e Venda [FRONT]', 'CX Parceiros [FRONT] [PRE]',
                'CX Parceiros da Portaria [FRONT] [PRE]', 'CX Propostas [FRONT] [PRE]',
                'CX Visitas [FRONT] [PRE]', 'Consultores imobiliários 5A',
                '[WH] Credito [FRONT]', '[WH] Closing [FRONT]'
            ) THEN 'pre_rental'
            WHEN ccs.last_department IN (
                'CX Mudança [FRONT] [POS]', 'CX Pagamentos [FRONT] [POS]', 'CX Reparos [FRONT] [POS]',
                'CX Rescisão [FRONT] [POS]', 'Aditivos [REP] [POS] [BACK]', 'Entrada no imóvel [ONB] [POS] [BACK]',
                'CX Pagamentos Ativo [POS] [BACK] [PAY]', 'Alteração de dados bancários [BACK]',
                '[WH] Alteração de dados bancários [Front]', 'Atendimento Escalado [OFF] [POS] [BACK]',
                'Onboarding Back', 'Ongoing Back', '[AeC] CX Ongoing [FRONT] [POS]', 'CX Ongoing [FRONT] [POS]'
            ) THEN 'post-rental'
            WHEN ccs.last_team IN (
                'Onboarding ForRent', 'Ongoing FR - Geral', 'Ongoing FR - Informe de Rendimentos',
                'Payment FR - Aluguel', 'Payment FR - Dados Bancários', 'Payment FR - Condomínio Geral',
                'Payment FR - Reembolso de Condomínio', 'Payment FR - Condomínio Interno',
                'Payment_FR_GeneralCondominium', 'Payment FR - PP Multi', 'Payment FR - Dados Bancários Front',
                'Onboarding Back', 'Payments', 'Ongoing Back', 'Payments Ativo Back', 'Offboarding Front',
                'Offboarding Reparos Back', 'Offboarding - AEC', 'Offboarding - CNX', 'Offboarding Back', 'Payments - DB'
            ) THEN 'post-rental'
            WHEN ccs.last_department IN (
                'Notificação Extrajudicial [CE] [POS] [BACK]', 'CX Conta Comigo [POS] [BACK]',
                'Dados Bancários [CE] [POS] [BACK]', 'Casos Especiais [CE] [POS] [BACK]', 'Midias Ops [POS] [BACK]'
            ) THEN 'CSI'
            ELSE 'others'
        END AS pre_and_post_contract
    FROM dw_bpo_performance.customer_contacts_session AS ccs
)
SELECT
    DATE_TRUNC('month', CAST(scoped.ts_submitted AS DATE)) AS ref_month,
    CAST(
        COUNT(DISTINCT CASE WHEN scoped.satisfaction_score IN (1, 2)
            THEN scoped.sk_support_session_fallback_ticket END) AS DOUBLE
    ) / NULLIF(
        CAST(COUNT(DISTINCT CASE WHEN scoped.satisfaction_score IS NOT NULL
            THEN scoped.sk_support_session_fallback_ticket END) AS DOUBLE), 0
    ) AS dsat_front,
    CAST(
        COUNT(DISTINCT CASE WHEN scoped.resolution_survey = true
            THEN scoped.sk_support_session_fallback_ticket END) AS DOUBLE
    ) / NULLIF(
        CAST(COUNT(DISTINCT CASE WHEN scoped.resolution_survey IS NOT NULL
            THEN scoped.sk_support_session_fallback_ticket END) AS DOUBLE), 0
    ) AS resolution_rate
FROM scoped
WHERE scoped.ts_submitted IS NOT NULL
    AND scoped.front_or_back = 'front'
    AND scoped.pre_and_post_contract = 'post-rental'
GROUP BY 1
ORDER BY 1
```

### Query 2 — Recontato D4 and D0 (monthly, Atento + AeC)

```sql
WITH scoped AS (
    SELECT
        ccs.*,
        CASE
            WHEN ccs.last_department IN (
                'CX Partners Tarefas [PRE] [BACK]', 'CX Propostas Tarefas [PRE] [BACK]',
                'OPS - FUP Documentação Rental OA2DS [CLO] [PRE]', 'FUP Carteirização B2C [CLO] [PRE] [BACK]',
                'EARLY DEMAND [CLOSING] [BACK]', 'Closing PP Multi [CLO] [PRE] [BACK]',
                'CX Parceiros Compra e Venda [FRONT]', 'CX Parceiros [FRONT] [PRE]',
                'CX Parceiros da Portaria [FRONT] [PRE]', 'CX Propostas [FRONT] [PRE]',
                'CX Visitas [FRONT] [PRE]', 'Consultores imobiliários 5A',
                '[WH] Credito [FRONT]', '[WH] Closing [FRONT]'
            ) THEN 'pre_rental'
            WHEN ccs.last_department IN (
                'CX Mudança [FRONT] [POS]', 'CX Pagamentos [FRONT] [POS]', 'CX Reparos [FRONT] [POS]',
                'CX Rescisão [FRONT] [POS]', 'Aditivos [REP] [POS] [BACK]', 'Entrada no imóvel [ONB] [POS] [BACK]',
                'CX Pagamentos Ativo [POS] [BACK] [PAY]', 'Alteração de dados bancários [BACK]',
                '[WH] Alteração de dados bancários [Front]', 'Atendimento Escalado [OFF] [POS] [BACK]',
                'Onboarding Back', 'Ongoing Back', '[AeC] CX Ongoing [FRONT] [POS]', 'CX Ongoing [FRONT] [POS]'
            ) THEN 'post-rental'
            WHEN ccs.last_team IN (
                'Onboarding ForRent', 'Ongoing FR - Geral', 'Ongoing FR - Informe de Rendimentos',
                'Payment FR - Aluguel', 'Payment FR - Dados Bancários', 'Payment FR - Condomínio Geral',
                'Payment FR - Reembolso de Condomínio', 'Payment FR - Condomínio Interno',
                'Payment_FR_GeneralCondominium', 'Payment FR - PP Multi', 'Payment FR - Dados Bancários Front',
                'Onboarding Back', 'Payments', 'Ongoing Back', 'Payments Ativo Back', 'Offboarding Front',
                'Offboarding Reparos Back', 'Offboarding - AEC', 'Offboarding - CNX', 'Offboarding Back', 'Payments - DB'
            ) THEN 'post-rental'
            WHEN ccs.last_department IN (
                'Notificação Extrajudicial [CE] [POS] [BACK]', 'CX Conta Comigo [POS] [BACK]',
                'Dados Bancários [CE] [POS] [BACK]', 'Casos Especiais [CE] [POS] [BACK]', 'Midias Ops [POS] [BACK]'
            ) THEN 'CSI'
            ELSE 'others'
        END AS pre_and_post_contract
    FROM dw_bpo_performance.customer_contacts_session AS ccs
)
SELECT
    DATE_TRUNC('month', CAST(scoped.dt_created AS DATE)) AS ref_month,
    CAST(
        COUNT(DISTINCT CASE WHEN scoped.theme_recontact_flag = 1
            AND scoped.agent_organization IN ('atento', 'aec')
            THEN scoped.sk_support_session_fallback_ticket END) AS DOUBLE
    ) / NULLIF(
        CAST(COUNT(DISTINCT CASE WHEN scoped.theme_recontact_flag IS NOT NULL
            AND scoped.agent_organization IN ('atento', 'aec')
            THEN scoped.sk_support_session_fallback_ticket END) AS DOUBLE), 0
    ) AS recontato_d4,
    CAST(
        COUNT(DISTINCT CASE WHEN scoped.theme_recontact_flag_d0 = 1
            AND scoped.agent_organization IN ('atento', 'aec')
            THEN scoped.sk_support_session_fallback_ticket END) AS DOUBLE
    ) / NULLIF(
        CAST(COUNT(DISTINCT CASE WHEN scoped.theme_recontact_flag_d0 IS NOT NULL
            AND scoped.agent_organization IN ('atento', 'aec')
            THEN scoped.sk_support_session_fallback_ticket END) AS DOUBLE), 0
    ) AS recontato_d0
FROM scoped
WHERE scoped.agent_organization IN ('atento', 'aec')
    AND scoped.front_or_back = 'front'
    AND scoped.pre_and_post_contract = 'post-rental'
GROUP BY 1
ORDER BY 1
```

## Superset Golden Assets

Superset charts where these indicators are published (BI reference only — not used in the calculation):

- **DSat — Superset chart** — URN: `urn:li:chart:(superset,chart.60534)` ([link](https://datahub.apps.data-prd.habitat.zone/chart/urn:li:chart:(superset,chart.60534)/Documentation?is_lineage_mode=false))
- **Recontato Front — Superset chart** — URN: `urn:li:chart:(superset,chart.60863)` ([link](https://datahub.apps.data-prd.habitat.zone/chart/urn:li:chart:(superset,chart.60863)/Documentation?is_lineage_mode=false))
