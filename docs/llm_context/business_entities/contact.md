# Contact

## Overview

A contact is a direct interaction between a customer and a support agent — either a **call** or a **chat** session. Contacts are the real-time component of the Support & Services domain, representing the Front Office side of operations.

Contacts flow through the following system architecture:
1. **Customer initiates contact** via call or chat
2. **Calls** go through BigFone (IVR / call management) → Twilio (real-time handling)
3. **Chats** go through Greenseer/Wall-E (chatbots) → if escalated, Sauron session → Twilio (real-time handling)
4. At the end of every Front Office interaction, a **ticket is generated** in Zendesk

### Calls

- The unit of service in calls is a **reservation** — each time the call is transferred to a different analyst, a new reservation is created
- One call = one Sauron session = potentially multiple reservations
- Sources: BigFone (IVR events, call records), Sauron (session identity), Hefesto (queue/worker routing)

### Chats

- The unit of service in chats is a **task** — each client-to-analyst interaction within the same chat session is a task
- One Sauron session or Twilio channel = potentially multiple tasks
- Channels: WhatsApp, in-app chat
- Sources: QuintoMessenger (channel/task events), Sauron (session identity)

### IVR (Interactive Voice Response)

- The automated phone menu that precedes a call contact
- IVR interactions are tracked step-by-step in `fact_ivr_interactions`
- Some calls are resolved entirely within the IVR without reaching a human agent

### Chatbot Interactions

- Interactions handled by chatbots (Greenseer/Wall-E) that do **not** escalate to a human agent are called **retentions** — no Sauron session is created
- Interactions that escalate to a human agent are called **escalations** — a Sauron session is registered
- **Canonical source for bot sessions and bot-side contacts:** `datalake_chatbot.sessions` (all bot sessions; includes contacts that involve bot interaction)
- **Canonical source for messages** in flows that **start with a chatbot interaction:** `datalake_chatbot.messages`
- **`dw_customer_support.fact_sessions_chatbot` is deprecated** — do not use it for new analysis or dashboards

## Synonyms

- **Contato**, **atendimento**, **interação** → `contact`
- **Ligação**, **chamada** → `call`
- **Conversa**, **bate-papo** → `chat`
- **Reserva** (in call context) → `reservation` (Twilio unit per analyst transfer)
- **Tarefa** (in chat context) → `task` (Twilio unit per client-to-analyst interaction)
- **Retenção** → `retention` (chatbot-resolved, no human agent)
- **Escalação**,  **transbordo** → `escalation` (chatbot → human agent)
- **Ura** → `ivr`, old bot interaction, not wall-e

## Tables

| You need... | Use this table |
|-------------|----------------|
| Unified contacts (calls + chats) with Twilio time metrics, channel, status | `dw_customer_support.fact_customer_contacts` |
| IVR step-by-step interaction events | `dw_customer_support.fact_ivr_interactions` |
| **Bot sessions** (all sessions; contacts that use bot interaction) | `datalake_chatbot.sessions` |
| **Bot messages** (sessions that **start** with a chatbot interaction) | `datalake_chatbot.messages` |
| ~~`dw_customer_support.fact_sessions_chatbot`~~ | **DEPRECATED — do not use** |
| Chat and chatbot message aggregations | `dw_customer_support.fact_chat_metrics` |
| Message-level facts across channels | `dw_customer_support.fact_chat_messages` |
| Task-level time metrics linked to contacts | `dw_customer_support.fact_task_metrics` |
| Average Handling Time per agent, day, department | `datalake_customer_support.chat_aht` (enrich) |
| Unified call sessions (enrich — source for DW) | `datalake_customer_support.calls` |
| Unified chat sessions (enrich — source for DW) | `datalake_customer_support.chats` |
| IVR step interactions (enrich) | `datalake_customer_support.ivr_interactions` |
| Chatbot dimension attributes | `dw_customer_support.dim_chatbot` |
| Channel dimension | `dw_customer_support.dim_channel` |
| User IVR blocking and constraints | `dw_customer_support.fact_user_blocks` |

### Key columns in `fact_customer_contacts`

| Column | Description |
|--------|-------------|
| `sk_contact` | Surrogate key for the contact |
| `sk_interaction`, `sk_session`, `sk_task`, `sk_call`, `sk_reservation` | Interaction identifiers |
| `sk_ticket` | Linked ticket |
| `sk_user` | Customer user |
| `sk_department`, `sk_prev_department`, `sk_next_department` | Department routing |
| `sk_first_department`, `sk_last_department` | First and last departments |
| `sk_analyst` | Analyst who handled the contact |
| `origin`, `direction`, `channel`, `status` | Contact classification |
| `worker_email` | Analyst email |
| `total_talk_time`, `total_queue_time`, `total_wrap_up_time` | Time metrics |
| `total_waiting_time`, `first_reply_time`, `total_handling_time` | Time metrics |
| `is_contact_answered`, `is_interaction_answered` | Whether the contact was answered |
| `ts_task_created`, `ts_reservation_created`, `ts_reservation_ended` | Timestamps |

### Key columns in `fact_ivr_interactions`

| Column | Description |
|--------|-------------|
| `sk_interaction` | Surrogate key for the IVR interaction |
| `sk_task`, `sk_call` | Linked task and call |
| `step_name` | Name of the IVR step |
| `type` | Step type (e.g., menu, input) |
| `value` | Value entered (e.g., digit pressed) |
| `from_phone_number`, `to_phone_number` | Phone numbers |
| `ts_event`, `ts_ivr_started` | Timestamps |

### Chatbot enrich tables (`datalake_chatbot`)

Use these instead of the deprecated DW table:

| Table | Role |
|-------|------|
| `datalake_chatbot.sessions` | All bot sessions; covers **all contacts that involve bot interaction** |
| `datalake_chatbot.messages` | All messages for sessions that **begin** with a chatbot interaction |

Column-level detail: follow the matching governance metadata under the chatbot enrich DAG (if present) or inspect the table in the metastore — do not use `dw_customer_support.fact_sessions_chatbot`.

### How `datalake_customer_support.calls` is built

Aggregates call data from multiple sources:
- Sauron sessions for session identity
- Support session service for higher-level session tracking
- BigFone events for reservation outcomes (answered, timeout, rejected, abandoned)
- Hefesto queues and reservations for routing context

### How `datalake_customer_support.chats` is built

Resolves chat sessions from:
- QuintoMessenger task events, channels, and tasks
- Sauron sessions for session identity
- Derives direction (inbound/outbound) from SPOC/session creator
- Maps channel and origin

### AHT (Average Handling Time)

`datalake_customer_support.chat_aht` computes AHT per agent, day, and department:
- Uses reservation accepted/completed windows from QuintoMessenger
- Separates idle vs active chatting time
- Computes concurrency-adjusted AHT (accounts for agents handling multiple chats simultaneously)

## Key Metrics

- **Contact volume** per month, by channel (call, chat, WhatsApp)
- **AHT** — Average Handling Time per chat interaction (`chat_aht`)
- **Retention rate** — percentage of chatbot interactions that do not escalate to a human (derive from `datalake_chatbot.sessions` — not from deprecated `fact_sessions_chatbot`)
- **Escalation rate** — percentage of interactions escalated from chatbot to human. Also a metric in `metric_ss__tickets.escalation`
- **IVR abandonment rate** — calls abandoned during IVR (`fact_ivr_interactions`)
- **Reservation outcomes** — answered, timeout, rejected, abandoned per call (`calls`)
- **Concurrency** — number of simultaneous chats handled by an agent

## Relationships with Other Entities

### Ticket (N:1 — many contacts may link to one ticket)

Contacts are linked to tickets via `sk_ticket` in `fact_customer_contacts`. Chat tasks use WT-prefix and call tasks use CA-prefix identifiers.

### Analyst (N:1 — many contacts to one analyst)

Contacts are assigned to analysts via Twilio reservations (calls) or tasks (chats). JOIN via `sk_analyst` in `fact_customer_contacts` to `dim_analyst`.

### Department (N:1 — many contacts to one department)

The queue/department that handled the contact. `fact_customer_contacts` has `sk_department`, `sk_prev_department`, `sk_next_department`, `sk_first_department`, `sk_last_department`.

### Sauron Session (1:1 — one contact creates one session)

Every interaction reaching a human agent creates a Sauron session. Chatbot-retained interactions do **not** create a session.

## Dos and Don'ts

**Do:**
- Use `fact_customer_contacts` for unified call + chat analysis
- Use `fact_ivr_interactions` for IVR step analysis — the step type is `type` and the digit pressed is `value`
- Use **`datalake_chatbot.sessions`** for bot sessions and bot-side contact behavior; use **`datalake_chatbot.messages`** for message-level analysis when the session **started** with the chatbot
- Use `chat_aht` for agent handling time — it already adjusts for concurrency
- Remember that one call can have multiple reservations (transfers) and one chat session can have multiple tasks

**Don't:**
- **Don't use `dw_customer_support.fact_sessions_chatbot`** — it is deprecated
- Don't assume every contact has a linked ticket — some bot interactions end without ticket creation
- Don't confuse reservation (call unit per analyst) with task (interaction unit per analyst)
- Don't confuse retention (chatbot-resolved, no human) with escalation (chatbot → human) — model retention/escalation from `datalake_chatbot.sessions`, not the old DW fact
- Don't mix AHT from different sources — use `chat_aht` for the concurrency-adjusted version
- Don't forget that WhatsApp and in-app chats are different channels routed through QuintoMessenger

## Golden Queries

### Query 1 — Unified contacts with channel and status

All customer contacts (calls + chats) with channel and department context.

```sql
SELECT DISTINCT
    fc.*,
    dc.channel AS channel_dim,
    dc.direction,
    dd.department,
    dd.journey_step
FROM dw_customer_support.fact_customer_contacts AS fc
LEFT JOIN dw_customer_support.dim_channel AS dc
    ON fc.channel = dc.channel
LEFT JOIN dw_customer_support.dim_department AS dd
    ON fc.sk_department = dd.sk_department
WHERE fc.ts_task_created >= TIMESTAMP '2025-01-01'
```

### Query 2 — IVR interactions with step details

IVR step-by-step analysis for understanding customer navigation through the phone menu.

```sql
SELECT
    fi.sk_interaction,
    fi.sk_task,
    fi.sk_call,
    fi.step_name,
    fi.type,
    fi.value,
    fi.from_phone_number,
    fi.to_phone_number,
    fi.ts_event,
    fi.ts_ivr_started
FROM dw_customer_support.fact_ivr_interactions AS fi
WHERE fi.ts_event >= TIMESTAMP '2025-01-01'
```

