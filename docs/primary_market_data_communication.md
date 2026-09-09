# Mercado Primário: mudanças de dados e guia de uso

**Atualizado em:** 03/09/2026  
**Fonte do estado do código:** `origin/master` atualizado localmente  
**Público:** Produto, Operações, Analytics, Data e Engineering

## Resumo executivo

O modelo de Mercado Primário mantém o `house_id` como chave de compatibilidade
com o stack existente, mas passa a representar uma estrutura 1:N:

```text
empreendimento
  └── tipologia
        ├── house de vitrine (shell): usada para catálogo e visita
        └── N houses de unidade: criadas para propostas/ofertas
```

Foram criadas novas tabelas enrich para conectar houses a empreendimento,
tipologia e negociação. Em paralelo, a classificação de mercado está sendo
propagada como `sale_type` (`PRIMARY` ou `SECONDARY`) nos fatos de visita,
oferta e eventos.

Há duas dimensões diferentes que não devem ser confundidas:

| Sinal | O que responde | Valores |
|---|---|---|
| `sale_type` | A operação é Mercado Primário ou Secundário? | `PRIMARY`, `SECONDARY`, `NULL` |
| `is_primary_market` | Booleano de compatibilidade derivado de `sale_type` | `TRUE` somente para `sale_type = 'PRIMARY'`; `FALSE` para `SECONDARY` ou `NULL` |
| `is_3p_supply` | O imóvel veio de parceiro 3P? | `TRUE`, `FALSE` |

`is_3p_supply` é eixo de origem/parceria e não substitui `sale_type`.

## Status das mudanças

`Master` significa mudança já presente no código-base. `Em PR` significa mudança
ainda não incorporada ao código-base. Todas as propagações listadas abaixo já
estão em `Master`. Nenhum dos rótulos garante que a
tabela esteja disponível no ambiente produtivo. Mesmo mudanças no master
precisam aguardar a execução do DAG e a atualização do catálogo físico.
O catálogo físico pode ficar temporariamente atrasado em relação ao SQL
publicado.

### Tabelas e colunas ajustadas

| Camada | Tabela | Mudança | Como usar | Status |
|---|---|---|---|---|
| Clean | `datalake_ebdb_clean.listing_sale_model` | `sale_type` e flag legada `is_primary_market` na origem | `sale_type` é a fonte da classificação; a flag legada não deve ser usada | Master |
| Enrich | `datalake_sale_primary_market.listing_sale_type` | Um `sale_type` por house, com faixa de preço | SSOT de classificação house/listing | Master |
| Enrich | `datalake_sale_offer.core_sale_offer` | `sale_type` no grain de oferta, vindo de Sales Flow | Classificação nativa da oferta | Master, [PR #28295](https://github.com/quintoandar/bi-etl-ejuice/pull/28295) |
| Enrich | `datalake_sale_offer.sale_offer` | Propaga `sale_type` de `core_sale_offer` | Camada enrich consumida pelo DW de ofertas | Master, [PR #28320](https://github.com/quintoandar/bi-etl-ejuice/pull/28320) |
| Enrich | `datalake_sale_visit.sale_visit` | `sale_type` por visita SALE | Ponto de entrada do fato de visitas For Sale | Master |
| Enrich | `datalake_sale_flows.sale_flow` | `sale_type` derivado das ofertas do fluxo | Classifica fluxos com oferta; booking/TTA-only ficam NULL | Master, [PR #28350](https://github.com/quintoandar/bi-etl-ejuice/pull/28350) |
| Enrich | `datalake_buyer_prospect.buyer_prospect_type` | `sale_type` e `bp_market_type` por ativação | Segmenta ativação PRIMARY e exclusividade de mercado | Master, [PR #28359](https://github.com/quintoandar/bi-etl-ejuice/pull/28359) |
| DW | `dw_visit.fact_visits` | `sale_type` para visitas SALE | Filtre `business_context = 'SALE'` e `sale_type = 'PRIMARY'` | Master |
| DW | `dw_visit.fact_visit_schedules` | `sale_type` por schedule | Filtre `business_context = 'SALE'` e `sale_type = 'PRIMARY'` | Master |
| DW | `dw_sale.fact_visits` | `sale_type` no fato de visitas For Sale | Ponto de entrada para eventos de visita | Master |
| DW | `dw_sale.fact_daily_ongoing_listing` | `sale_type` no snapshot diário | Métricas de estoque/listings em andamento; sem `is_3p_supply` nativo | Master |
| DW | `dw_sale.dim_listing` | `sale_type` novo; `is_primary_market` derivado dele | Use `sale_type`; a flag existe apenas para compatibilidade | Master, [PR #28332](https://github.com/quintoandar/bi-etl-ejuice/pull/28332) |
| DW | `dw_sale.fact_listings` | `sale_type` por listing | Métricas de publicação e listing | Master, [PR #28332](https://github.com/quintoandar/bi-etl-ejuice/pull/28332) |
| DW | `dw_sale.fact_listing_price_changes` | `sale_type` por house | Segmentar alterações de preço; classificação é latest-per-house, não as-of | Master, [PR #28332](https://github.com/quintoandar/bi-etl-ejuice/pull/28332) |
| DW | `dw_sale.fact_offers` | `sale_type` por oferta | Ponto de entrada padrão do funil de ofertas | Master, [PR #28320](https://github.com/quintoandar/bi-etl-ejuice/pull/28320) |
| DW | `dw_sale.dim_offer` | `sale_type` por oferta | Atributo de oferta junto do `sk_offer` | Master, [PR #28329](https://github.com/quintoandar/bi-etl-ejuice/pull/28329) |
| DW | `dw_sale.dim_sale_agreement` | `sale_type` por CCV/oferta | Segmentar acordos por mercado | Master, [PR #28329](https://github.com/quintoandar/bi-etl-ejuice/pull/28329) |
| DW | `dw_sale.fact_sale_demand_event` | `sale_type` de visitas e ofertas | Segmentar eventos sem join adicional | Master, [PR #28320](https://github.com/quintoandar/bi-etl-ejuice/pull/28320) |
| DW | `dw_sale.fact_sale_flows` | `sale_type` derivado da oferta | Segmentar o fluxo buyer-house quando há oferta | Master, [PR #28350](https://github.com/quintoandar/bi-etl-ejuice/pull/28350) |

`datalake_visit.visit_schedules` não recebe `sale_type` nativo nesta onda.
Ele continua sendo a origem de schedules; a classificação é adicionada nas
camadas enrich/DW por meio do SSOT de house.

Os sinais `is_sale_primary_market` e `is_primary_market` continuam disponíveis
em algumas dimensões por compatibilidade. Ambos devem ser entendidos como
derivações de `sale_type`; o terceiro sinal, `is_3p_supply`, representa origem
3P e não mercado.

### Novas tabelas enrich de Mercado Primário

| Tabela | Grain | Papel |
|---|---|---|
| `datalake_sale_primary_market.listing_sale_type` | Uma linha por house | Centraliza a classificação `PRIMARY`/`SECONDARY` de listing SALE |
| `datalake_sale_primary_market.house_development` | Uma linha por house ligada a empreendimento | Denormaliza empreendimento, tipologia, atributos, amenities e contato para o grain de house |
| `datalake_sale_primary_market.development_negotiation` | Uma linha por negociação pré-OS | Conecta empreendimento, visita, unidade, oferta e Sales Flow sem usar `id_visit` como chave da oferta |

### Novas tabelas DW de Mercado Primário

Estas tabelas não precisam de `sale_type` próprio para os principais casos de
uso, porque já carregam a chave nativa de empreendimento ou negociação:

| Tabela | Grain | Papel |
|---|---|---|
| `dw_sale_primary_market.dim_house_development` | Uma linha por house | Dimensão de house com empreendimento, tipologia, região, cidade e faixa de preço |
| `dw_sale_primary_market.fact_development_negotiation` | Uma linha por negociação | Fato de negociação pré-OS com house da visita, house da unidade, oferta, fluxo, hub e EN |

Na consulta física realizada em 03/09/2026, `fact_development_negotiation`
estava registrado no catálogo Trino, enquanto `dim_house_development` ainda
aguardava a primeira execução/registro físico.

## Como usar `sale_type`

### Fatos de visita

Use o campo nativo do fato:

```sql
SELECT
    sale_type,
    COUNT(*) AS number_of_visits
FROM
    dw_visit.fact_visits
WHERE
    business_context = 'SALE'
    AND sale_type = 'PRIMARY'
GROUP BY
    sale_type
```

No `dw_visit.fact_visits` e no `dw_visit.fact_visit_schedules`, `sale_type`
fica `NULL` para RENT e também pode ficar `NULL` quando não houver classificação
de listing.

### Fatos de oferta e eventos

Após o merge da [PR #28320](https://github.com/quintoandar/bi-etl-ejuice/pull/28320)
e a execução dos DAGs correspondentes, use `sale_type` diretamente:

```sql
SELECT
    sale_type,
    COUNT(*) AS number_of_offers
FROM
    dw_sale.fact_offers
WHERE
    sale_type = 'PRIMARY'
GROUP BY
    sale_type
```

No `dw_sale.fact_sale_demand_event`, a origem depende do tipo de evento:

| `sk_event_type` | Evento | Origem de `sale_type` |
|---:|---|---|
| 1 | Visit booked | `dw_sale.fact_visits.sale_type` |
| 2 | Visit completed | `dw_sale.fact_visits.sale_type` |
| 7 | Visit canceled | `dw_sale.fact_visits.sale_type` |
| 3 | Offer submitted | `dw_sale.fact_offers.sale_type` |
| 4 | Offer accepted | `dw_sale.fact_offers.sale_type` |
| 5 | Sale agreement created | `dw_sale.fact_offers.sale_type` |
| 6 | Sale agreement signed | `dw_sale.fact_offers.sale_type` |
| 8 | Offer dismissed | `dw_sale.fact_offers.sale_type` |

Assim, uma análise do funil pode filtrar:

```sql
SELECT
    sk_event_type,
    COUNT(*) AS number_of_events
FROM
    dw_sale.fact_sale_demand_event
WHERE
    sale_type = 'PRIMARY'
GROUP BY
    sk_event_type
```

## KPIs de negócio e exemplos

Os exemplos abaixo usam as tabelas novas ou as colunas propagadas. Substitua
as partições de data pelos dias desejados antes de executar os exemplos de
snapshot.

### Q1: houses e listings PRIMARY publicados atualmente

```sql
SELECT
    COUNT(DISTINCT sk_house) AS n_primary_houses_published,
    COUNT(DISTINCT sk_sale_listing) AS n_primary_listings_published
FROM
    dw_sale.dim_listing
WHERE
    sale_type = 'PRIMARY'
    AND status = 'PUBLISHED'
```

`is_primary_market` continua disponível apenas para compatibilidade e é derivado
de `sale_type`. Use sempre `sale_type = 'PRIMARY'` em novas consultas.

### Q2: preço médio, maior e menor

`listing_sale_type` já contém a classificação e a faixa de preço da mesma
linha mais recente de `ListingSaleModel`:

```sql
SELECT
    COUNT(*) AS n_houses,
    COUNT(min_price) AS n_with_price,
    AVG(min_price) AS avg_min_price,
    AVG(max_price) AS avg_max_price,
    MAX(max_price) AS highest_price,
    MIN(min_price) AS lowest_price
FROM
    datalake_sale_primary_market.listing_sale_type
WHERE
    sale_type = 'PRIMARY'
```

`ListingSaleModel.sale_type` é a fonte da classificação. Quando está NULL, a
tabela SSOT classifica como `SECONDARY`; a flag legada não é usada como fallback.

### Q3: número de empreendimentos distintos

Após a primeira execução do DW de Mercado Primário:

```sql
SELECT
    COUNT(DISTINCT id_development) AS n_developments
FROM
    dw_sale_primary_market.dim_house_development
```

Enquanto a dimensão DW não estiver registrada, use
`datalake_sale_primary_market.house_development`.

### Q4: número de tipologias por empreendimento

```sql
WITH per_development AS (
    SELECT
        id_development,
        COUNT(DISTINCT id_development_typology) AS n_typologies
    FROM
        dw_sale_primary_market.dim_house_development
    GROUP BY
        id_development
)
SELECT
    COUNT(*) AS n_developments_with_typology,
    AVG(n_typologies) AS avg_typologies_per_development,
    MAX(n_typologies) AS max_typologies_per_development
FROM
    per_development
```

Use `COUNT(DISTINCT id_development_typology)` porque a dimensão tem grain de
house e várias houses podem pertencer à mesma tipologia.

### Q5: área e quartos médios das tipologias

```sql
WITH unique_typologies AS (
    SELECT DISTINCT
        id_development_typology,
        total_area,
        bedrooms
    FROM
        dw_sale_primary_market.dim_house_development
)
SELECT
    COUNT(*) AS n_typologies,
    COUNT(total_area) AS n_with_area,
    AVG(total_area) AS avg_total_area_m2,
    AVG(bedrooms) AS avg_bedrooms
FROM
    unique_typologies
```

### Validação dos exemplos contra as origens

Consulta realizada em 03/09/2026:

| KPI | Resultado |
|---|---|
| Q1, classificação de houses publicadas | A origem retornou 476 houses; `dw_sale.dim_listing` retornou 401. A dimensão exige joins adicionais com `sale_listing` e `sale_listing_demand`, então tem menor cobertura. |
| Q2, preços PRIMARY | `listing_sale_type` e a origem com o mesmo fallback retornaram 5.303 houses, 536 com preço e os mesmos valores médio, máximo e mínimo. |
| Q3, empreendimentos | Origem e `house_development` retornaram 200 empreendimentos. |
| Q4, tipologias | Origem e `house_development` retornaram 200 empreendimentos, média 2,68 tipologias e máximo 9. |
| Q5, atributos de tipologia | Origem e `house_development` retornaram 536 tipologias, 536 com área, média de 111,95 m² e 2,28 quartos. |

Q1 deve ser interpretado como um KPI da cobertura da dimensão de listing.
Para medir todas as houses publicadas na origem, use a origem de
`listing_business_context` junto com a classificação SSOT e documente essa
diferença de cobertura.

### Q6: visitas booked e completed PRIMARY

Use schedules para contar bookings e conclusões no mesmo grain:

```sql
SELECT
    COUNT(DISTINCT CASE WHEN is_booking = 1 THEN sk_schedule END) AS n_primary_visit_booked,
    COUNT(DISTINCT CASE WHEN is_completed = 1 THEN sk_schedule END) AS n_primary_visit_completed,
    1.0 * COUNT(DISTINCT CASE WHEN is_completed = 1 THEN sk_schedule END)
        / NULLIF(COUNT(DISTINCT CASE WHEN is_booking = 1 THEN sk_schedule END), 0) AS visit_completion_rate
FROM
    dw_visit.fact_visit_schedules
WHERE
    sale_type = 'PRIMARY'
    AND year = 2026
    AND month = 9
    AND day = 2
```

### Q7: conversão do funil PRIMARY

`fact_sale_demand_event` permite calcular as etapas no mesmo fato:

```sql
WITH primary_event_counts AS (
    SELECT
        COUNT(DISTINCT CASE WHEN sk_event_type = 1 THEN sk_sale_demand_event END) AS vb,
        COUNT(DISTINCT CASE WHEN sk_event_type = 2 THEN sk_sale_demand_event END) AS vc,
        COUNT(DISTINCT CASE WHEN sk_event_type = 3 THEN sk_sale_demand_event END) AS os,
        COUNT(DISTINCT CASE WHEN sk_event_type = 4 THEN sk_sale_demand_event END) AS oa,
        COUNT(DISTINCT CASE WHEN sk_event_type = 6 THEN sk_sale_demand_event END) AS ccv
    FROM
        dw_sale.fact_sale_demand_event
    WHERE
        sale_type = 'PRIMARY'
        AND year = 2026
        AND month = 9
        AND day = 2
)
SELECT
    vb,
    vc,
    os,
    oa,
    ccv,
    1.0 * vc / NULLIF(vb, 0) AS vb_to_vc_rate,
    1.0 * oa / NULLIF(os, 0) AS os_to_oa_rate,
    1.0 * ccv / NULLIF(os, 0) AS os_to_ccv_rate
FROM
    primary_event_counts
```

### Q8: conversão de ofertas PRIMARY

Use as chaves de data do fato de ofertas para medir OA e CCV:

```sql
SELECT
    COUNT(DISTINCT sk_offer) AS n_primary_offers,
    COUNT(DISTINCT CASE WHEN sk_offer_accepted_date <> -1 THEN sk_offer END) AS n_primary_offers_accepted,
    COUNT(DISTINCT CASE WHEN sk_sale_agreement_signed_date <> -1 THEN sk_offer END) AS n_primary_ccvs_signed,
    1.0 * COUNT(DISTINCT CASE WHEN sk_offer_accepted_date <> -1 THEN sk_offer END)
        / NULLIF(COUNT(DISTINCT sk_offer), 0) AS offer_acceptance_rate,
    1.0 * COUNT(DISTINCT CASE WHEN sk_sale_agreement_signed_date <> -1 THEN sk_offer END)
        / NULLIF(COUNT(DISTINCT sk_offer), 0) AS offer_to_ccv_rate
FROM
    dw_sale.fact_offers
WHERE
    sale_type = 'PRIMARY'
```

### Q9: compradores com oferta PRIMARY

`fact_buyer_prospects` ainda não tem `sale_type`. Este é um proxy explícito
para compradores que chegaram à etapa de oferta:

```sql
SELECT
    COUNT(DISTINCT sk_buyer) AS n_buyers_with_primary_offer,
    COUNT(DISTINCT sk_house) AS n_houses_with_primary_offer,
    COUNT(DISTINCT sk_offer) AS n_primary_offers
FROM
    dw_sale.fact_offers
WHERE
    sale_type = 'PRIMARY'
```

Não use esse proxy como contagem de todos os prospects PRIMARY. Para isso,
`fact_buyer_prospects` precisa receber uma classificação própria ou uma nova
definição de grain.

### Q10: compradores PRIMARY por exclusividade de mercado

O novo campo `bp_market_type` é diferente de `bp_type`:

- `bp_type`: NBP/RBP, ou seja, novo versus recorrente;
- `bp_market_type`: PRIMARY_EXCLUSIVE, NON_EXCLUSIVE ou
  SECONDARY_EXCLUSIVE.

Para analisar compradores que tiveram uma ativação no Mercado Primário:

```sql
SELECT
    bp_market_type,
    bp_type,
    COUNT(DISTINCT id_prospect) AS n_buyers,
    COUNT(*) AS n_activation_events,
    COUNT(DISTINCT id_house) AS n_houses,
    COUNT(DISTINCT id_offer) AS n_offers
FROM
    datalake_buyer_prospect.buyer_prospect_type
WHERE
    sale_type = 'PRIMARY'
GROUP BY
    bp_market_type,
    bp_type
ORDER BY
    bp_market_type,
    bp_type
```

Resultado observado em 03/09/2026: 7 compradores
`PRIMARY_EXCLUSIVE`/`NBP` e 3 compradores `NON_EXCLUSIVE`/`RBP`.
`id_offer` pode ficar NULL porque a ativação também pode ser originada por
visita. Use `dw_sale.fact_offers` para KPIs da etapa de oferta.

Para visualizar todos os segmentos, remova `sale_type = 'PRIMARY'`. Nesse
caso, `SECONDARY_EXCLUSIVE` representa compradores que nunca tocaram o
Mercado Primário dentro da janela configurada.

### Ofertas PRIMARY

Use `fact_offers` para medir ofertas no grain de oferta:

```sql
SELECT
    sale_type,
    COUNT(DISTINCT sk_offer) AS number_of_offers,
    SUM(sale_price_agreed) AS total_agreed_value,
    AVG(sale_price_agreed) AS average_agreed_value
FROM
    dw_sale.fact_offers
WHERE
    sale_type = 'PRIMARY'
GROUP BY
    sale_type
```

### Funil de eventos PRIMARY

Use `fact_sale_demand_event` para contar cada etapa do funil. Filtre as
partições quando consultar um período específico:

```sql
SELECT
    sk_event_type,
    COUNT(DISTINCT sk_sale_demand_event) AS number_of_events
FROM
    dw_sale.fact_sale_demand_event
WHERE
    sale_type = 'PRIMARY'
    AND year = 2026
    AND month = 9
    AND day BETWEEN 1 AND 2
GROUP BY
    sk_event_type
ORDER BY
    sk_event_type
```

### Fluxos buyer-house PRIMARY

`fact_sale_flows` é offer-side. Fluxos iniciados apenas por booking ou TTA
ficam com `sale_type = NULL`:

```sql
SELECT
    sale_type,
    COUNT(DISTINCT sk_sale_flow) AS number_of_sale_flows,
    SUM(bookings) AS number_of_bookings,
    SUM(visits_completed) AS number_of_completed_visits,
    SUM(offers_submitted) AS number_of_offers
FROM
    dw_sale.fact_sale_flows
WHERE
    sale_type = 'PRIMARY'
GROUP BY
    sale_type
```

### Estoque PRIMARY por snapshot

`fact_daily_ongoing_listing` tem grain listing-dia. `SUM(sale_price)` abaixo
representa valor de listings e pode contar mais de uma listing da mesma house:

```sql
SELECT
    COUNT(DISTINCT sk_house) AS number_of_houses,
    COUNT(DISTINCT sk_sale_listing) AS number_of_listings,
    SUM(sale_price) AS total_listing_value,
    AVG(sale_price) AS average_listing_price
FROM
    dw_sale.fact_daily_ongoing_listing
WHERE
    sale_type = 'PRIMARY'
    AND year = 2026
    AND month = 9
    AND day = 2
```

### Houses por empreendimento

Use a dimensão específica de Mercado Primário para contar houses e tipologias
sem repetir os joins de Desenvolvimento:

```sql
SELECT
    id_development,
    COUNT(DISTINCT id_house) AS number_of_houses,
    COUNT(DISTINCT id_development_typology) AS number_of_typologies
FROM
    dw_sale_primary_market.dim_house_development
GROUP BY
    id_development
ORDER BY
    number_of_houses DESC
```

### Listing/house quando não houver campo nativo

Para uma tabela que ainda não tenha `sale_type`, use a dimensão de listing ou
o SSOT enrich:

```sql
SELECT
    fact.sk_house,
    lst.sale_type
FROM
    dw_sale.fact_daily_ongoing_listing AS fact
LEFT JOIN
    datalake_sale_primary_market.listing_sale_type AS lst
        ON fact.sk_house = lst.id_house
WHERE
    lst.sale_type = 'PRIMARY'
```

Quando já existir uma coluna nativa no fato, prefira essa coluna. Evite
repetir o join com `listing_sale_type`.

### Negociação e empreendimento

Para análises de negociação pré-OS, filtre o `actor` antes de contar
negociações:

```sql
SELECT
    id_development,
    actor,
    COUNT(*) AS number_of_negotiations
FROM
    datalake_sale_primary_market.development_negotiation
WHERE
    actor = 'DEMAND'
GROUP BY
    id_development,
    actor
```

`AGENT` representa negociação criada por ou para corretor. `DEMAND` representa
negociação criada pela demanda. Misturar os dois atores pode inflar o volume
de propostas.

## Design dos dois caminhos de `id_house`

### Por que existem dois caminhos

No Secundário, uma listing normalmente aponta para uma house. No Primário,
uma tipologia serve como vitrine e pode gerar várias unidades concretas. Por
isso, o mesmo empreendimento pode aparecer com:

1. uma house de vitrine, usada para catálogo e visita;
2. várias houses de unidade, criadas para propostas/ofertas.

Essas houses são `Imovel.id` no EBDB. O `id_house` interno de
`datalake_sales_flow_clean.house.id` é outra chave e não deve ser usado como
`Imovel.id`. A ponte do Sales Flow para Imovel é:

```text
datalake_sales_flow_clean.house.id_external = EBDB Imovel.id
```

### Caminho A: house de desenvolvimento/listing shell

```text
Development
  └── DevelopmentTypology
        └── house.id_development_typology
              └── house.id (Imovel da vitrine)
                    └── listing / catálogo / visita
```

Esse é o `id_house` da listing de tipologia, a vitrine. No contexto de uma
visita, ele aparece em:

```text
development_negotiation.id_visit
  → visit.id_house
  → development_negotiation.id_house_development
```

`id_house_development` identifica a house na qual a visita foi agendada.

### Caminho B: house de unidade/oferta

```text
Development
  └── DevelopmentTypology
        └── DevelopmentTypologyUnit
              └── development_typology_unit.id_house
                    └── Imovel da unidade
                          └── Sales Flow house.id_external
                                └── offer / Sales Flow / CCV
```

Esse é o `id_house` da unidade concreta usada pela proposta ou oferta. Em
`development_negotiation`, o caminho é:

```text
development_negotiation
  → development_negotiation_unit
    → development_typology_unit.id_house
      → development_negotiation.id_house
```

O `id_house` da unidade é então relacionado ao Sales Flow por
`sales_flow.house.id_external`. A tabela `development_negotiation` expõe
também `id_offer` e `id_sales_flow` após essa resolução.

### Como `house_development` unifica os caminhos

`datalake_sale_primary_market.house_development` entrega uma linha no grain de
house e resolve a tipologia com a seguinte prioridade:

```text
development_typology_unit.id_development_typology
  → house.id_development_typology
```

Ou seja, quando existe uma unidade de oferta, a tipologia da unidade é usada;
caso contrário, a tabela usa a tipologia da house de vitrine. O consumidor
pode usar `id_house`, `id_development` e `id_development_typology` sem
reimplementar os dois joins.

### Regras de join

- `id_house_development` = listing/vitrine onde a visita aconteceu.
- `id_house` = Imovel da unidade criada para a proposta/oferta.
- `id_visit` = contexto de origem da negociação, não chave de match com oferta.
- Para conectar negociação e Sales Flow, use `id_house` da unidade e
  `sales_flow.house.id_external`.
- Não use `id_visit` para encontrar a oferta.
- Uma visita pode originar várias negociações quando o comprador quer mais de
  uma unidade.
- O mesmo apartamento físico pode receber uma nova house em outra negociação.
  Não deduplique unidades apenas por endereço ou número do apartamento.
- Uma negociação não deve conter duas unidades abertas; interesse em duas
  unidades resulta em negociações/houses separadas.

## O que ainda não está coberto

Estas tabelas não recebem `sale_type` ou `is_primary_market` nesta onda:

- `dw_sale.fact_buyer_prospects`;
- `dw_sale.fact_closing_flows`;
- `dw_sale.fact_sale_cohort_conversion`, que ainda precisa de uma definição
  para o tipo do evento base versus o tipo do evento de conversão;
- NPS, que possui `sk_offer` em alguns fluxos, mas não a classificação;
- `dw_house.dim_house_entrance_history`, que possui segmentação nativa de
  acesso (`entry_model_type`, `entry_model_channel`, `entry_model_details`),
  não segmentação de mercado;
- `datalake_visit.visit_schedules`, que não possui coluna nativa e recebe a
  classificação apenas nos fatos/escopos derivados;
- `dw_listing.fact_listing_events`, que não foi encontrado no repositório nem
  no catálogo consultado.

`NULL` em `sale_type` não significa `SECONDARY`. Pode significar fonte
histórica, Firestore, Sales Flow sem classificação ou ausência de uma listing
SALE correspondente.

## Mensagem pronta para stakeholders

> Atualizamos o modelo de Mercado Primário mantendo compatibilidade com o
> `house_id` existente. Agora temos uma classificação de mercado
> (`sale_type = PRIMARY/SECONDARY`) propagada para visitas, schedules, ofertas
> e eventos, além de uma camada de novas tabelas enrich para conectar house,
> tipologia, empreendimento e negociação.
>
> Para análises de oferta, usem `dw_sale.fact_offers.sale_type`. Para eventos,
> usem `dw_sale.fact_sale_demand_event.sale_type`. Para visitas, usem
> `dw_visit.fact_visits.sale_type` ou
> `dw_visit.fact_visit_schedules.sale_type`. Para dados de empreendimento,
> usem `datalake_sale_primary_market.house_development`. Para pré-OS,
> usem `datalake_sale_primary_market.development_negotiation` e filtrem
> `actor`.
>
> Atenção: `id_house_development` é a house de vitrine da visita; `id_house` é
> a house da unidade usada na oferta. `id_visit` é contexto de origem e não
> deve ser usado como chave para conectar oferta. `NULL` não deve ser tratado
> como Secundário.
