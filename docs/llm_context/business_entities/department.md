# Department

## Overview

A department (also called queue or "caixa"/"fila") is the organizational unit responsible for handling a specific type of customer support request. Departments determine **routing**, **SLA targets**, and **journey classification** for tickets and contacts.

Departments are chosen based on what the customer is talking about. The routing logic works as follows:
1. Customer initiates contact (call, chat, email)
2. The chatbot or IVR identifies the topic
3. The interaction is routed to the appropriate department/queue
4. If the bot cannot identify the correct queue, a **default queue** is used

Key routing nuances:
- Some routings are non-trivial — e.g., a customer requesting changes to their registration is routed to the **repairs queue**
- **Hefesto** manages all Twilio queues (Front Office). Some queues exist **only in Zendesk** (Back Office queues without a Twilio counterpart)
- The primary source of queue definitions is the **"Controle de Departamentos"** Google Sheet

Each department maps to a **journey_step** (e.g., Onboarding, Offboarding, Reparos) and a **team**, forming a hierarchy:

```
Journey step (e.g., Offboarding)
  └── Department (e.g., Offboarding Reparos)
        └── Team (e.g., Offboarding Reparos Team A)
```

## Synonyms

- **Departamento**, **fila**, **caixa** → `department` / queue
- **Jornada** → `journey_step` (business-level grouping)
- **Time**, **equipe** → `team` (operational team within a department)

## Tables

| You need... | Use this table |
|-------------|----------------|
| Department dimension (name, journey, team hierarchy) | `dw_customer_support.dim_department` |
| Department definitions such as manager, from GSheets (primary source of truth) | `gsheets_clean.department_control` |
| Hefesto queue definitions (Twilio queues) | `hefesto_clean.queue` |
| Hefesto queue types | `hefesto_clean.queue_type` |
| Hefesto queue events | `hefesto_clean.queue_event` |

### Key columns in `dim_department`

| Column | Description |
|--------|-------------|
| `sk_department` | Surrogate key |
| `department` | Department/queue name |
| `board` | Board classification |
| `team` | Team within the department |
| `journey_step` | Journey the department belongs to (e.g., Onboarding, Offboarding, Reparos) |
| `channel` | Channel associated with this department |
| `front_or_back` | Whether this is Front Office or Back Office |
| `area` | Area classification |
| `concentrix_area_name` | Concentrix/Webhelp area mapping |
| `is_concentrix` | Whether handled by Concentrix/Webhelp |
| `is_active` | Whether the department is currently active |
| `is_partner` | Whether this is a partner department |

### How `dim_department` is built

Source: **"Controle de Departamentos" Google Sheet** (`gsheets_clean.department_control`). Contains the department → journey_step → team mapping for both Twilio (Front Office) and Zendesk (Back Office) queues.

## Key Metrics

- **Ticket volume by department** — how many tickets each department handles
- **SLA compliance by department** — percentage of tickets resolved within SLA per department
- **Backlog by department** — open tickets exceeding SLA per department
- **CSAT by department** — satisfaction scores per department
- **AHT by department** — Average Handling Time per department (for Front Office)

## Relationships with Other Entities

### Ticket (1:N — one department handles many tickets)

JOIN via `ft.sk_main_department = dd.sk_department` from `dw_customer_support.fact_tickets`. Note: use `sk_main_department` (not `sk_department`).

### Analyst (1:N — one department has many analysts)

Department context is not directly in `dim_analyst`. Join through tickets or contacts.

### Contact (1:N — one department handles many contacts)

`fact_customer_contacts` has `sk_department` (and also `sk_prev_department`, `sk_next_department`, `sk_first_department`, `sk_last_department`).

### SLA (N:1 — department maps to SLA journey)

SLA targets are determined by journey. The hierarchy for SLA resolution is: tag → theme → journey. Journey comes from `dim_department.journey_step`.

### Taxonomy (N:M — departments can handle multiple taxonomies)

Different taxonomy topics can appear within the same department, and the same topic can appear across departments. Taxonomy and department together drive SLA and ticket rate.

## Dos and Don'ts

**Do:**
- Use `dim_department` as the primary department dimension for all S&S queries
- Join tickets on `ft.sk_main_department = dd.sk_department` (not `sk_department` on fact)
- Use `journey_step` for journey-level analysis (the most common business grouping)
- Use `department` (not `department_name`) for the department name column
- Remember that the "Controle de Departamentos" GSheet is the primary source of truth for department definitions
- Distinguish Front Office (Twilio) from Back Office (Zendesk-only) using `front_or_back`

**Don't:**
- Don't assume every department has a Twilio queue — Back Office departments exist only in Zendesk
- Don't confuse department (routing/queue) with taxonomy (topic classification) — they are orthogonal dimensions
- Don't ignore the journey hierarchy — SLA targets cascade from journey level
- Don't treat Hefesto queues as the complete list — some Back Office queues are Zendesk-only
- Don't use `department_name` or `journey_name` — the actual columns are `department` and `journey_step`

## Golden Queries

### Query 1 — Ticket volume and SLA by department

Monthly ticket volume and SLA compliance per department.

```sql
SELECT
    date_trunc('month', CAST(ft.ts_created AS TIMESTAMP)) AS month_created,
    dd.department,
    dd.journey_step,
    dd.front_or_back,
    COUNT(*) AS ticket_volume,
    SUM(CASE WHEN fb.is_backlog_within_sla THEN 1 ELSE 0 END) AS tickets_in_sla,
    CAST(SUM(CASE WHEN fb.is_backlog_within_sla THEN 1 ELSE 0 END) AS DOUBLE) / COUNT(*) AS sla_rate
FROM dw_customer_support.fact_tickets AS ft
LEFT JOIN dw_customer_support.dim_department AS dd
    ON ft.sk_main_department = dd.sk_department
LEFT JOIN dw_customer_support.fact_tickets_backlog AS fb
    ON ft.sk_ticket = fb.sk_ticket
WHERE ft.ts_created >= DATE '2025-01-01'
GROUP BY 1, 2, 3, 4
```

### Query 2 — Department with analyst count and CSAT

Department performance including analyst count and average CSAT.

```sql
SELECT
    dd.department,
    dd.journey_step,
    dd.front_or_back,
    COUNT(DISTINCT da.sk_analyst) AS active_analysts,
    COUNT(ft.sk_ticket) AS total_tickets,
    AVG(fcsat.first_csat_score) AS avg_csat
FROM dw_customer_support.fact_tickets AS ft
LEFT JOIN dw_customer_support.dim_department AS dd
    ON ft.sk_main_department = dd.sk_department
LEFT JOIN dw_customer_support.dim_analyst AS da
    ON ft.sk_last_analyst = da.sk_analyst
LEFT JOIN dw_satisfaction_rating.fact_ticket_csat AS fcsat 
  ON ft.sk_ticket = fcsat.sk_ticket 
WHERE ft.ts_created >= DATE '2025-01-01'
GROUP BY 1, 2, 3
```
