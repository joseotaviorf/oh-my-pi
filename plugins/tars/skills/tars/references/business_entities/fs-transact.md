# FS Transact — Business Context & Analytics Guide (TARS)

> Written for TARS, QuintoAndar's analytics AI assistant. Combines business knowledge, data model, metric formulas, and SQL patterns needed to answer FS Transact questions correctly. Read this before writing any SQL for the For Sale transaction funnel.
>
> Last enriched: 2026-06-03 via Superset metadata (TARS session x7k2m9).
> Disclaimer: The numbers in this documents represent a rough estimate based on observations at the time this file was updated. Use them as a reference, but not as a definitive answer for users.

---

## 1. Contexto e Escopo

**FS Transact** é o funil de transação do negócio For Sale (Venda) da QuintoAndar — da primeira oferta submetida pelo comprador até a entrega das chaves e registro do imóvel em cartório.

O funil tem dois grandes blocos:

| Bloco | Escopo | Relevância de receita |
|-------|--------|-----------------------|
| **EoF — End of Funnel** | Offer Submitted (OS) → Closed Deal (CD) | CD = evento oficial de receita do time Financeiro |
| **EoP — End of Process** | CCV assinado → Chaves + CRI | Obrigações pós-fechamento |

> ⚠️ **Escopo: transações 1P exclusivamente.** Transações 3P (`payment_model = 'CLOSING_3P'`) seguem fluxo completamente diferente. **Nunca misturar 1P e 3P na mesma análise.** Aplicar sempre os filtros da seção 7.

> ⚠️ **CCV ≠ CD (crítico):**
> - **CCV** (`fact_offers.ts_sale_agreement_signed`) = contrato assinado. Marco comercial/pipeline.
> - **CD** (`fact_closing_flows.sk_legal_analysis_ended_date`) = CCV que completou DD + Termo de Corretagem. **Métrica oficial de vendas do time Financeiro.** Usar CD para qualquer análise financeira/revenue; usar CCV para análises de pipeline e conversão.

---

## 2. Glossário e Sinônimos

| Termo | Significado | Fonte de dados |
|-------|-------------|----------------|
| **FS / For Sale / Venda** | Negócio de compra e venda residencial da QuintoAndar | — |
| **FS Transact / Transação de Venda** | Jornada completa OS → Entrega de Chaves | — |
| **EoF / End of Funnel** | Sub-funil OS → OA → SAC → CD. Bloco de reconhecimento de receita. | — |
| **EoP / End of Process** | Sub-funil CD → Registro → Chaves. Obrigações pós-fechamento. | — |
| **OS / Offer Submitted / Proposta Enviada** | Comprador submete oferta de compra | `fact_offers.ts_offer_submitted` |
| **OA / Offer Accepted / Proposta Aceita** | Proprietário aceita a oferta | `fact_offers.ts_offer_accepted` |
| **OR / Offer Rejected / Dismissed / Proposta Recusada** | Oferta descartada antes do aceite | `fact_offers.ts_offer_dismissed` |
| **SAC / Sale Agreement Created / CCV Criado** | Esboço de CCV criado — marco de pipeline, NÃO receita | `fact_offers.ts_sale_agreement_created` |
| **CCVe / CCV esboçado** | CCV em rascunho | `fact_offers.ts_sale_agreement_drafted` |
| **CCV / Compromisso de Compra e Venda / Sale Agreement Signed** | Contrato assinado. Marco comercial. **Não é CD.** | `fact_offers.ts_sale_agreement_signed` |
| **CD / Closed Deal / Venda / Fechamento** | CCV que passou por DD + Termo de Corretagem. **Métrica oficial de vendas do Financeiro.** | `fact_closing_flows.sk_legal_analysis_ended_date` |
| **BP / Buyer Prospect** | Comprador com visita agendada (VISIT_BOOKED) em For Sale. **Fonte correta: `fact_sale_demand_event`.** | `fact_sale_demand_event` WHERE `event_name = 'VISIT_BOOKED'` |
| **NBP / New Buyer Prospect** | Primeira visita ever do buyer na plataforma (~70% do BP mensal) | `dim_buyer_prospect_type.buyer_prospect_type = 'NBP'` |
| **RBP / Recovery Buyer Prospect** | Buyer retornando após inatividade (~30% do BP mensal) | `dim_buyer_prospect_type.buyer_prospect_type = 'RBP'` |
| **BP2CCV** | Conversão BP → CCV. Coorte M0+M1 no Fibonacci. | `sandbox.summary_table` (oficial); aproximar via `fact_sale_demand_event` + `fact_offers` |
| **Diligência / Due Diligence** | Revisão jurídica pós-CCV (house, seller, report) | `dim_sale_agreement.*_dilligence_status` |
| **Escritura** | Lavratura da escritura no Cartório de Notas (Cash track) | — |
| **Registro / CRI** | Registro formal de propriedade no Cartório de Registro de Imóveis | `fact_closing_flows.sk_house_registry_ended_date` |
| **Entrega de Chaves** | Entrega física das chaves ao comprador | `fact_closing_flows.sk_sale_key_delivered_date` |
| **Sinal / Earnest Payment** | ~6% do preço de venda, retido pela QuintoAndar | — |
| **Regularização** | Atualizações de registro e ajustes jurídicos (Legal Ops) | — |
| **ROFR / Direito de Preferência** | Cláusula de preferência de compra para inquilinos | — |
| **Averbação** | Anotação de registro; adiciona ~23 dias ao LT Cash quando presente | — |
| **Matrícula** | Certidão de registro do imóvel; obrigatória no ROFR | — |
| **ITBI** | Imposto municipal de transmissão de imóvel | — |
| **FGTS** | Fundo de Garantia; pode ser usado para complementar pagamento | — |
| **EN / Negotiation Executive** | Agente interno que media a negociação de ofertas | `fact_offers.sk_closing_specialist` (filtrar `<> -1`) |
| **SPOC** | Single Point of Contact — agente de ops que suporta o cliente no EoP | Salesforce; não mapeado no DW |
| **Corban** | Correspondente bancário que intermedeia financiamento. **Internal Corban** (~14% dos casos de financiamento) ou **Partner Corban** (~86%). | `dw_atta.fact_pre_analysis_proposal_flow` → `franchise_name LIKE '%Quinto Andar%'` = Internal Corban |
| **CRN / Cartório de Notas** | Cartório que executa a escritura no track Cash | — |
| **IQ / Interveniente Quitante** | Pagamento ao credor anterior no track Mortgage | — |
| **Credit Model** | Modelo de financiamento | `dim_sale_agreement.credit_model` |
| **Payment Method** | Método de pagamento da transação | `dim_sale_agreement.payment_method` |
| **Domi / Vandinha** | Agente conversacional de AI em desenvolvimento para suporte EoP | — |
| **Lego Contract** | Sistema de geração automatizada de CCV (Legal Ops) | — |
| **Legaut** | Sistema interno de automações e crawlers de Due Diligence | — |

---

## 3. EoF — End of Funnel

### 3.1 Estágios do funil e timestamps canônicos

Todos os eventos EoF têm fonte em `dw_sale.fact_offers` (1 linha por oferta):

| Estágio | Abrev | Fonte | Notas |
|---------|-------|-------|-------|
| Offer Submitted | OS | `fact_offers.ts_offer_submitted` | Ponto de entrada do FS Transact |
| Offer Accepted | OA | `fact_offers.ts_offer_accepted` | Proprietário aceita |
| Offer Rejected / Dismissed | OR | `fact_offers.ts_offer_dismissed` | Antes do aceite |
| Offer Cancelled | — | `fact_offers.ts_offer_canceled` | Antes ou depois do aceite |
| Offer Rescued | — | `fact_offers.ts_offer_rescued` | `dim_offer.is_a_rescued_offer = TRUE` |
| Sale Agreement Created | SAC | `fact_offers.ts_sale_agreement_created` | Marco de pipeline — NÃO é receita |
| Sale Agreement Drafted | CCVe | `fact_offers.ts_sale_agreement_drafted` | CCV em rascunho |
| **Sale Agreement Signed** | **CCV** | **`fact_offers.ts_sale_agreement_signed`** | **Marco comercial. NÃO é CD.** |
| Sale Agreement Cancelled | — | `fact_offers.ts_sale_agreement_canceled` | `dim_sale_agreement.is_ccv_canceled = TRUE` |
| CCV Rescued | — | `dim_sale_agreement.is_a_rescued_ccv = TRUE` | — |
| **Closed Deal** | **CD** | **`fact_closing_flows.sk_legal_analysis_ended_date`** | **CCV + DD aprovado + TC. Métrica oficial de vendas do Financeiro.** |

### 3.2 O que acontece em cada estágio

**OS → OA (Negociação de Oferta)**
EN medeia negociação de preço entre comprador e vendedor. Estágio de menor conversão (~60% OS→OA). Drivers de queda: desalinhamento de preço, desconto alto, urgência do vendedor, capacidade/habilidade do EN. Experiência de produto QA é mínima — quase toda a interação é pelo EN.

**OA → CCV (Contrato)**
Legal Ops conduz: coleta de documentos, validação cruzada, geração de CCV, assinatura digital. ~25% dos CCVs passam por ajustes contratuais. Análise de crédito para casos financiados ocorre em paralelo aqui.

**CCV → CD (Due Diligence + Termo de Corretagem)**
CD = CCV que completou:
1. **Due Diligence (DD)** — revisão jurídica de vendedor e imóvel (~9 dias em média; ~80% dos casos são "Sem Apontamento" ou "Baixo Risco")
2. OU **Termo de Corretagem (TC)** — quando as partes seguem com CCV próprio, sem os serviços do QuintoAndar, elas assinam um termo de corretagem que garante o pagamento da corretagem da QuintoAndar. Nesses casos pode ter uma DD, mas simplificada.

CD é o evento de receita do time Financeiro. Fonte no produto é: `fact_closing_flows.sk_legal_analysis_ended_date`. A fonte que contém todos os CD, incluindo termos de corretagens e operações fora do produto é a `datalake_gsheets_clean.closed_deals`. 

### 3.3 Atribuição de queda EoF (Abr 2026)

~50% dos drops são acionáveis (o restante é não-acionável: comprador decidiu alugar, vendedor fechou com outro, etc.):

| Driver | % dos drops acionáveis | Estágio |
|--------|------------------------|---------|
| Fricção em negociação / desalinhamento de preço | ~17 pp | Concentrado OS→OA |
| Barreiras financeiras (recusa de crédito, mismatch de funding, entrada, FGTS) | ~12 pp | OA→CCV (9pp) + pós-CCV (2.5pp) |
| Documentação / problemas legais (hard-blocks de propriedade, pendências, DD) | ~8 pp | OA→CCV (5pp) + pós-CCV (3pp) |

Dos **cancelamentos pós-CCV**: ~37% são causados por recusa de crédito.

### 3.4 Motivos de cancelamento de CCV

`dim_sale_agreement.sale_agreement_cancellation_reason`:
- Buyer Desistiu
- Seller Desistiu
- Reprovado Crédito
- Reprovado Diligência
- Modelo QA
- COVID
- Não se Aplica

### 3.5 Métricas EoF

| Métrica | Status | Fórmula / Fonte | Benchmark | Dashboard |
|---------|--------|-----------------|-----------|-----------|
| `# CCV` | ✅ | `COUNT(DISTINCT sk_offer) WHERE sk_sale_agreement_signed_date > 0` — `fact_offers` | — | [Fibonacci](https://superset.apps.data-prd.habitat.zone/superset/dashboard/2608/?native_filters_key=NCV4qOpFaqbK2BnCnpRNn7Cxw-0yWw-TY6PXZYsIRmvWCNPHjQZaXs-RcTCPWaZh) |
| `CD` | ✅ | `COUNT(DISTINCT sk_offer) WHERE contract_group <> 'Bypass'` — `fact_closing_flows` | — | [Fibonacci](https://superset.apps.data-prd.habitat.zone/superset/dashboard/2608/?native_filters_key=NCV4qOpFaqbK2BnCnpRNn7Cxw-0yWw-TY6PXZYsIRmvWCNPHjQZaXs-RcTCPWaZh) |
| `OS2CCV` | ✅ | `COUNT(ts_sale_agreement_signed IS NOT NULL) / COUNT(ts_offer_submitted IS NOT NULL)` — `fact_offers` | ~40% (BP OS2CD) | — |
| `OS2OA` | ✅ | `COUNT(ts_offer_accepted IS NOT NULL) / COUNT(ts_offer_submitted IS NOT NULL)` — `fact_offers` | ~60% | — |
| `OA2SO` | ✅ | `SUM(Contagem_SO) / SUM(Contagem_oa)` — Dataset 18848 (`fact_offers` + `fact_closing_flows`) | — | [EoF Conv.](https://superset.apps.data-prd.habitat.zone/superset/dashboard/1384/?native_filters_key=9NJo85VO9rON_m4l734v6MuTsFkoQabYATt6vlRV8mCQ9f4ZkRjkDyiiZrfudQKH) |
| `SO2CCVe` | ✅ | `SUM(Contagem_CCVe) / SUM(Contagem_SO)` — Dataset 18848 | — | [EoF Conv.](https://superset.apps.data-prd.habitat.zone/superset/dashboard/1384/?native_filters_key=9NJo85VO9rON_m4l734v6MuTsFkoQabYATt6vlRV8mCQ9f4ZkRjkDyiiZrfudQKH) |
| `CCVe2CCVa` | ✅ | `SUM(Contagem_CCV_Assinado) / SUM(Contagem_CCVe)` — Dataset 18848 | — | [EoF Conv.](https://superset.apps.data-prd.habitat.zone/superset/dashboard/1384/?native_filters_key=9NJo85VO9rON_m4l734v6MuTsFkoQabYATt6vlRV8mCQ9f4ZkRjkDyiiZrfudQKH) |
| `CCV2CD` | ✅ | `SUM(Contagem_Closed_Deals) / SUM(Sale_Agreement)` WHERE `payment_model <> 'CLOSING_3P'` — Dataset 18848 | ~95% | [EoF Conv.](https://superset.apps.data-prd.habitat.zone/superset/dashboard/1384/?native_filters_key=9NJo85VO9rON_m4l734v6MuTsFkoQabYATt6vlRV8mCQ9f4ZkRjkDyiiZrfudQKH) |
| `% Distratos` | ✅ | `COUNT(is_ccv_canceled = TRUE) / COUNT(ts_sale_agreement_signed IS NOT NULL)` — `fact_offers` + `dim_sale_agreement` | — | — |
| `Ticket médio CCV` | ✅ | `AVG(sale_price_agreed) WHERE ts_sale_agreement_signed IS NOT NULL` — `fact_offers` | — | — |
| `Ticket médio CD` | ✅ | `AVG(sale_price_agreed)` — `fact_offers` JOIN `fact_closing_flows` | — | — |
| `% Termo de corretagem` | ✅ | Numerador: CDs com TC; denominador: CCVs — `fact_closing_flows`. Confirmar nome da flag TC. | — | — |
| `LT OS2OA` | ✅ | `AVG(days_offer_submitted_to_offer_accepted)` — coluna pré-computada em `fact_offers` | ~2 dias | — |
| `LT OA2CCV` | ✅ | `AVG(days_offer_accepted_to_sale_agreement_signed)` — coluna pré-computada em `fact_offers` | ~6 dias | [SLA Sheet](https://docs.google.com/spreadsheets/d/1b69z6hkWqhri5FDLwtDWu2EJzJ0RsgMLyy_9qFT_IUs/edit?gid=556290245) |
| `LT OS2CCV` | ✅ | Soma dos dois acima, ou `AVG(ts_sale_agreement_signed - ts_offer_submitted)` | — | — |
| `LT CCV2CD` | ✅ | `AVG(days_sale_agreement_signed_to_legal_analysis_ended)` — `fact_closing_flows` (pré-computado). Filtro: `is_ccv_canceled = FALSE`. Segmentar por `sub_division`. | ~10 dias | [SLA Sheet](https://docs.google.com/spreadsheets/d/1b69z6hkWqhri5FDLwtDWu2EJzJ0RsgMLyy_9qFT_IUs/edit?gid=1745870402) |
| `LT OS2CD` | ✅ | `AVG(DATE_DIFF('day', CAST(fo.ts_offer_submitted AS DATE), dd.date_day))` — `fact_closing_flows` JOIN `fact_offers fo` JOIN `dim_date dd ON fcf.sk_legal_analysis_ended_date = dd.sk_date`. ⚠️ Nunca subtrair `sk_legal_analysis_ended_date` diretamente de `ts_offer_submitted` — `sk_*` é surrogate key inteira, não timestamp. | — | — |
| `LT OA2SO` | ⚠️ | OA → SAC. Aproximar de `fact_offers`. Confirmar se calendário de dias úteis disponível. | — | [SLA Sheet](https://docs.google.com/spreadsheets/d/1b69z6hkWqhri5FDLwtDWu2EJzJ0RsgMLyy_9qFT_IUs/edit?gid=556290245) |
| `LT SO2CCVe` | ⚠️ | SAC → CCV draft. Mesma dependência. | — | [SLA Sheet](https://docs.google.com/spreadsheets/d/1b69z6hkWqhri5FDLwtDWu2EJzJ0RsgMLyy_9qFT_IUs/edit?gid=556290245) |
| `LT CCVe2CCVa` | ⚠️ | CCV draft → CCV assinado. Mesma dependência. | — | [SLA Sheet](https://docs.google.com/spreadsheets/d/1b69z6hkWqhri5FDLwtDWu2EJzJ0RsgMLyy_9qFT_IUs/edit?gid=556290245) |
| `NPS CCV` | ⚠️ | `(promoters - detractors) / total * 100`. Filtro: `metric_group IN ('buyerccv','sellerccv')` — `metric_group` vive em `dim_nps_campaign`, **não** em `dim_nps_answer`. Fonte: `dw_customer_satisfaction.fact_nps_dispatches` + `dim_nps_answer` + `dim_nps_campaign`. | ~75 | — |
| `NPS Buyer lost proposal` | ⚠️ | Mesma fonte NPS. `metric_group = 'buyerlostproposal'`. | ~22 | — |
| `BPOS2BPCCV` | ⚠️ | Coorte M0+M1: buyers com VISIT_BOOKED no mês M com CCV em M ou M+1. Join `fact_sale_demand_event` + `fact_offers`. `fact_buyer_prospects` dá conversão lifetime — não serve para coorte mensal. | — | — |
| `BPOS2BPOA` | ⚠️ | Mesma abordagem de coorte, numerador = OA em M ou M+1. | — | — |
| `BPOA2BPCCV` | ⚠️ | Buyers com VISIT_BOOKED + OA no mês M; numerador = CCV em M ou M+1. | — | — |
| `UC CCV` | ❌ | Fonte de custo não mapeada. Benchmark: ~R$250/CCV. | — | — |
| `UC DD` | ❌ | Fonte de custo não mapeada. Benchmark: ~R$250/DD. | — | — |
| `R$ Bypass Revenue` | ❌ | Conceito "Bypass" não definido. | — | — |

---

## 4. EoP — End of Process

### 4.1 Distribuição de tracks de pagamento (Abr 2026)

Segmentar **sempre** por `dim_sale_agreement.payment_method`. As distribuições de LT e NPS variam drasticamente entre tracks.

| Track | % dos CCVs | Característica |
|-------|-----------|----------------|
| **Mortgage (Financiamento)** | ~70% | Mais longo e complexo; dependente de banco |
| **Cash (À Vista)** | ~30% | Mais simples; dependente de cartório |
| **Consortium (Consórcio)** | ~2% | Operado com parceiro Bamaq |
| **Hybrid** | ~4% | Comprador e vendedor transacionando simultaneamente no QA |

Dentro de Mortgage:
- **Internal Corban** (~14%): correspondente bancário operado pelo QA. Melhor NPS (29,6 vs 36,6) e menor LT (100d vs 127d). Identificar por `franchise_name LIKE '%Quinto Andar%'` via `dw_atta.fact_pre_analysis_proposal_flow`.
- **Partner Corban** (~86%): correspondentes externos.

Dentro de Cash:
- **CRN Parceiro** (~82%): NPS 62,1, LT 75,5d
- **CRN Não-parceiro** (~18%): NPS 2,8, LT 121,9d — gap de 60 pontos de NPS e 46 dias de LT. Sempre sinalizar em análises de Cash.

### 4.2 Etapas comuns a Cash e Mortgage

**Onboarding** — Primeiro touchpoint pós-CCV; handover do EN para o SPOC. Meta Cash: conversão ao CRN parceiro (~89% attach). Meta Mortgage: conversão ao Internal Corban (medida quando o comprador seleciona proposta, não na autorização). Atualmente 100% manual; AI (Vandinha) em rollout para Cash H1 2026.

**Sinal (Earnest Payment)** — ~6% do preço de venda, retido pelo QA. Vendedor não recebe nada neste momento — principal fonte de frustração de vendedores.

**Regularização** — Atualizações de registro e ajustes jurídicos (averbações, fiduciárias, aditivos, distratos). Executado pelo Legal Ops. No Mortgage: cancelamento de fiduciárias existentes deve ocorrer antes da análise jurídica bancária.

### 4.3 Steps específicos por track

**Cash:**
```
CCV Assinado → Onboarding → Sinal → Regularização
→ Escritura (CRN): mais intensivo; escritura, assinaturas, pagamento total, ITBI
  Parceiro CRN: ~40d. Com averbação: +23d.
→ Entrega de Chaves (geralmente no dia da escritura)
→ Registro (CRI): ~25,7d após escritura
```
LT total Cash: parceiro sem averbação ~72d; com averbação ~98d; sem parceiro ~122d.

**Mortgage:**
```
[Análise de Crédito] — frequentemente antes do CCV
  Caixa Econômica Federal = maior volume, sem API de terceiros;
  85% dos compradores aguardam resultado da Caixa antes de avançar.
  LT: ~18d (IC) / ~13d (Parceiros)
→ CCV Assinado
→ Onboarding → Sinal → Regularização
→ Seleção de Banco + Input de Dados: erros aqui reiniciam o processo
→ Vistoria e Análise Jurídica (paralelas): ~80% do LT da etapa de financiamento
→ Contrato de Financiamento + Entrada: IQ, entrevista gerencial, assinatura
  LT etapa financiamento: ~50d (IC) / ~59d (Parceiros)
→ Registro (CRI) + Pagamento pelo banco + Entrega de Chaves
```
LT total Mortgage: IC ~100d; Parceiros ~127d.

**Consortium:** Operado com Bamaq. Revisão docs → Vistoria → Contrato → ITBI + CRI → Bamaq libera fundos em 2 dias úteis → cashback 10% para comprador.

**Hybrid:** ~4% dos CCVs. Processos individuais idênticos aos outros tracks, mas timings de compra e venda precisam ser coordenados.

**ROFR (Direito de Preferência):** Inquilino tem 30 dias para exercer; comprador end-user tem 90 dias de prazo de desocupação (pode adicionar 120+ dias ao EoP). Bloqueado até entrega da matrícula. Casos com inquilino externo fora do controle de ops.

### 4.4 Métricas EoP

#### Lead Time

| Métrica | Status | Fórmula / Fonte | Benchmark | Dashboard |
|---------|--------|-----------------|-----------|-----------|
| `Lead Time Cash + IC` | ✅ | `AVG(days_sale_agreement_signed_to_house_registry_ended)` — `dw_sale.fact_closing_flows`. Filtro: `is_ccv_canceled = FALSE AND sub_division IN ('INTERNAL CORBAN','CASH%')`. Âncora: `sk_house_registry_ended_date`. | Cash+IC consolidado | [DS 16038](https://superset.apps.data-prd.habitat.zone/explore/?datasource_type=table&datasource_id=16038) · [Polygon](https://superset.apps.data-prd.habitat.zone/superset/dashboard/3087/?native_filters_key=qrFlLhJPBrGpXeHbk0hKesRA557cNDVxvqVx1_9vmAeePM1FKeo_63C9BBHu066x) |
| `Lead Time - Cash` | ✅ | Mesma coluna. Filtro: `division = 'CASH' AND is_ccv_canceled = FALSE`. CASH = `payment_method IN ('CASH','CASH_USING_FGTS')`. | ~75,5d (CRN parceiro) / ~121,9d (sem parceiro) | [DS 16038](https://superset.apps.data-prd.habitat.zone/explore/?datasource_type=table&datasource_id=16038) |
| `Lead Time - Internal Corban` | ✅ | Filtro: `sub_division = 'INTERNAL CORBAN' AND is_ccv_canceled = FALSE`. IC = `franchise_name LIKE '%Quinto Andar%'`. | ~100d | [DS 16038](https://superset.apps.data-prd.habitat.zone/explore/?datasource_type=table&datasource_id=16038) |
| `Lead Time - Mortgage w/ Partners` | ✅ | Filtro: `division = 'FINANCED' AND is_ccv_canceled = FALSE`. FINANCED = `payment_method LIKE '%FINANCED%' AND credit_model <> 'EXTERNAL'`. | ~127d | [DS 16038](https://superset.apps.data-prd.habitat.zone/explore/?datasource_type=table&datasource_id=16038) |
| `Lead Time - Cash w/ CRN Partner` | ❌ | Dados de CRN ainda não incluídos no dataset. | — | — |
| `Lead Time - Cash wo/ CRN Partner` | ❌ | Idem. | — | — |

#### NPS EoP

Fonte confirmada: `dw_customer_satisfaction.fact_nps_dispatches` + `dim_nps_answer` + `dim_nps_campaign`. Fórmula: `(COUNT(DISTINCT CASE WHEN score_category = 'promoter' THEN sk_nps_answer END) - COUNT(DISTINCT CASE WHEN score_category = 'detractor' THEN sk_nps_answer END)) / NULLIF(COUNT(DISTINCT sk_nps_answer), 0) * 100`. Filtro de escopo: `dim_nps_campaign.metric_group IN ('buyerendofprocess','sellerendofprocess')` — `metric_group` vive em `dim_nps_campaign`, **não** em `dim_nps_answer`. `is_answered` vive em `fact_nps_dispatches`. Segmentação de payment_method requer LEFT JOIN `dim_sale_agreement` via `disp.sk_offer` (JOIN direto — `fact_offers` não é necessário). Segmentação CRN: `seguiu_com_cart_parceiro`. Segmentação IC: `franchise_name` de `dw_atta.fact_pre_analysis_proposal_flow`.

| Métrica | Status | Filtro | Benchmark | Dashboard |
|---------|--------|--------|-----------|-----------|
| `NPS Cash + IC` | ✅ | `payment_method IN ('Internal Corban','Cash')` | ~45 (total EoP) | [DS 18337](https://superset.apps.data-prd.habitat.zone/explore/?datasource_type=table&datasource_id=18337) · [Polygon](https://superset.apps.data-prd.habitat.zone/superset/dashboard/3087/?native_filters_key=qrFlLhJPBrGpXeHbk0hKesRA557cNDVxvqVx1_9vmAeePM1FKeo_63C9BBHu066x) |
| `NPS - Cash` | ✅ | `payment_method IN ('Cash')` | 54,1 | [DS 18337](https://superset.apps.data-prd.habitat.zone/explore/?datasource_type=table&datasource_id=18337) |
| `NPS - Cash w/ CRN Parceiro` | ✅ | + `seguiu_com_cart_parceiro = 'Sim'` | 62,1 | [DS 18337](https://superset.apps.data-prd.habitat.zone/explore/?datasource_type=table&datasource_id=18337) |
| `NPS - Cash wo/ CRN Parceiro` | ✅ | + `seguiu_com_cart_parceiro <> 'Sim'` | 2,8 | [DS 18337](https://superset.apps.data-prd.habitat.zone/explore/?datasource_type=table&datasource_id=18337) |
| `NPS - Internal Corban` | ✅ | `payment_method IN ('Internal Corban')` | 29,6 | [DS 18337](https://superset.apps.data-prd.habitat.zone/explore/?datasource_type=table&datasource_id=18337) |
| `NPS - Mortgage w/ Partners` | ✅ | `payment_method IN ('Financed Internal')` | 36,6 | [DS 18337](https://superset.apps.data-prd.habitat.zone/explore/?datasource_type=table&datasource_id=18337) |

#### DSAT e Resolution Rate

Fonte confirmada: Dataset 18277 (`dw_atta` schema). Colunas: `csat_score`, `resolution`, `id_response`, `response_date`, `payment_method`, `seguiu_com_cart_parceiro`. Fórmulas:
- **DSAT:** `COUNT(CASE WHEN csat_score IN (1,2) THEN 1 END) / NULLIF(CAST(COUNT(csat_score) AS DOUBLE), 0)`
- **Resolution Rate:** `COUNT(CASE WHEN resolution = 1 THEN 1 END) / NULLIF(CAST(COUNT(id_response) AS DOUBLE), 0)`

| Métrica | Status | Filtro principal | Dashboard |
|---------|--------|-----------------|-----------|
| `DSAT - Cash` | ✅ | `payment_method = 'Cash'` | [DS 18277](https://superset.apps.data-prd.habitat.zone/explore/?datasource_type=table&datasource_id=18277) · [Polygon](https://superset.apps.data-prd.habitat.zone/superset/dashboard/3087/?native_filters_key=qrFlLhJPBrGpXeHbk0hKesRA557cNDVxvqVx1_9vmAeePM1FKeo_63C9BBHu066x) |
| `DSAT - Cash w/ CRN Parceiro` | ✅ | + `seguiu_com_cart_parceiro = 'Sim'` | [DS 18277](https://superset.apps.data-prd.habitat.zone/explore/?datasource_type=table&datasource_id=18277) |
| `DSAT - Cash wo/ CRN Parceiro` | ✅ | + `seguiu_com_cart_parceiro <> 'Sim'` | [DS 18277](https://superset.apps.data-prd.habitat.zone/explore/?datasource_type=table&datasource_id=18277) |
| `DSAT - Internal Corban` | ✅ | `payment_method = 'Internal Corban'` | [DS 18277](https://superset.apps.data-prd.habitat.zone/explore/?datasource_type=table&datasource_id=18277) |
| `DSAT - Mortgage w/ Partners` | ✅ | `payment_method = 'Financed Internal'` | [DS 18277](https://superset.apps.data-prd.habitat.zone/explore/?datasource_type=table&datasource_id=18277) |
| `DSAT - Cash AI` | ❌ | Dataset "wip" — lógica de identificação de casos AI não criada. | — |
| `Resolution Rate - Cash` | ✅ | `payment_method = 'Cash'` | [DS 18277](https://superset.apps.data-prd.habitat.zone/explore/?datasource_type=table&datasource_id=18277) |
| `Resolution Rate - IC` | ✅ | `payment_method = 'Internal Corban'` | [DS 18277](https://superset.apps.data-prd.habitat.zone/explore/?datasource_type=table&datasource_id=18277) |
| `Resolution Rate - Mortgage w/ Partners` | ✅ | `payment_method = 'Financed Internal'` | [DS 18277](https://superset.apps.data-prd.habitat.zone/explore/?datasource_type=table&datasource_id=18277) |

#### Attach Rate e Share IC

Fonte: Dataset 18841 (`dw_sale.fact_offers` + `dw_sale.dim_sale_agreement` + `dw_atta.fact_pre_analysis_proposal_flow` + `dw_atta.dim_franchise_atta`). Internal Corban = `franchise_name LIKE '%Quinto Andar%'`.

| Métrica | Status | Fórmula | Dashboard |
|---------|--------|---------|-----------|
| `Attach Rate - IC` | ✅ | `SUM(CASE WHEN IS_INTERNAL_CORBAN=1 THEN IS_INTERNAL_FINANCED END) / NULLIF(SUM(CASE WHEN IS_INTERNAL_CORBAN=1 THEN IS_FINANCED END), 0)` | [DS 18841](https://superset.apps.data-prd.habitat.zone/explore/?datasource_type=table&datasource_id=18841) |
| `Attach Rate - Mortgage` | ✅ | `SUM(IS_INTERNAL_FINANCED) / NULLIF(SUM(IS_FINANCED), 0)` (sem filtro por IC) | [DS 18841](https://superset.apps.data-prd.habitat.zone/explore/?datasource_type=table&datasource_id=18841) |
| `Attach Rate - Mortgage w/ Partners` | ✅ | `SUM(CASE WHEN IS_INTERNAL_CORBAN=0 THEN IS_INTERNAL_FINANCED END) / NULLIF(SUM(CASE WHEN IS_INTERNAL_CORBAN=0 THEN IS_FINANCED END), 0)` | [DS 18841](https://superset.apps.data-prd.habitat.zone/explore/?datasource_type=table&datasource_id=18841) |
| `Share Routed to IC` | ✅ | `COUNT(DISTINCT CASE WHEN franchise_name LIKE '%Quinto Andar%' AND contagem_ticket_IC > 0 THEN id_offer END) / NULLIF(COUNT(DISTINCT id_offer), 0)`. Filtros: `payment_model = 'CCV_ASSISTANCE' AND ccv_model = 'Is a 5A model' AND payment_method LIKE '%FINANCED%' AND sub_division <> 'CONSORTIUM'`. Fonte: Dataset 19155 (`datalake_sale_closing_flows.closing_flow`). | [DS 18647](https://superset.apps.data-prd.habitat.zone/explore/?datasource_type=table&datasource_id=18647) |

---

## 5. Buyer Prospect

### 5.1 Definição e fonte correta

**Buyer Prospect (BP)** = comprador com visita agendada (VISIT_BOOKED) em For Sale.

**Fonte correta: `dw_sale.fact_sale_demand_event` + `dw_sale.dim_sale_event_type`**

```sql
-- # Buyer Prospect mensal (1P, excluindo 3P)
SELECT
    DATE_FORMAT(dd.month_start, '%Y-%m')   AS month,
    COUNT(DISTINCT fde.sk_buyer)            AS buyer_prospects
FROM dw_sale.fact_sale_demand_event AS fde
JOIN dw_sale.dim_sale_event_type    AS det ON fde.sk_event_type = det.sk_event_type
JOIN dw_public.dim_date             AS dd  ON fde.sk_event_date = dd.sk_date
WHERE det.event_name      = 'VISIT_BOOKED'
  AND fde.is_3p_demand    = false
  AND fde.is_3p_supply    = false
GROUP BY 1
ORDER BY 1
```

Validação: ~90% de aderência ao Fibonacci (26,8k vs 29,8k — Mar/26, 5 cidades). Gap residual de ~10% por diferença de janela de ativação do prospect.

> ⚠️ **`fact_buyer_prospects` NÃO é a fonte correta para `# BP`** — captura apenas o primeiro agendamento histórico do buyer (~50% do total). É útil somente para análises de jornada lifetime por buyer.

### 5.2 Tipos de BP

| Tipo | Descrição | Share |
|------|-----------|-------|
| **NBP** (New Buyer Prospect) | Primeira visita ever do buyer na plataforma | ~70% do BP mensal |
| **RBP** (Recovery Buyer Prospect) | Buyer retornando após período de inatividade | ~30% do BP mensal |

Segmentar via `dim_buyer_prospect_type` (join de `fact_sale_demand_event.sk_buyer_prospect_type`). A dimensão é time-windowed: `ts_activation` → `ts_activation_end`.

Fibonacci (Mar/26, 5 cidades): NBP = 20.715, RBP = 9.138, Total = 29.853.

### 5.3 Event names disponíveis em `dim_sale_event_type`

| sk_event_type | event_name |
|---------------|-----------|
| 1 | VISIT_BOOKED |
| 2 | VISIT_COMPLETED |
| 3 | OFFER_SUBMITTED |
| 4 | OFFER_ACCEPTED |
| 5 | SALE_AGREEMENT_CREATED |
| 6 | SALE_AGREEMENT_SIGNED |
| 7 | VISIT_CANCELLED |
| 8 | OFFER_REJECTED |

### 5.4 Métricas de BP

| Métrica | Status | Notas |
|---------|--------|-------|
| `# Buyer Prospect` | ✅ | `COUNT(DISTINCT sk_buyer) WHERE event_name = 'VISIT_BOOKED' AND 1P`. ~90% vs Fibonacci. |
| `BP2CCV` | ⚠️ | Fonte oficial: `sandbox.summary_table` (SQL não disponível). DW: join `fact_sale_demand_event` (VISIT_BOOKED mês M, 1P) + `fact_offers` (CCV em M ou M+1) — coorte M0+M1. `fact_buyer_prospects.sale_agreements_signed` = lifetime, não serve. |
| `BPOS2BPCCV` | ⚠️ | Mesma lógica de coorte. Buyers com VISIT_BOOKED no mês M; numerador = CCV em M ou M+1. |
| `BPOS2BPOA` | ⚠️ | Idem. Numerador = OA em M ou M+1. |
| `BPOA2BPCCV` | ⚠️ | Buyers com VISIT_BOOKED + OA em M; numerador = CCV em M ou M+1. |
| `HT BP2CCV` | ❌ | HT = High Ticket. Definido nas tabelas `datalake_buyer_prospect`. Fonte não mapeada no DW central. |

---

## 6. Data Model

### 6.1 Tabelas principais

| Tabela | Schema | Grain | Uso |
|--------|--------|-------|-----|
| `fact_offers` | `dw_sale` | 1 linha por oferta | Todos os eventos EoF (timestamps), brokerage_fee, sale_price_agreed, flags 3P |
| `dim_offer` | `dw_sale` | 1 linha por oferta | offer_status (17 estados), drop_reason, drop_reason_responsible, offer_flow, is_a_rescued_offer, **`tags_from_salesflow`** (filtros de fluxo legado Casa Mineira — esta coluna vive **aqui**, não em `dim_sale_agreement`) |
| `dim_sale_agreement` | `dw_sale` | 1 linha por oferta que chegou à etapa de acordo | Atributos do CCV: payment_method, credit_model, is_ccv_canceled, cancellation_reason, *_dilligence_status, payment_model (filtro 1P) |
| `fact_closing_flows` | `dw_sale` | 1 linha por closing flow | **Fonte primária do EoP.** Evento CD (`sk_legal_analysis_ended_date`), todos os lead times pré-computados, datas de etapas EoP |
| `fact_sale_demand_event` | `dw_sale` | 1 linha por evento por buyer | **Fonte correta para # BP.** Filtrar `event_name = 'VISIT_BOOKED'`, `is_3p_demand = false` |
| `dim_sale_event_type` | `dw_sale` | Referência | event_name catalog (8 tipos). Join via `sk_event_type`. |
| `dim_buyer_prospect_type` | `dw_sale` | Dimensão BP | NBP / RBP, city_group, price_segment. Time-windowed via `ts_activation`/`ts_activation_end`. |
| `fact_buyer_prospects` | `dw_sale` | 1 linha por buyer | OBT lifetime por buyer. Colunas: `offers_submitted`, `offers_accepted`, `sale_agreements_signed`, `days_*` pré-computados. ⚠️ NÃO usar para `# BP`. |
| `fact_visits` | `dw_sale` | 1 linha por visita | Bridge via `sk_booking` (1:N com `fact_offers`). ⚠️ `fact_visits.sk_offer` = apenas primeira oferta por booking — não usar para enumerar ofertas. |
| `fact_pre_analysis_proposal_flow` | `dw_atta` | 1 linha por proposta (join: `sk_offer`) | Identificação de Internal Corban: `franchise_name LIKE '%Quinto Andar%'`. Usar registro mais recente: `ROW_NUMBER() OVER (PARTITION BY sk_offer ORDER BY ts_last_updated DESC) = 1`. |
| `dim_franchise_atta` | `dw_atta` | Dimensão de franquia | Join via `sk_franchise` a partir de `fact_pre_analysis_proposal_flow`. |
| `fact_nps_dispatches` | `dw_customer_satisfaction` | 1 linha por disparo NPS | Join `dim_nps_answer` via `sk_nps_answer`. Colunas-chave: `sk_offer`, `sk_nps_campaign`. |
| `dim_nps_answer` | `dw_customer_satisfaction` | 1 linha por resposta NPS | `score_category` (promoter/detractor/neutral), `ts_answered`, `is_answered`, `metric_group`. |
| `fact_closing_offer_partners` | `dw_sale` | Partner attribution | Usado no dataset de Attach Rate (18841). |
| `dim_region` | `dw_public` | Dimensão de região | neighborhood, city, UF. Join via `sk_region`. |
| `dim_date` | `dw_public` | Dimensão de data | `sk_date`, `month_start`, `year`. Para recortes temporais EoP, fazer join pela `sk_*` da etapa de interesse (ex.: CRI → `sk_house_registry_ended_date = dd.sk_date`) e filtrar `dd.year`. |
| `fact_tickets` | `dw_customer_support` | Tickets Zendesk | Join via `sk_sale_offer`. `group_name` = queue (classifica divisão). |
| `dim_ticket` | `dw_customer_support` | Atributos de ticket | `group_name`, `subject`. |
| `closing_flow` | `datalake_sale_closing_flows` | Raw EoP (camada datalake) | Preferir `dw_sale.fact_closing_flows` para análises DW. |

> ⚠️ `dim_sale_agreement` só tem linhas para ofertas que **chegaram à etapa de acordo**. Sempre LEFT JOIN a partir de `fact_offers`.

### 6.2 Colunas-chave em `fact_offers`

| Coluna | Tipo | Descrição |
|--------|------|-----------|
| `ts_offer_submitted` | timestamp | Evento OS |
| `ts_offer_accepted` | timestamp | Evento OA |
| `ts_offer_dismissed` | timestamp | Evento OR |
| `ts_offer_canceled` | timestamp | Cancelamento de oferta |
| `ts_sale_agreement_drafted` | timestamp | CCVe |
| `ts_sale_agreement_created` | timestamp | Evento SAC |
| `ts_sale_agreement_signed` | timestamp | **CCV — marco comercial** |
| `ts_sale_agreement_canceled` | timestamp | Cancelamento pós-assinatura |
| `brokerage_fee` | numeric | Honorário de corretagem |
| `sale_price_agreed` | numeric | Preço acordado de venda |
| `days_offer_submitted_to_offer_accepted` | integer | LT OS→OA pré-computado |
| `days_offer_accepted_to_sale_agreement_signed` | integer | LT OA→CCV pré-computado |
| `is_buyer_first_offer` | boolean | Primeira oferta do comprador |
| `is_house_first_offer` | boolean | Primeira oferta do imóvel |
| `has_completed_visit_before_offer` | boolean | Visitou antes de ofertar |
| `is_3p_demand` / `is_3p_lead_gen` / `is_3p_supply` | boolean | Flags de atribuição 3P |
| `sk_buyer` | bigint | FK → `dw_public.dim_user` |
| `sk_house` | bigint | FK → `dw_house.dim_house` |
| `sk_booking` | bigint | FK → `dw_sale.fact_visits` |
| `sk_broker_demand` | bigint | Corretor que trouxe o comprador. Ver `broker_xp.md`. |
| `sk_broker_supply` | bigint | Corretor dono do listing. Ver `broker_xp.md`. |
| `sk_region` | bigint | FK → `dw_public.dim_region` |
| `sk_closing_specialist` | bigint | EN — filtrar `<> -1` para atribuídos |

### 6.3 Colunas pré-computadas em `fact_closing_flows`

Usá-las evita cálculos manuais de diferença de datas:

| Coluna | Significado |
|--------|-------------|
| `sk_legal_analysis_ended_date` | **Evento CD** — data em que o Closed Deal foi atingido (DD + TC). Âncora primária para a métrica CD. |
| `sk_house_registry_ended_date` | Data do CRI (transferência de propriedade). Âncora primária para LT EoP. |
| `sk_sale_agreement_signed_date` | Data de assinatura do CCV. |
| `sk_credit_analysis_ended_date` | Data de aprovação de crédito. |
| `sk_financing_ended_date` | Data de assinatura do contrato de financiamento. |
| `days_sale_agreement_signed_to_house_registry_ended` | **LT CCV→CRI** (LT total do EoP). Pré-computado em dias. |
| `days_sale_agreement_signed_to_credit_analysis_ended` | LT CCV→Crédito aprovado. |
| `days_credit_analysis_ended_to_financing_started` | LT entre aprovação de crédito e início do financiamento. |
| `days_financing_started_to_financing_ended` | LT da etapa de financiamento. |
| `days_financing_ended_to_house_registry_ended` | LT de fim do financiamento ao CRI. |
| `days_sale_agreement_signed_to_legal_analysis_ended` | LT CCV→CD. |

### 6.4 Joins canônicos

```sql
-- Base padrão para análises EoF/EoP (1P)
-- ⚠️ tags_from_salesflow vive em dim_offer (NÃO em dim_sale_agreement).
FROM dw_sale.fact_offers fo
LEFT JOIN dw_sale.dim_offer             do  ON fo.sk_offer   = do.sk_offer
LEFT JOIN dw_sale.dim_sale_agreement    dsa ON fo.sk_offer   = dsa.sk_offer
WHERE fo.ts_offer_submitted IS NOT NULL
  AND (dsa.sk_offer IS NULL
       OR (dsa.payment_model <> 'CLOSING_3P'
           AND COALESCE(do.tags_from_salesflow, '') NOT LIKE '%#fluxo-cm%'
           AND COALESCE(do.tags_from_salesflow, '') NOT LIKE '%#casa-mineira%'
           AND COALESCE(do.tags_from_salesflow, '') NOT LIKE '%#fluxo_cm%'))

-- Closed Deals (métrica do time Financeiro)
FROM dw_sale.fact_closing_flows fcf
LEFT JOIN dw_sale.fact_offers fo ON fcf.sk_offer = fo.sk_offer

-- Internal Corban (identificação de franquia)
-- ⚠️ ROW_NUMBER() NÃO pode ir no ON nem no WHERE em Trino/Spark — isolar num CTE.
WITH ic_latest AS (
    SELECT
        fpp.sk_offer,
        dfr.franchise_name,
        ROW_NUMBER() OVER (PARTITION BY fpp.sk_offer
                           ORDER BY fpp.ts_last_updated DESC) AS rn
    FROM dw_atta.fact_pre_analysis_proposal_flow fpp
    LEFT JOIN dw_atta.dim_franchise_atta dfr ON fpp.sk_franchise = dfr.sk_franchise
)
SELECT ...
FROM dw_sale.fact_offers fo
LEFT JOIN ic_latest ic ON fo.sk_offer = ic.sk_offer AND ic.rn = 1
-- Internal Corban: ic.franchise_name LIKE '%Quinto Andar%'

-- NPS EoP
-- metric_group vive em dim_nps_campaign (não em dim_nps_answer); is_answered em fact_nps_dispatches.
-- fact_offers não é necessário — dim_sale_agreement pode ser joinada diretamente via disp.sk_offer.
FROM dw_customer_satisfaction.fact_nps_dispatches disp
JOIN dw_customer_satisfaction.dim_nps_answer       ans  ON disp.sk_nps_answer   = ans.sk_nps_answer
JOIN dw_customer_satisfaction.dim_nps_campaign     dnc  ON disp.sk_nps_campaign = dnc.sk_nps_campaign
LEFT JOIN dw_sale.dim_sale_agreement                dsa  ON disp.sk_offer        = dsa.sk_offer
WHERE disp.is_answered = true
  AND dnc.metric_group IN ('buyerendofprocess','sellerendofprocess')

-- # Buyer Prospect (1P)
FROM dw_sale.fact_sale_demand_event fde
JOIN dw_sale.dim_sale_event_type    det ON fde.sk_event_type = det.sk_event_type
JOIN dw_public.dim_date             dd  ON fde.sk_event_date = dd.sk_date
WHERE det.event_name   = 'VISIT_BOOKED'
  AND fde.is_3p_demand = false
  AND fde.is_3p_supply = false
```

---

## 7. Filtros Obrigatórios (1P)

Aplicar **sempre** ao consultar dados EoF ou EoP para restringir a transações 1P válidas:

```sql
-- payment_model + is_ccv_canceled vivem em dw_sale.dim_sale_agreement (dsa)
-- tags_from_salesflow vive em dw_sale.dim_offer (do) — NÃO em dim_sale_agreement
WHERE dsa.payment_model <> 'CLOSING_3P'                          -- exclui transações 3P/Marketplace
  AND COALESCE(do.tags_from_salesflow, '') NOT LIKE '%#fluxo-cm%'    -- exclui fluxo legado Casa Mineira
  AND COALESCE(do.tags_from_salesflow, '') NOT LIKE '%#casa-mineira%'
  AND COALESCE(do.tags_from_salesflow, '') NOT LIKE '%#fluxo_cm%'
```

**Por quê:**
- `CLOSING_3P` = transações Marketplace. Funil, atores e dados completamente diferentes. Nunca incluir em análises 1P.
- Tags legadas = tipos de fechamento Casa Mineira que não estão mais ativos. Distorcem conversão, LT e custos.
- `tags_from_salesflow` exige `JOIN dw_sale.dim_offer` — a coluna **não** existe em `dim_sale_agreement` (Trino retorna `COLUMN_NOT_FOUND`). O `COALESCE` evita que ofertas sem tag sejam descartadas pelo `NOT LIKE`.

**Base completa para funil EoF (com preservação de ofertas que não chegaram ao acordo):**
```sql
FROM dw_sale.fact_offers fo
LEFT JOIN dw_sale.dim_offer          do  ON fo.sk_offer = do.sk_offer
LEFT JOIN dw_sale.dim_sale_agreement dsa ON fo.sk_offer = dsa.sk_offer
WHERE fo.ts_offer_submitted IS NOT NULL
  AND (dsa.sk_offer IS NULL
       OR (    dsa.payment_model <> 'CLOSING_3P'
           AND COALESCE(do.tags_from_salesflow, '') NOT LIKE '%#fluxo-cm%'
           AND COALESCE(do.tags_from_salesflow, '') NOT LIKE '%#casa-mineira%'
           AND COALESCE(do.tags_from_salesflow, '') NOT LIKE '%#fluxo_cm%'))
```

**Lógica de division / sub_division** (usada em datasets 16038, 19155, 18841):
```sql
-- division
CASE
  WHEN payment_method IN ('CASH','CASH_USING_FGTS')                   THEN 'CASH'
  WHEN payment_method LIKE '%FINANCED%' AND credit_model = 'EXTERNAL' THEN 'FINANCED W/O PARTNER'
  ELSE 'FINANCED'
END AS division

-- sub_division (requer join com dw_atta.fact_pre_analysis_proposal_flow)
CASE
  WHEN franchise_name LIKE '%Quinto Andar%'                            THEN 'INTERNAL CORBAN'
  WHEN payment_method = 'CASH_USING_FGTS'                             THEN 'CASH W/ FGTS'
  WHEN payment_method = 'CASH'                                         THEN 'CASH W/O FGTS'
  WHEN payment_method LIKE '%FINANCED%' AND credit_model = 'EXTERNAL' THEN 'EXTERNAL FINANCING'
  ELSE 'INTERNAL FINANCING'
END AS sub_division
```

---

## 8. SQL Templates (Análises Comuns)

### Funil EoF de conversão por mês
```sql
SELECT
    DATE_TRUNC('month', fo.ts_offer_submitted)                                      AS month_os,
    COUNT(*)                                                                          AS offers_submitted,
    COUNT(*) FILTER (WHERE fo.ts_offer_accepted IS NOT NULL)                          AS offers_accepted,
    COUNT(*) FILTER (WHERE fo.ts_sale_agreement_signed IS NOT NULL)                   AS ccv_signed,
    ROUND(CAST(COUNT(*) FILTER (WHERE fo.ts_offer_accepted IS NOT NULL) AS DOUBLE)
          / NULLIF(COUNT(*), 0) * 100, 1)                                             AS os2oa_pct,
    ROUND(CAST(COUNT(*) FILTER (WHERE fo.ts_sale_agreement_signed IS NOT NULL) AS DOUBLE)
          / NULLIF(COUNT(*) FILTER (WHERE fo.ts_offer_accepted IS NOT NULL), 0) * 100, 1) AS oa2ccv_pct
FROM dw_sale.fact_offers fo
LEFT JOIN dw_sale.dim_offer          do  ON fo.sk_offer = do.sk_offer
LEFT JOIN dw_sale.dim_sale_agreement dsa ON fo.sk_offer = dsa.sk_offer
WHERE fo.ts_offer_submitted IS NOT NULL
  AND (dsa.sk_offer IS NULL
       OR (dsa.payment_model <> 'CLOSING_3P'
           AND COALESCE(do.tags_from_salesflow, '') NOT LIKE '%#fluxo-cm%'
           AND COALESCE(do.tags_from_salesflow, '') NOT LIKE '%#casa-mineira%'
           AND COALESCE(do.tags_from_salesflow, '') NOT LIKE '%#fluxo_cm%'))
GROUP BY 1 ORDER BY 1
```

### Closed Deals por mês (métrica financeira)
```sql
-- Fonte primária
-- ⚠️ ETL usa -1 como sentinel para datas ausentes; IS NOT NULL não exclui esses registros.
-- ⚠️ Aplicar filtros 1P (payment_model + tags Casa Mineira) conforme §7.
SELECT DATE_TRUNC('month', CAST(dd.date_day AS DATE)) AS month_cd,
       COUNT(*)                                         AS closed_deals
FROM dw_sale.fact_closing_flows fcf
JOIN dw_public.dim_date         dd  ON fcf.sk_legal_analysis_ended_date = dd.sk_date
LEFT JOIN dw_sale.dim_sale_agreement dsa ON fcf.sk_offer = dsa.sk_offer
LEFT JOIN dw_sale.dim_offer          do  ON fcf.sk_offer = do.sk_offer
WHERE fcf.sk_legal_analysis_ended_date > 0
  AND fcf.contract_group <> 'Bypass'
  AND dsa.payment_model <> 'CLOSING_3P'
  AND COALESCE(do.tags_from_salesflow, '') NOT LIKE '%#fluxo-cm%'
  AND COALESCE(do.tags_from_salesflow, '') NOT LIKE '%#casa-mineira%'
  AND COALESCE(do.tags_from_salesflow, '') NOT LIKE '%#fluxo_cm%'
GROUP BY 1 ORDER BY 1
-- Se números não baterem com o Financeiro: verificar também datalake_gsheets_clean.closed_deals
```

### Lead Time EoP por track
```sql
-- Internal Corban precisa do registro mais recente por oferta: isolar num CTE
-- (ROW_NUMBER() não pode aparecer no ON/WHERE em Trino/Spark).
WITH ic_latest AS (
    SELECT
        fpp.sk_offer,
        dfr.franchise_name,
        ROW_NUMBER() OVER (PARTITION BY fpp.sk_offer
                           ORDER BY fpp.ts_last_updated DESC) AS rn
    FROM dw_atta.fact_pre_analysis_proposal_flow fpp
    LEFT JOIN dw_atta.dim_franchise_atta dfr ON fpp.sk_franchise = dfr.sk_franchise
)
SELECT
    CASE WHEN dsa.payment_method IN ('CASH','CASH_USING_FGTS')        THEN 'CASH'
         WHEN ic.franchise_name LIKE '%Quinto Andar%'                  THEN 'INTERNAL CORBAN'
         ELSE 'FINANCED W/ PARTNER'
    END                                                                  AS track,
    AVG(fcf.days_sale_agreement_signed_to_house_registry_ended)          AS avg_lt_days,
    COUNT(*)                                                              AS ccv_count
FROM dw_sale.fact_closing_flows fcf
JOIN dw_sale.dim_sale_agreement dsa ON fcf.sk_offer = dsa.sk_offer
LEFT JOIN dw_sale.dim_offer         do  ON fcf.sk_offer = do.sk_offer
LEFT JOIN ic_latest                 ic  ON fcf.sk_offer = ic.sk_offer AND ic.rn = 1
WHERE fcf.sk_house_registry_ended_date IS NOT NULL
  AND dsa.is_ccv_canceled = false
  AND dsa.payment_model <> 'CLOSING_3P'
  AND COALESCE(do.tags_from_salesflow, '') NOT LIKE '%#fluxo-cm%'
  AND COALESCE(do.tags_from_salesflow, '') NOT LIKE '%#casa-mineira%'
  AND COALESCE(do.tags_from_salesflow, '') NOT LIKE '%#fluxo_cm%'
GROUP BY 1 ORDER BY 2
```

### # Buyer Prospect por mês (NBP vs RBP)
```sql
SELECT
    DATE_FORMAT(dd.month_start, '%Y-%m')                           AS month,
    dbpt.buyer_prospect_type,
    COUNT(DISTINCT fde.sk_buyer)                                    AS buyer_prospects
FROM dw_sale.fact_sale_demand_event fde
JOIN dw_sale.dim_sale_event_type    det  ON fde.sk_event_type          = det.sk_event_type
JOIN dw_public.dim_date             dd   ON fde.sk_event_date          = dd.sk_date
JOIN dw_sale.dim_buyer_prospect_type dbpt ON fde.sk_buyer_prospect_type = dbpt.sk_buyer_prospect_type
WHERE det.event_name   = 'VISIT_BOOKED'
  AND fde.is_3p_demand = false
  AND fde.is_3p_supply = false
GROUP BY 1, 2 ORDER BY 1, 2
```

### NPS EoP por payment track
```sql
-- Deduplicar a proposta do Internal Corban por oferta via CTE (evita fan-out no NPS).
-- is_answered vive em fact_nps_dispatches; metric_group vive em dim_nps_campaign.
-- fact_offers não é necessário — dim_sale_agreement é joinada diretamente via disp.sk_offer.
WITH ic_latest AS (
    SELECT
        fpp.sk_offer,
        dfr.franchise_name,
        ROW_NUMBER() OVER (PARTITION BY fpp.sk_offer
                           ORDER BY fpp.ts_last_updated DESC) AS rn
    FROM dw_atta.fact_pre_analysis_proposal_flow fpp
    LEFT JOIN dw_atta.dim_franchise_atta dfr ON fpp.sk_franchise = dfr.sk_franchise
)
SELECT
    DATE_TRUNC('month', ans.ts_answered)                                               AS month,
    CASE WHEN dsa.payment_method IN ('CASH','CASH_USING_FGTS') THEN 'Cash'
         WHEN ic.franchise_name LIKE '%Quinto Andar%'           THEN 'Internal Corban'
         ELSE 'Financed w/ Partner'
    END                                                                                  AS track,
    ROUND((COUNT(DISTINCT CASE WHEN ans.score_category = 'promoter'  THEN ans.sk_nps_answer END)
         - COUNT(DISTINCT CASE WHEN ans.score_category = 'detractor' THEN ans.sk_nps_answer END))
        * 100.0 / NULLIF(COUNT(DISTINCT ans.sk_nps_answer), 0), 1)                    AS nps
FROM dw_customer_satisfaction.dim_nps_answer       ans
JOIN dw_customer_satisfaction.fact_nps_dispatches  disp ON disp.sk_nps_answer   = ans.sk_nps_answer
JOIN dw_customer_satisfaction.dim_nps_campaign     dnc  ON disp.sk_nps_campaign = dnc.sk_nps_campaign
LEFT JOIN dw_sale.dim_sale_agreement                dsa  ON disp.sk_offer        = dsa.sk_offer
LEFT JOIN ic_latest                                 ic   ON disp.sk_offer        = ic.sk_offer AND ic.rn = 1
WHERE disp.is_answered    = true
  AND dnc.metric_group   IN ('buyerendofprocess','sellerendofprocess')
GROUP BY 1, 2 ORDER BY 1, 2
```

### Motivos de cancelamento de CCV
```sql
SELECT
    dsa.sale_agreement_cancellation_reason,
    COUNT(*)                               AS ccvs_cancelados
FROM dw_sale.fact_offers fo
JOIN dw_sale.dim_sale_agreement dsa ON fo.sk_offer = dsa.sk_offer
LEFT JOIN dw_sale.dim_offer         do  ON fo.sk_offer = do.sk_offer
WHERE dsa.is_ccv_canceled = true
  AND dsa.payment_model <> 'CLOSING_3P'
  AND COALESCE(do.tags_from_salesflow, '') NOT LIKE '%#fluxo-cm%'
  AND COALESCE(do.tags_from_salesflow, '') NOT LIKE '%#casa-mineira%'
  AND COALESCE(do.tags_from_salesflow, '') NOT LIKE '%#fluxo_cm%'
GROUP BY 1 ORDER BY 2 DESC
```

### Performance por corretor de demanda
```sql
SELECT
    fo.sk_broker_demand,
    COUNT(*)                                                                   AS offers_submitted,
    COUNT(*) FILTER (WHERE fo.ts_sale_agreement_signed IS NOT NULL)            AS ccv_signed,
    ROUND(CAST(COUNT(*) FILTER (WHERE fo.ts_sale_agreement_signed IS NOT NULL) AS DOUBLE)
          / NULLIF(COUNT(*), 0) * 100, 1)                                      AS os2ccv_pct
FROM dw_sale.fact_offers fo
LEFT JOIN dw_sale.dim_offer          do  ON fo.sk_offer = do.sk_offer
LEFT JOIN dw_sale.dim_sale_agreement dsa ON fo.sk_offer = dsa.sk_offer
WHERE fo.sk_broker_demand <> -1
  AND fo.ts_offer_submitted IS NOT NULL
  AND (dsa.sk_offer IS NULL
       OR (dsa.payment_model <> 'CLOSING_3P'
           AND COALESCE(do.tags_from_salesflow, '') NOT LIKE '%#fluxo-cm%'
           AND COALESCE(do.tags_from_salesflow, '') NOT LIKE '%#casa-mineira%'
           AND COALESCE(do.tags_from_salesflow, '') NOT LIKE '%#fluxo_cm%'))
GROUP BY 1 ORDER BY 2 DESC
```

---

## 9. Benchmarks de Referência (Abr 2026)

Usar para validar outputs de queries e identificar anomalias.

### EoF

| Métrica | Benchmark |
|---------|-----------|
| BP OS2CD | ~40% |
| OS2OA | ~60% |
| OA2CCV | ~70% |
| CCV2CD | ~95% |
| LT OS→OA | ~2 dias |
| LT OA→CCV | ~6 dias |
| LT CCV→CD | ~10 dias |
| NPS CCV | ~75 |
| NPS Lost Proposal | ~22 |
| Unit cost CCV drafting | ~R$250/CCV (37 analistas, ~R$500k/mês) |
| Unit cost Due Diligence | ~R$250/DD (49 analistas, ~R$650k/mês) |
| % CCVs com ajustes contratuais | ~25% |
| % casos com pendências | ~39% (~50% evitáveis) |

### EoP

| Track | NPS | Lead Time |
|-------|-----|-----------|
| Cash — CRN parceiro | 62,1 | 75,5d |
| Cash — sem CRN parceiro | 2,8 | 121,9d |
| Cash — agregado | 54,1 | 84,3d |
| Mortgage — Internal Corban | 29,6 | 100,2d |
| Mortgage — w/ Partners | 36,6 | 126,6d |
| Mortgage — agregado | 36,6 | 125,7d |
| NPS EoP total | ~45 | — |
| Unit cost pós-contrato | ~R$1.079/CCV | — |
| Attach rate CRN parceiro (Cash) | ~82% | — |
| Attach rate Internal Corban (Mortgage) | ~14% (meta: 40% mid-2026, 100% fim-2026) | — |

### Superset Dashboards de Referência

| Dashboard | URL |
|-----------|-----|
| **Fibonacci** (KPIs top-level FS) | [dashboard/2608](https://superset.apps.data-prd.habitat.zone/superset/dashboard/2608/?native_filters_key=dDh6IIGlT-pzn26pNdObLfREBRYeXFAyq8La-U_w2qg17iJtziEiH75U_c7WAce3) |
| **Demand Conversion** | [dashboard/2915](https://superset.apps.data-prd.habitat.zone/superset/dashboard/2915/?native_filters_key=0a3HQaGb7F3w5ocmOaRjX2vCetgsveB6t3ubyOkCTKglp4Sh1ktOzUF3bETXwkQ-) |
| **Polygon** (NPS / KPIs EoP) | [dashboard/3087](https://superset.apps.data-prd.habitat.zone/superset/dashboard/3087/) |
| **EoF Conversion** (OA2SO, SO2CCVe, CCV2CD) | [dashboard/1384](https://superset.apps.data-prd.habitat.zone/superset/dashboard/1384/?native_filters_key=9NJo85VO9rON_m4l734v6MuTsFkoQabYATt6vlRV8mCQ9f4ZkRjkDyiiZrfudQKH) |
| **Dataset Lead Time EoP** | [datasource/16038](https://superset.apps.data-prd.habitat.zone/explore/?datasource_type=table&datasource_id=16038) |
| **Dataset DSAT/Resolution Rate** | [datasource/18277](https://superset.apps.data-prd.habitat.zone/explore/?datasource_type=table&datasource_id=18277) |
| **Dataset NPS EoP** | [datasource/18337](https://superset.apps.data-prd.habitat.zone/explore/?datasource_type=table&datasource_id=18337) |
| **Dataset Attach Rate** | [datasource/18841](https://superset.apps.data-prd.habitat.zone/explore/?datasource_type=table&datasource_id=18841) |
| **Dataset Share IC** | [datasource/18647](https://superset.apps.data-prd.habitat.zone/explore/?datasource_type=table&datasource_id=18647) |

---

## 10. Pitfalls — Nunca Cometa Esses Erros

| ❌ Erro | ✅ Abordagem correta |
|---------|-------------------|
| Usar CCV como "número de vendas" ou métrica de receita | CD ≠ CCV. Usar `fact_closing_flows.sk_legal_analysis_ended_date` para CD (Financeiro) |
| Assumir `fact_closing_flows` como única fonte de CD | Parte dos CDs é inserida manualmente e pode estar em `datalake_gsheets_clean.closed_deals`. Verificar ambas ao reconciliar com o Financeiro. |
| Consultar EoF/EoP sem filtros 1P | Sempre filtrar `payment_model <> 'CLOSING_3P'` (em `dim_sale_agreement`) + tags legadas (`tags_from_salesflow` em `dim_offer`) |
| Filtrar tags Casa Mineira via `dim_sale_agreement.tags_from_salesflow` | Coluna **não existe** em `dim_sale_agreement` (Trino: `COLUMN_NOT_FOUND`). Está em `dw_sale.dim_offer.tags_from_salesflow` — join via `sk_offer`. Usar `COALESCE(do.tags_from_salesflow, '')` para não descartar ofertas sem tag. |
| Usar `ROW_NUMBER() OVER (...)` dentro do `ON` ou `WHERE` (ex.: pegar proposta mais recente do Internal Corban) | Trino/Spark não permitem window function em `ON`/`WHERE`. Isolar num CTE (`ic_latest`) com `ROW_NUMBER()` no `SELECT` e filtrar `rn = 1` no join. |
| Misturar 1P e 3P na mesma análise de funil | 3P segue fluxo completamente diferente. Manter separados sempre. |
| INNER JOIN `dim_sale_agreement` | Sempre LEFT JOIN — a tabela só tem linhas para ofertas que chegaram à etapa de acordo |
| Usar `fact_visits.sk_offer` para enumerar ofertas | Carrega apenas a primeira oferta por booking. Usar `fact_offers` diretamente. |
| Usar `fact_buyer_prospects` para calcular `# BP` | Captura apenas primeiro agendamento histórico (~50% do total). Fonte correta: `fact_sale_demand_event` WHERE `event_name = 'VISIT_BOOKED'`. |
| Usar `dim_sale_agreement.is_3p_lead_gen` | Essa coluna não existe em `dim_sale_agreement`. Filtrar via `fact_offers.is_3p_lead_gen`. |
| Reportar LT EoP como uma média única | Sempre segmentar por `payment_method` e tipo de Corban/CRN — distribuições muito diferentes entre tracks. |
| Usar `ts_offer_accepted` ou `ts_sale_agreement_created` como proxy de receita | Usar `fact_closing_flows.sk_legal_analysis_ended_date` (CD) para receita, ou `ts_sale_agreement_signed` (CCV) para pipeline. |
| Reportar volume de CCV sem declarar gross vs net | Default = gross (inclui CCVs cancelados posteriormente). Declarar sempre. |
| Incluir `sk_* = -1` em GROUP BY sem filtrar | Todos os `sk_*` usam `-1` para linhas não atribuídas. Filtrar `sk_closing_specialist <> -1` etc. |
| Conflitar SAC com CCV | SAC = rascunho criado (pipeline). CCV = contrato assinado (marco comercial). CD = pós-DD e TC. |
| Usar colunas de status EoP sem validar enums | `closing_status`, `*_dilligence_status` podem ter sido estendidos. Validar valores atuais antes de usar. |
| Usar `fact_buyer_prospects.sale_agreements_signed` para BP2CCV cohortado | Dá conversão lifetime, não cohort mensal. Fibonacci usa janela M0+M1. |
