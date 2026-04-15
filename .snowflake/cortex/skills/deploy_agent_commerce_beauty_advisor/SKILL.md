---
name: deploy_agent_commerce_beauty_advisor
description: "Deploy the Agent Commerce beauty advisor demo to a Snowflake account. Creates database, tables, Cortex Agent, Cortex Search, Semantic Views, and SPCS backend service. Use when: deploy agent commerce, setup beauty advisor demo, install agent commerce, deploy commerce demo. Triggers: agent commerce, beauty advisor, deploy demo, commerce demo."
---

# Deploy Agent Commerce Beauty Advisor v2

Fully automated deployment of the Agent Commerce beauty advisor v2 demo. Builds Docker image from source (no Docker Hub), uses git-based data loading, and verifies all objects.

**Source repo**: `https://github.com/sfc-gh-amgupta/agent_commerce_beauty_advisor_v2`

## Step 0: Show Object Inventory

Before ANY deployment, present this inventory to the user so they know what will be created:

| Category | Objects | Count |
|----------|---------|-------|
| Database | AGENT_COMMERCE | 1 |
| Schemas | PRODUCTS, SOCIAL, INVENTORY, CUSTOMERS, CART_OLTP, UTIL | 6 |
| Warehouse | AGENT_COMMERCE_WH (X-SMALL) | 1 |
| Role | AGENT_COMMERCE_ROLE | 1 |
| Tables | PRODUCTS schema (8), SOCIAL (4), INVENTORY (3), CUSTOMERS (2) | 17 |
| Hybrid Tables | CART_OLTP schema (7) | 7 |
| Dynamic Table | PRODUCT_LABEL_EXTRACT | 1 |
| Views | PRODUCT_CATALOG_VIEW, PRODUCT_LABEL_VIEW, SOCIAL_PROOF_VIEW | 3 |
| Semantic Views | PRODUCT, SOCIAL_PROOF, CART, CUSTOMER, INVENTORY | 5 |
| Cortex Search | PRODUCT_SEARCH, LABEL_SEARCH, SOCIAL_SEARCH | 3 |
| Cortex Agents | AGENTIC_COMMERCE_ASSISTANT (17 tools), EXECUTIVE_PRODUCT_360 (6 tools) | 2 |
| MCP Server | AGENTIC_COMMERCE_MCP_SERVER | 1 |
| Streamlit | EXECUTIVE_PRODUCT_360 | 1 |
| SPCS Service | AGENT_COMMERCE_BACKEND | 1 |
| Compute Pool | AGENT_COMMERCE_POOL (CPU_X64_S) | 1 |
| UDFs/Procs | Various (face analysis, cart ops, email, etc.) | ~26 |
| DMFs | COST_EXCEEDS_PRICE (custom) + 3 built-in | 4 |
| Notebook | NRFDEMO_MULTIMODAL_PROCESSING | 1 |
| Stages | PRODUCT_LABELS, PRODUCT_MEDIA, FACE_IMAGES, EXECUTIVE_360, CSV_DATA | 5 |
| **Total objects** | | **~81** |

**Ask** user: "This will create ~81 objects in your account. Proceed?"

## Step 1: Check Prerequisites

**Check** Docker is available:
```bash
docker --version
```

**If Docker is NOT installed:**
- macOS: Check for Homebrew first:
  ```bash
  brew --version && brew install --cask docker
  ```
  If Homebrew is not available:
  ```bash
  curl -fsSL https://get.docker.com | sh
  ```
- Linux: `curl -fsSL https://get.docker.com | sh`
- After install, remind user to **launch Docker Desktop** and wait for the daemon to start.

**If Docker daemon not running** (common on macOS after install):
```bash
open -a Docker
```
Wait 15-30 seconds, then verify with `docker info`. Retry up to 3 times.

**Check** Snowflake CLI:
```bash
snow --version
```

**Check** Cross-Region Inference (required for `claude-opus-4-6` model):
```sql
SHOW PARAMETERS LIKE 'CORTEX_ENABLED_CROSS_REGION' IN ACCOUNT;
```

If the value is NOT `ANY_REGION`:
- **Inform user**: "Cross-region inference is required for this demo. The agents, Dynamic Table AI extraction, and face analysis UDF all use the `claude-opus-4-6` model, which may not be available in your region natively. Enabling cross-region allows Cortex to route LLM requests to regions where the model is available. This will run: `ALTER ACCOUNT SET CORTEX_ENABLED_CROSS_REGION = 'ANY_REGION';` — Proceed?"
- **If user agrees**, run:
```sql
ALTER ACCOUNT SET CORTEX_ENABLED_CROSS_REGION = 'ANY_REGION';
```
- **If user declines**, warn: "Agent features and AI extraction will not work without cross-region inference enabled. The demo requires `claude-opus-4-6` which may not be available in all regions natively."
- Requires **ACCOUNTADMIN** role (already required for this deployment).

## Step 2: Cleanup (if re-deploying)

**Ask** user: "Should I clean up any existing AGENT_COMMERCE objects first?"

If yes, run cleanup:
```sql
USE ROLE ACCOUNTADMIN;
DROP DATABASE IF EXISTS AGENT_COMMERCE CASCADE;
DROP WAREHOUSE IF EXISTS AGENT_COMMERCE_WH;
DROP COMPUTE POOL IF EXISTS AGENT_COMMERCE_POOL;
DROP INTEGRATION IF EXISTS GITHUB_API_INTEGRATION;
DROP ROLE IF EXISTS AGENT_COMMERCE_ROLE;
```

## Step 3: Create Role and Git Integration

Execute via `snowflake_sql_execute`:

```sql
USE ROLE ACCOUNTADMIN;
```

```sql
CREATE ROLE IF NOT EXISTS AGENT_COMMERCE_ROLE
    COMMENT = 'Role for Agent Commerce application';
```

```sql
GRANT CREATE DATABASE ON ACCOUNT TO ROLE AGENT_COMMERCE_ROLE;
GRANT CREATE WAREHOUSE ON ACCOUNT TO ROLE AGENT_COMMERCE_ROLE;
GRANT CREATE COMPUTE POOL ON ACCOUNT TO ROLE AGENT_COMMERCE_ROLE;
GRANT BIND SERVICE ENDPOINT ON ACCOUNT TO ROLE AGENT_COMMERCE_ROLE;
GRANT CREATE INTEGRATION ON ACCOUNT TO ROLE AGENT_COMMERCE_ROLE;
GRANT CREATE AGENT ON SCHEMA AGENT_COMMERCE.UTIL TO ROLE AGENT_COMMERCE_ROLE;
```

```sql
DECLARE
    current_user_name VARCHAR;
BEGIN
    current_user_name := CURRENT_USER();
    EXECUTE IMMEDIATE 'GRANT ROLE AGENT_COMMERCE_ROLE TO USER "' || current_user_name || '"';
END;
```

```sql
CREATE OR REPLACE API INTEGRATION GITHUB_API_INTEGRATION
    API_PROVIDER = GIT_HTTPS_API
    API_ALLOWED_PREFIXES = ('https://github.com/sfc-gh-amgupta/')
    ENABLED = TRUE
    COMMENT = 'Integration for Agent Commerce GitHub repository';
```

```sql
GRANT USAGE ON INTEGRATION GITHUB_API_INTEGRATION TO ROLE AGENT_COMMERCE_ROLE;
```

## Step 4: Create Database and Clone Git Repo

```sql
USE ROLE AGENT_COMMERCE_ROLE;
```

```sql
CREATE DATABASE IF NOT EXISTS AGENT_COMMERCE
    COMMENT = 'Agent Commerce Demo - AI-powered beauty advisor';
```

```sql
CREATE SCHEMA IF NOT EXISTS AGENT_COMMERCE.UTIL COMMENT = 'Utilities and shared resources';
```

```sql
CREATE OR REPLACE GIT REPOSITORY AGENT_COMMERCE.UTIL.AGENT_COMMERCE_GIT
    API_INTEGRATION = GITHUB_API_INTEGRATION
    ORIGIN = 'https://github.com/sfc-gh-amgupta/agent_commerce_beauty_advisor_v2.git'
    COMMENT = 'Agent Commerce v2 source code and data';
```

```sql
ALTER GIT REPOSITORY AGENT_COMMERCE.UTIL.AGENT_COMMERCE_GIT FETCH;
```

## Step 5: Run SQL Scripts (01-07)

Run each script via EXECUTE IMMEDIATE. **Wait for each to complete before proceeding.**

```sql
EXECUTE IMMEDIATE FROM @AGENT_COMMERCE.UTIL.AGENT_COMMERCE_GIT/branches/main/sql/01_setup_infrastructure.sql;
```

```sql
EXECUTE IMMEDIATE FROM @AGENT_COMMERCE.UTIL.AGENT_COMMERCE_GIT/branches/main/sql/02_create_tables.sql;
```

```sql
EXECUTE IMMEDIATE FROM @AGENT_COMMERCE.UTIL.AGENT_COMMERCE_GIT/branches/main/sql/03_load_data.sql;
```

```sql
EXECUTE IMMEDIATE FROM @AGENT_COMMERCE.UTIL.AGENT_COMMERCE_GIT/branches/main/sql/04_create_views.sql;
```

```sql
EXECUTE IMMEDIATE FROM @AGENT_COMMERCE.UTIL.AGENT_COMMERCE_GIT/branches/main/sql/05_create_udfs_procedures.sql;
```

```sql
EXECUTE IMMEDIATE FROM @AGENT_COMMERCE.UTIL.AGENT_COMMERCE_GIT/branches/main/sql/06_create_cortex_search.sql;
```

```sql
EXECUTE IMMEDIATE FROM @AGENT_COMMERCE.UTIL.AGENT_COMMERCE_GIT/branches/main/sql/07_create_semantic_views.sql;
```

## Step 6: Build and Push Docker Image

**IMPORTANT**: Build from repo source. NO Docker Hub dependency.

Clone repo and build:
```bash
git clone https://github.com/sfc-gh-amgupta/agent_commerce_beauty_advisor_v2.git /tmp/agent_commerce_v2_deploy
```

```bash
docker build --platform linux/amd64 -t agent-commerce-backend:latest /tmp/agent_commerce_v2_deploy/backend
```

Login to Snowflake image registry (uses active `snow` connection — no Docker Hub login needed):
```bash
snow spcs image-registry login
```

Get registry URL and push:
```bash
snow spcs image-repository url AGENT_COMMERCE.UTIL.AGENT_COMMERCE_REPO
```

Use the returned URL to tag and push:
```bash
docker tag agent-commerce-backend:latest <REPO_URL>/agent-commerce-backend:latest
docker push <REPO_URL>/agent-commerce-backend:latest
```

Replace `<REPO_URL>` with the actual URL from the previous command. This takes 2-5 minutes.

Verify image uploaded:
```sql
SHOW IMAGES IN IMAGE REPOSITORY AGENT_COMMERCE.UTIL.AGENT_COMMERCE_REPO;
```

## Step 6b: Create Agents and Deploy SPCS

**IMPORTANT**: Script 08 uses `CREATE OR REPLACE AGENT ... FROM SPECIFICATION $$...$$;` syntax (NOT `$spec$`, NOT `CREATE CORTEX AGENT`). The MCP server uses `CREATE OR REPLACE MCP SERVER ... FROM SPECIFICATION $$yaml$$;` (NOT `CREATE CORTEX MCP SERVER`, NOT `SPEC = '{json}'`).

```sql
EXECUTE IMMEDIATE FROM @AGENT_COMMERCE.UTIL.AGENT_COMMERCE_GIT/branches/main/sql/08_create_agents.sql;
```

```sql
EXECUTE IMMEDIATE FROM @AGENT_COMMERCE.UTIL.AGENT_COMMERCE_GIT/branches/main/sql/09_deploy_spcs.sql;
```

**NOTE**: The script uses `CREATE OR REPLACE SERVICE` so re-running it will recreate the service with the latest image. Suspend/resume does NOT pull new images — only DROP+CREATE (or CREATE OR REPLACE) does. The ingress URL changes after recreation — always query `SHOW ENDPOINTS` for the current URL.

Wait for SPCS service:
```sql
SELECT SYSTEM$GET_SERVICE_STATUS('AGENT_COMMERCE.UTIL.AGENT_COMMERCE_BACKEND');
```
If PENDING, wait 30s and retry up to 10 times.

```sql
EXECUTE IMMEDIATE FROM @AGENT_COMMERCE.UTIL.AGENT_COMMERCE_GIT/branches/main/sql/10_setup_dmfs.sql;
```

## Step 6c: Deploy Notebook

The chatbot frontend (React UI) is pre-built and included in the Docker image via `backend/static/`. The Dockerfile has `COPY static/ ./static/` which bundles `index.html`, `vite.svg`, and the JS/CSS assets into the image. No separate frontend build step is needed.

Deploy the walkthrough notebook from the git repo:
```sql
CREATE OR REPLACE NOTEBOOK AGENT_COMMERCE.UTIL.NRFDEMO_MULTIMODAL_PROCESSING
  FROM '@AGENT_COMMERCE.UTIL.AGENT_COMMERCE_GIT/branches/main/notebooks'
  MAIN_FILE = 'NRFDEMO_MULTIMODAL_PROCESSING.ipynb'
  QUERY_WAREHOUSE = AGENT_COMMERCE_WH;
```

## Step 7: Verify All Objects Against Inventory

Run these verification queries and present results as a pass/fail table:

```sql
SELECT 'Tables' AS category, COUNT(*) AS found, 24 AS expected
FROM INFORMATION_SCHEMA.TABLES
WHERE TABLE_CATALOG = 'AGENT_COMMERCE' AND TABLE_TYPE IN ('BASE TABLE', 'HYBRID TABLE')
  AND TABLE_SCHEMA NOT IN ('INFORMATION_SCHEMA')
UNION ALL
SELECT 'Dynamic Tables', COUNT(*), 1
FROM INFORMATION_SCHEMA.TABLES
WHERE TABLE_CATALOG = 'AGENT_COMMERCE' AND TABLE_TYPE = 'DYNAMIC TABLE'
UNION ALL
SELECT 'Views', COUNT(*), 3
FROM INFORMATION_SCHEMA.VIEWS
WHERE TABLE_CATALOG = 'AGENT_COMMERCE' AND TABLE_SCHEMA NOT IN ('INFORMATION_SCHEMA');
```

```sql
SHOW CORTEX SEARCH SERVICES IN DATABASE AGENT_COMMERCE;
```

```sql
SHOW SEMANTIC VIEWS IN DATABASE AGENT_COMMERCE;
```

```sql
SHOW AGENTS IN SCHEMA AGENT_COMMERCE.UTIL;
-- Expected: AGENTIC_COMMERCE_ASSISTANT, EXECUTIVE_PRODUCT_360
-- NOTE: Use SHOW AGENTS (not SHOW CORTEX AGENTS)
```

```sql
SHOW CORTEX MCP SERVERS IN SCHEMA AGENT_COMMERCE.UTIL;
```

```sql
SHOW STREAMLITS IN SCHEMA AGENT_COMMERCE.UTIL;
```

```sql
SHOW NOTEBOOKS IN SCHEMA AGENT_COMMERCE.UTIL;
-- Expected: NRFDEMO_MULTIMODAL_PROCESSING
```

```sql
SHOW ENDPOINTS IN SERVICE AGENT_COMMERCE.UTIL.AGENT_COMMERCE_BACKEND;
```

```sql
SELECT 'PRODUCTS' AS domain, COUNT(*) AS rows FROM AGENT_COMMERCE.PRODUCTS.PRODUCTS
UNION ALL SELECT 'CUSTOMERS', COUNT(*) FROM AGENT_COMMERCE.CUSTOMERS.CUSTOMERS
UNION ALL SELECT 'INVENTORY', COUNT(*) FROM AGENT_COMMERCE.INVENTORY.LOCATIONS
UNION ALL SELECT 'REVIEWS', COUNT(*) FROM AGENT_COMMERCE.SOCIAL.PRODUCT_REVIEWS
UNION ALL SELECT 'CART_SESSIONS', COUNT(*) FROM AGENT_COMMERCE.CART_OLTP.CART_SESSIONS;
```

Present a verification summary table showing:
- Expected vs Found for each object category
- PASS/FAIL status for each
- Data row counts

**Do NOT proceed to Step 8 unless ALL verifications pass.**

## Step 8: End-to-End Test Plan

Test both agents with these questions. Present each question, run it, and report the result.

### Test A: Beauty Advisor Agent (6 questions)

Run each via the agent (use `snowflake_sql_execute` with `SNOWFLAKE.CORTEX.DATA_AGENT_RUN()`). **Set timeout_seconds to 1200** — the agent orchestrates multiple tools (search, analyst, cart) and complex queries can take 60-180s.

**IMPORTANT**: Q1-Q3 and Q6 are independent. Q4 ("Do you have it in stock?") requires conversational context from Q3 — pass the prior messages in the `messages` array. Q5 requires context from Q4.

Example (single question):
```sql
SELECT TRY_PARSE_JSON(
  SNOWFLAKE.CORTEX.DATA_AGENT_RUN(
    'AGENT_COMMERCE.UTIL.AGENTIC_COMMERCE_ASSISTANT',
    $${"messages": [{"role": "user", "content": [{"type": "text", "text": "YOUR QUESTION"}]}]}$$
  )
) AS resp;
```

Example (multi-turn for Q4 — include Q3 question + Q3 response + Q4 question):
```sql
SELECT TRY_PARSE_JSON(
  SNOWFLAKE.CORTEX.DATA_AGENT_RUN(
    'AGENT_COMMERCE.UTIL.AGENTIC_COMMERCE_ASSISTANT',
    $${"messages": [
      {"role": "user", "content": [{"type": "text", "text": "How are the reviews for Summer Fridays Luxe Foundation on your website"}]},
      {"role": "assistant", "content": "<PASTE Q3 RESPONSE TEXT HERE>"},
      {"role": "user", "content": [{"type": "text", "text": "Do you have it in stock?"}]}
    ]}$$
  )
) AS resp;
```

| # | Question | Expected Behavior | Pass Criteria |
|---|----------|-------------------|---------------|
| 1 | Can you recommend face products for my oily skin with warm undertone | ProductAnalyst returns skin_type filtered results | Response contains product names with prices |
| 2 | Compare these 2 foundations - Summer Fridays Luxe Foundation and Drunk Elephant Pro Foundation | Multi-product lookup | Both products mentioned with comparison |
| 3 | How are the reviews for Summer Fridays Luxe Foundation on your website | SocialSearch/SocialAnalyst | Review summaries, ratings, or sentiment |
| 4 | Do you have it in stock? (multi-turn — include Q3 context) | InventoryAnalyst follow-up | Stock/inventory info for Summer Fridays Luxe Foundation |
| 5 | Add it to my cart and checkout (multi-turn — include Q4 context) | ACP cart flow | Cart creation and/or checkout steps |
| 6 | List the ingredients and any warnings for Summer Fridays Luxe Foundation | LabelSearch + GetLabelURL | Ingredient list and/or warnings |

**After each question**: Extract `resp:choices[0]:messages[0]:content` for the text response. Report pass/fail.

### Test B: Executive Product 360 (4 questions)

| # | Question | Expected Behavior |
|---|----------|-------------------|
| 1 | What are my top products in past 6 months | ProductAnalyst + CheckoutAnalyst |
| 2 | Why am I doing better in lip than others? | Cross-tool analysis |
| 3 | What has been my stock levels across non lip products | InventoryAnalyst |
| 4 | Summarize the findings and send email to cdo@operations.com | EmailSender tool |

**Testing approach**: For each question, check agent logs to confirm the correct tools were invoked. If any test fails, check SPCS logs and agent error details. Troubleshoot and retry.

**Only declare deployment SUCCESS after all SQL-based test questions produce reasonable results.**

## Step 8b: Chatbot Widget Validation

The chatbot widget runs on SPCS with a public endpoint that requires Snowflake OAuth with passkey/biometric verification. This means automated API testing via `web_fetch` or `curl` is NOT possible — the SPCS ingress enforces browser-based OAuth.

**What Step 8 already validates**: The `DATA_AGENT_RUN` SQL tests in Step 8 invoke the **exact same Cortex Agent** (`AGENTIC_COMMERCE_ASSISTANT`) that the chatbot widget calls via its FastAPI backend. If all 6 SQL tests pass, the agent logic is confirmed working.

**What Step 8b validates**: The SPCS service is running and the chatbot UI is accessible.

**Validate SPCS service health:**
```sql
SELECT v.value:status::STRING AS status, v.value:containerName::STRING AS container
FROM TABLE(RESULT_SCAN(LAST_QUERY_ID())) t, LATERAL FLATTEN(input => PARSE_JSON(t."status")) v;
```
Run this after:
```sql
CALL SYSTEM$GET_SERVICE_STATUS('AGENT_COMMERCE.UTIL.AGENT_COMMERCE_BACKEND');
```

**Validate endpoint is reachable:**
```sql
SHOW ENDPOINTS IN SERVICE AGENT_COMMERCE.UTIL.AGENT_COMMERCE_BACKEND;
```
Confirm `ingress_url` is returned and `is_public = true`.

**Only proceed to Step 9 after Step 8 SQL tests pass and SPCS service is confirmed READY.**

## Step 9: Deployment Complete — Everything You Need to Demo

After all tests pass, present the following to the user as the final deployment handoff.

### 9a. Retrieve Live URLs (MUST run before presenting summary)

**IMPORTANT**: Always query the database for the latest URLs — NEVER cache or hardcode them. The SPCS ingress URL can change after service recreation.

Run these queries and capture the results:

```sql
SHOW ENDPOINTS IN SERVICE AGENT_COMMERCE.UTIL.AGENT_COMMERCE_BACKEND;
```
Capture the `ingress_url` column value — this is the **Beauty Advisor Chatbot URL**.

```sql
SHOW STREAMLITS IN SCHEMA AGENT_COMMERCE.UTIL;
```

### 9b. Present Final Summary

Substitute the **actual URLs** from Step 9a into the summary below. Do NOT present placeholder URLs — the user needs clickable links.

---

**Deployment Complete!** Here is everything you need to run the demo.

#### Access Points

| What | Where |
|------|-------|
| **Beauty Advisor Chatbot** | `https://<ACTUAL ingress_url from Step 9a SHOW ENDPOINTS query>` (open in browser — requires Snowflake OAuth) |
| **Executive Product 360 Dashboard** | Snowsight > Streamlit > `AGENT_COMMERCE.UTIL.EXECUTIVE_PRODUCT_360` |
| **Notebook (AISQL Pipeline)** | Snowsight > Notebooks > `AGENT_COMMERCE.UTIL.NRFDEMO_MULTIMODAL_PROCESSING` |
| **MCP Server** | `AGENT_COMMERCE.UTIL.AGENTIC_COMMERCE_MCP_SERVER` — connect from ChatGPT, Claude Desktop, or VS Code Copilot |

#### Invoke Agents via SQL (Snowsight / Notebooks)

Beauty Advisor:
```sql
SELECT SNOWFLAKE.CORTEX.DATA_AGENT_RUN(
  'AGENT_COMMERCE.UTIL.AGENTIC_COMMERCE_ASSISTANT',
  $${"messages": [{"role": "user", "content": [{"type": "text", "text": "YOUR QUESTION HERE"}]}]}$$
);
```

Executive Product 360:
```sql
SELECT SNOWFLAKE.CORTEX.DATA_AGENT_RUN(
  'AGENT_COMMERCE.UTIL.EXECUTIVE_PRODUCT_360',
  $${"messages": [{"role": "user", "content": [{"type": "text", "text": "YOUR QUESTION HERE"}]}]}$$
);
```

#### Demo Test Questions

**Beauty Advisor Agent** (use in chatbot or SQL):

| # | Question |
|---|----------|
| 1 | Can you recommend face products for my oily skin with warm undertone |
| 2 | Compare these 2 foundations for me - Summer Fridays Luxe Foundation and Drunk Elephant Pro Foundation |
| 3 | How are the reviews for Summer Fridays Luxe Foundation on your website |
| 4 | Do you have it in stock? |
| 5 | Add it to my cart and checkout |
| 6 | List the ingredients and any warnings I should be aware of for Summer Fridays Luxe Foundation |

**Executive Product 360** (use in Streamlit dashboard or SQL):

| # | Question |
|---|----------|
| 1 | What are my top products in past 6 months |
| 2 | Why am I doing better in lip than others? |
| 3 | What has been my stock levels across non lip products |
| 4 | Summarize the findings and send email to cdo@operations.com |

#### What Was Deployed & Where to Find It

| Category | Objects | Snowsight Location |
|----------|---------|-------------------|
| **Database** | AGENT_COMMERCE | Databases > AGENT_COMMERCE |
| **Schemas** | PRODUCTS, SOCIAL, INVENTORY, CUSTOMERS, CART_OLTP, UTIL | Databases > AGENT_COMMERCE > Schemas |
| **Tables** | 17 standard + 7 hybrid (CART_OLTP) + 1 dynamic | Each schema's Tables tab |
| **Cortex Agents** | AGENTIC_COMMERCE_ASSISTANT (17 tools), EXECUTIVE_PRODUCT_360 (6 tools) | AI & ML > Cortex Agents |
| **Cortex Search** | PRODUCT_SEARCH_SERVICE, LABEL_SEARCH_SERVICE, SOCIAL_SEARCH_SERVICE | AI & ML > Cortex Search |
| **Semantic Views** | PRODUCT, SOCIAL_PROOF, CART, CUSTOMER, INVENTORY | Each schema's Semantic Views tab |
| **MCP Server** | AGENTIC_COMMERCE_MCP_SERVER | AI & ML > MCP Servers |
| **Streamlit** | EXECUTIVE_PRODUCT_360 | Streamlit |
| **Notebook** | NRFDEMO_MULTIMODAL_PROCESSING | Notebooks |
| **SPCS Service** | AGENT_COMMERCE_BACKEND (FastAPI) | Compute > Services |
| **Compute Pool** | AGENT_COMMERCE_POOL (CPU_X64_S) | Compute > Compute Pools |
| **DMFs** | FRESHNESS, NULL_COUNT, ROW_COUNT, COST_EXCEEDS_PRICE on PRODUCTS table | Databases > AGENT_COMMERCE > PRODUCTS > PRODUCTS table > Data Quality |
| **Dynamic Table** | PRODUCT_LABEL_EXTRACT (AI label extraction, 5-min refresh) | Databases > AGENT_COMMERCE > PRODUCTS > Dynamic Tables |
| **Warehouse** | AGENT_COMMERCE_WH (X-SMALL) | Warehouses |

#### Monitoring

- **Dynamic Table refresh**: Snowsight > Databases > AGENT_COMMERCE > PRODUCTS > Dynamic Tables > PRODUCT_LABEL_EXTRACT — check refresh history and status
- **Data Quality (DMFs)**: Snowsight > Databases > AGENT_COMMERCE > PRODUCTS > PRODUCTS table > Data Quality tab — view freshness, null counts, row counts, and custom metric results
- **SPCS Service health**: `SELECT SYSTEM$GET_SERVICE_STATUS('AGENT_COMMERCE.UTIL.AGENT_COMMERCE_BACKEND');`
- **Cortex Search index status**: `SHOW CORTEX SEARCH SERVICES IN DATABASE AGENT_COMMERCE;` — check index build status

---

## Stopping Points

- After Step 0: if user declines to proceed
- After Step 1: if Docker not available and user can't install
- After Step 5: before Docker build (confirm infrastructure is set up)
- After Step 6: if Docker build/push fails
- After Step 7: if verification fails (troubleshoot before testing)

## Troubleshooting

**Docker not found**: Install via `brew install --cask docker` (macOS) or `curl -fsSL https://get.docker.com | sh` (Linux)

**Docker daemon not running**: `open -a Docker` (macOS), `sudo systemctl start docker` (Linux), wait 15-30s

**snow spcs image-registry login fails**: Ensure `snow` CLI is configured with an active connection. Run `snow connection test` to verify.

**SPCS service stuck in PENDING**: Check `DESCRIBE COMPUTE POOL AGENT_COMMERCE_POOL`. If SUSPENDED, run `ALTER COMPUTE POOL AGENT_COMMERCE_POOL RESUME`.

**EXECUTE IMMEDIATE fails**: Fetch git repo first: `ALTER GIT REPOSITORY AGENT_COMMERCE.UTIL.AGENT_COMMERCE_GIT FETCH;`

**Cortex Search not starting**: These use INCREMENTAL refresh and may take 2-5 minutes to build initial index.

**FRESHNESS DMF fails with "Function FRESHNESS$V1 does not exist"**: The UPDATED_AT column must be `TIMESTAMP_LTZ`, `TIMESTAMP_TZ`, or `DATE` — not `TIMESTAMP_NTZ`. The table creation script (`02_create_tables.sql`) defines UPDATED_AT as `TIMESTAMP_LTZ` to avoid this issue. If deploying on an existing table with NTZ, you cannot ALTER the column type — you must recreate the table.

**Agent creation fails with syntax error**: Ensure the script uses `CREATE OR REPLACE AGENT ... FROM SPECIFICATION $$...$$;` — NOT `$spec$` (fails with EXECUTE IMMEDIATE), NOT `CREATE CORTEX AGENT`, and NOT `AGENT_SPEC = $$`.

**MCP Server creation fails with "unexpected 'MCP'"**: The correct syntax is `CREATE OR REPLACE MCP SERVER ... FROM SPECIFICATION $$yaml$$;` — NOT `CREATE OR REPLACE CORTEX MCP SERVER`. The `CORTEX` keyword is NOT part of the DDL. The specification must be YAML (not JSON) inside `$$` delimiters.

**Agent invocation fails with "Unknown function SNOWFLAKE.CORTEX.AGENT"**: Use `SNOWFLAKE.CORTEX.DATA_AGENT_RUN('<db>.<schema>.<agent_name>', $${ ... }$$)` — not `SNOWFLAKE.CORTEX.AGENT()`. See Snowflake docs for DATA_AGENT_RUN.

**Model unavailable errors**: This demo uses `claude-opus-4-6` which requires cross-region inference. Verify `SHOW PARAMETERS LIKE 'CORTEX_ENABLED_CROSS_REGION' IN ACCOUNT;` returns `ANY_REGION`. If not: `ALTER ACCOUNT SET CORTEX_ENABLED_CROSS_REGION = 'ANY_REGION';`

**Chatbot URL shows JSON instead of UI**: The Docker image must include `backend/static/` with the pre-built React frontend. Verify the Dockerfile has `COPY static/ ./static/` (not `RUN mkdir -p /app/static`). If the static files are missing from the repo, download them from `https://github.com/sfc-gh-amgupta/agent_commerce_beauty_advisor/tree/main/backend/static`. Rebuild and push the Docker image, then DROP and recreate the SPCS service (suspend/resume does NOT pull a new image).

**SPCS endpoint requires passkey/biometric in browser**: Public SPCS endpoints use Snowflake OAuth which requires passkey verification. This is expected behavior — users must authenticate in their browser. Automated API testing (curl, Python requests) is not possible without a valid OAuth token. Use `DATA_AGENT_RUN` SQL for automated testing instead.

**DATA_AGENT_RUN query times out**: The agent orchestrates multiple tools (search, analyst, cart operations) and complex queries can take 60-180s. Use `timeout_seconds=1200` with `snowflake_sql_execute`. If it still times out, try simpler questions first (e.g., "What products do you have?") to verify basic connectivity.

**SPCS service not picking up new Docker image after push**: `ALTER SERVICE ... SUSPEND` / `RESUME` does NOT pull a new image — it restarts with the same cached image digest. You must `DROP SERVICE` and `CREATE SERVICE` again to pick up the latest image from the registry. The ingress URL will change after recreation — always query `SHOW ENDPOINTS` for the current URL.

**DMF schedule**: Use 5-field cron format: `USING CRON 0 */5 * * * UTC`. Six-field formats (with seconds) may be silently converted.

## Cleanup

```sql
USE ROLE ACCOUNTADMIN;
DROP DATABASE IF EXISTS AGENT_COMMERCE CASCADE;
DROP WAREHOUSE IF EXISTS AGENT_COMMERCE_WH;
DROP COMPUTE POOL IF EXISTS AGENT_COMMERCE_POOL;
DROP INTEGRATION IF EXISTS GITHUB_API_INTEGRATION;
DROP ROLE IF EXISTS AGENT_COMMERCE_ROLE;
```