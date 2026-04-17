# Agent Commerce - Beauty Advisor

A complete Snowflake demo featuring two Cortex Agents for cosmetics retail: a customer-facing **Beauty Advisor** which covers end-to-end shopper experience discovery to conversion and an executive-facing **Executive Product 360** analytics dashboard.

## Architecture Overview

<p align="center">
  <img src="./images/architecture_overview.png" alt="Architecture Overview" width="100%">
</p>

> Open [architecture.html](architecture.html) in a browser for the interactive version.

## Solution Overview

Agent Commerce solution demonstrates how retail, CPG, and consumer brands can deploy a decoupled AI architecture where Snowflake serves as the intelligent data backend — a Cortex Agent that orchestrates product knowledge, customer intelligence, inventory, social proof, and transactional operations — while interoperating with any frontend or AI platform. Brands connect their existing website chatbots, mobile apps, or voice assistants via the Cortex Agent API, and expose the same intelligence to agentic commerce platforms like ChatGPT via MCP Server. The solution addresses personalized product consultation through visual AI, intelligent product discovery via semantic search, automated label compliance through multimodal extraction, consumer sentiment intelligence across social channels, low-latency cart and checkout via hybrid tables, and executive analytics through natural language — all without requiring brands to rebuild their customer-facing experiences on Snowflake.

## Expected Business Outcomes

By positioning Snowflake as the data intelligence layer behind any commerce frontend, Agent Commerce enables brands to increase conversion rates through personalized recommendations served to their existing channels, reduce support costs by offloading product knowledge queries to a Cortex Agent accessible from any chatbot, accelerate time-to-insight with natural language executive analytics, improve product safety compliance through automated label extraction and monitoring, drive customer retention via visual AI-based identification across touchpoints, and achieve platform-agnostic interoperability — any AI system that speaks REST or MCP can tap into the brand's unified data intelligence without data duplication or custom integrations.

## Solution Capabilities

**Vision**: Brands deploy a Cortex Agent as their unified data intelligence backend on Snowflake — decoupled from any specific frontend. The agent interoperates with the brand's existing chatbot or mobile app via the Cortex Agent API, and with Agentic commerce platforms like ChatGPT  via MCP Server — enabling a single source of product knowledge, customer intelligence, and transactional capability that serves every channel without data duplication.

| Key Business Capability | Required Technology Component | Enabling Snowflake Feature(s) |
|------------------------|-------------------------------|-------------------------------|
| Visual AI Skin Analysis | Containerized ML for visual profiling with embedding-based matching, served to any calling application | SPCS, Model Registry, Vector Similarity, Presigned URLs |
| Product Label Intelligence | Multimodal AI extraction from product label images with continuous refresh and semantic indexing | AI SQL, Dynamic Tables, Cortex Search |
| Data Quality & Operational Trust | Automated monitoring of freshness, completeness, and business rule validation | Data Metric Functions (built-in + custom) |
| Cross-Platform Agent Interoperability | Cortex Agent exposed via REST API for brand frontends and via MCP for AI platforms (ChatGPT, Claude, Copilot) | MCP Server, Cortex Agent API |
| Executive Reporting & Decision Support | Natural language analytics with automated email delivery and visual dashboards | Cortex Analyst, Semantic Views, Streamlit |
| Source-Controlled Deployment & Experimentation | Version-controlled SQL pipelines with interactive AI processing notebooks | Git Integration, Snowflake Notebooks |
| Transactional Commerce Operations | Full cart lifecycle with ACID-compliant order processing at sub-second latency, callable from any frontend | Hybrid Tables |

## Snowflake Features Role in the Solution

| Workload | Feature | Role in Solution |
|----------|---------|-----------------|
| **AI/ML** | Cortex Agents | Multi-tool orchestration — the intelligent backend that any frontend or AI platform calls into |
| | Cortex Search | Semantic search with INCREMENTAL refresh across products, labels, social content |
| | Cortex Analyst | Text-to-SQL over semantic views for structured queries without raw SQL |
| | AI_COMPLETE (AISQL) | Multimodal inference for label image extraction and dynamic table processing |
| | Model Serving & Model Registry (SPCS) | Containerized ML model serving and registry for visual AI inference on GPU-capable compute |
| | Vector Similarity | Embedding-based customer identification via VECTOR_COSINE_SIMILARITY |
| | MCP Server | Expose the Cortex Agent to ChatGPT, Claude Desktop, Copilot, and any MCP-compatible client |
| **Horizon** | Semantic Views | Business-friendly data model layer enabling natural language analytics |
| | Data Metric Functions | Quality monitoring — freshness, null counts, custom business rule validation |
| **Data Engineering** | Dynamic Tables | Continuous AI-powered extraction pipelines with automatic refresh |
| | Git Integration | Source-controlled SQL deployment directly from GitHub repository stage |
| | Snowflake Notebooks | Interactive development of AISQL multimodal pipelines |
| | Presigned URLs | Secure, time-limited image URLs for product media served to external frontends |
| **Transactions** | Hybrid Tables | Low-latency OLTP for cart, orders, payments with ACID guarantees |
| **Apps & Collaboration** | Streamlit | Interactive dashboards for executive-facing experiences |



## Solution Walkthrough

### Scene 1: Agentic Commerce on the Merchant's Website

The Beauty Advisor Chatbot is powered by the Product 360 Data Agent on Snowflake Cortex. Open the chatbot URL and run these prompts in sequence:

| # | Prompt | Showcases |
|---|--------|-----------|
| 1 | *Can you recommend face products for my oily skin with warm undertone* | Cortex Agent → Cortex Analyst over Semantic Views for personalized product discovery |
| 2 | *Compare these 2 foundations — Summer Fridays Luxe Foundation and Drunk Elephant Pro Foundation* | Multi-tool orchestration within a single agent turn |
| 3 | *How are the reviews for Summer Fridays Luxe Foundation on your website* | Cortex Search + Cortex Analyst for social proof retrieval |
| 4 | *Do you have it in stock?* | Conversational context + Inventory Semantic View query |
| 5 | *Add it to my cart and checkout* | Full cart-to-checkout via Hybrid Tables (ACID-compliant, sub-second) |

### Scene 2: Agentic Commerce via ChatGPT

The same Product 360 Data Agent is exposed via MCP Server. Open ChatGPT with the MCP connection and run the same prompts from Scene 1 — demonstrating identical product discovery and conversion across any AI platform.

### Scene 3: Under the Hood — Building Blocks

Walk through the Snowflake objects powering the agent:

1. **Semantic Views** — Open `sql/07_create_semantic_views.sql` and show the 5 semantic views (Product, Social, Cart, Customer, Inventory) that give Cortex Analyst a business-friendly data model
2. **Cortex Search** — Show the 3 search services (Product, Label, Social) with INCREMENTAL refresh in `sql/06_create_cortex_search.sql`
3. **Data Quality (Horizon)** — Show Data Metric Functions (FRESHNESS, NULL_COUNT, ROW_COUNT, custom COST_EXCEEDS_PRICE) attached to the products table in `sql/10_setup_dmfs.sql`

### Scene 3b: Unstructured Data — Notebook Walkthrough with AI SQL

Open the notebook `NRFDEMO_MULTIMODAL_PROCESSING` in Snowsight and walk through it:

1. **AI_COMPLETE with TO_FILE** — Show how `claude-opus-4-6` extracts structured JSON (brand, warnings, ingredients) from a product label image using AI SQL
2. **Dynamic Table** — Show `PRODUCT_LABEL_EXTRACT` which continuously processes all 2,000+ labels on a 5-min refresh using the same AI_COMPLETE pattern
3. **Cortex Search over extracted content** — Show how the extracted ingredients feed into `LABEL_SEARCH_SERVICE`, then prompt the chatbot (or ChatGPT): *"List the ingredients and any warnings I should be aware of for Summer Fridays Luxe Foundation"*

### Scene 4: AI for Agentic Commerce Analytics

Open Snowflake Intelligence connected to the Executive Product 360 Data Agent. Run these prompts:

| # | Prompt | Showcases |
|---|--------|-----------|
| 1 | *What are my top products in past 6 months?* | Cortex Analyst text-to-SQL over Product + Checkout Semantic Views |
| 2 | *Why am I doing better in lip than others?* | Cross-tool analysis spanning Product, Social, and Checkout data |
| 3 | *What has been my stock levels across non lip products?* | Inventory Semantic View filtering |
| 4 | *Summarize the findings and send email to cdo@operations.com* | Agent-triggered email delivery via custom UDF |

### Scene 5: AI for Rapid Development

Show how a developer uses Cortex Code to rapidly extend the Executive Product 360 Agent with an external macroeconomics dataset.

1. Switch Cortex Code to **Plan mode**
2. Enter this prompt:

> Integrate the provided macroeconomics data from marketplace to my executive 360 Cortex agent. Share your plan
> https://app.snowflake.com/marketplace/listing/GZTSZ290BV255/snowflake-public-data-products-snowflake-public-data-free

3. CoCo will generate a plan covering all dependencies — marketplace data acquisition, semantic view creation, and agent tool integration
4. Approve the plan and let CoCo execute it end-to-end
5. Switch to Snowflake Intelligence and ask: *"How are macro trends impacting my beauty sales?"*

## Prerequisites

- **Snowflake account** with ACCOUNTADMIN role
- **Cross-region inference** enabled (`CORTEX_ENABLED_CROSS_REGION = 'ANY_REGION'`) — required for the `claude-opus-4-6` model used by agents, Dynamic Table AI extraction, and face analysis
- **Docker Desktop** installed and running (for SPCS backend)
- **Snowflake CLI** (`snow`) installed
- **No Docker Hub account needed** - images are built locally and pushed directly to Snowflake registry

## Quick Start (CoCo Deployment)

The recommended deployment method is via Cortex Code (CoCo).

**1. Download the skill (one-time):**

```bash
mkdir -p ~/.snowflake/cortex/skills/deploy_agent_commerce_beauty_advisor
curl -sL https://raw.githubusercontent.com/sfc-gh-amgupta/agent_commerce_beauty_advisor_v2/main/.snowflake/cortex/skills/deploy_agent_commerce_beauty_advisor/SKILL.md \
  -o ~/.snowflake/cortex/skills/deploy_agent_commerce_beauty_advisor/SKILL.md
```

**2. Invoke in CoCo:**

```
/deploy_agent_commerce_beauty_advisor
```

This handles all deployment steps automatically — SQL execution, Docker image build/push, object verification, and agent testing.

## Manual Deployment

### Step 1: Set up Git Repository Integration

```sql
-- Run sql/01_setup_infrastructure.sql
-- Creates: database, schemas, warehouse, roles, stages, git repo integration
```

### Step 2: Create Tables

```sql
-- Run sql/02_create_tables.sql
-- Creates: 23 tables across 5 schemas (including 7 hybrid tables in CART_OLTP)
```

### Step 3: Load Data

```sql
-- Run sql/03_load_data.sql
-- Loads CSVs from @UTIL.AGENT_COMMERCE_GIT/branches/main/data/csv/
-- Loads images from git repo into stage directories
-- Runs skin_type_compatibility derivation algorithm
```

### Step 4: Create Views

```sql
-- Run sql/04_create_views.sql
```

### Step 5: Create UDFs and Procedures

```sql
-- Run sql/05_create_udfs_procedures.sql
-- Creates: face analysis tools, color matching, cart operations, email sender
```

### Step 6: Create Cortex Search Services

```sql
-- Run sql/06_create_cortex_search.sql
-- Creates: PRODUCT_SEARCH_SERVICE, LABEL_SEARCH_SERVICE, SOCIAL_SEARCH_SERVICE
-- All use INCREMENTAL refresh mode
```

### Step 7: Create Semantic Views

```sql
-- Run sql/07_create_semantic_views.sql
-- Creates: 5 semantic views (PRODUCT, SOCIAL_PROOF, CART, CUSTOMER, INVENTORY)
-- PRODUCT and SOCIAL_PROOF include ["CA"] extension
```

### Step 8: Create Agents

```sql
-- Run sql/08_create_agents.sql
-- Creates:
--   AGENTIC_COMMERCE_ASSISTANT (Beauty Advisor - 17 tools)
--   EXECUTIVE_PRODUCT_360 (Executive analytics - 6 tools)
--   AGENTIC_COMMERCE_MCP_SERVER (wraps Beauty Advisor)
--   EXECUTIVE_PRODUCT_360 Streamlit app
```

### Step 9: Deploy SPCS Backend

```bash
# Build Docker image from repo source
docker build --platform linux/amd64 -t agent-commerce-backend:latest ./backend

# Login to Snowflake image registry (no Docker Hub needed)
snow spcs image-registry login

# Tag and push
REPO_URL=$(snow spcs image-repository url AGENT_COMMERCE.UTIL.IMAGE_REPOSITORY)
docker tag agent-commerce-backend:latest $REPO_URL/agent-commerce-backend:latest
docker push $REPO_URL/agent-commerce-backend:latest

# Create compute pool and service
-- Run sql/09_deploy_spcs.sql
```

### Step 10: Set up Data Metric Functions

```sql
-- Run sql/10_setup_dmfs.sql
-- Creates: COST_EXCEEDS_PRICE custom DMF
-- Attaches: FRESHNESS, NULL_COUNT, ROW_COUNT built-in DMFs
```

### Cleanup

```sql
-- Run sql/99_cleanup.sql
-- Drops: database, warehouse, role, compute pool
```

## Object Inventory

| Category | Object | Schema | Type |
|----------|--------|--------|------|
| **Database** | AGENT_COMMERCE | - | DATABASE |
| **Schemas** | PRODUCTS, SOCIAL, INVENTORY, CUSTOMERS, CART_OLTP, UTIL, PUBLIC | - | SCHEMA |
| **Warehouse** | AGENT_COMMERCE_WH | - | X-SMALL |
| **Tables** | PRODUCTS, PRODUCT_VARIANTS, PRODUCT_MEDIA, PRODUCT_LABELS, PRODUCT_INGREDIENTS, PRODUCT_WARNINGS, PRICE_HISTORY, PROMOTIONS | PRODUCTS | TABLE |
| | PRODUCT_REVIEWS, SOCIAL_MENTIONS, INFLUENCER_MENTIONS, SOCIAL_ENGAGEMENT_SUMMARY | SOCIAL | TABLE |
| | LOCATIONS, STOCK_LEVELS, INVENTORY_TRANSACTIONS | INVENTORY | TABLE |
| | CUSTOMERS, SKIN_ANALYSIS_HISTORY | CUSTOMERS | TABLE |
| | CART_SESSIONS, CART_ITEMS, ORDERS, ORDER_ITEMS, PAYMENT_METHODS, PAYMENT_TRANSACTIONS, FULFILLMENT_OPTIONS | CART_OLTP | HYBRID TABLE |
| **Dynamic Table** | PRODUCT_LABEL_EXTRACT | PRODUCTS | 5-min FULL refresh |
| **Views** | PRODUCT_CATALOG_VIEW, PRODUCT_LABEL_VIEW | PRODUCTS | VIEW |
| | SOCIAL_PROOF_VIEW | SOCIAL | VIEW |
| **Semantic Views** | PRODUCT_SEMANTIC_VIEW | PRODUCTS | SEMANTIC VIEW |
| | SOCIAL_PROOF_SEMANTIC_VIEW | SOCIAL | SEMANTIC VIEW |
| | CART_SEMANTIC_VIEW | CART_OLTP | SEMANTIC VIEW |
| | CUSTOMER_SEMANTIC_VIEW | CUSTOMERS | SEMANTIC VIEW |
| | INVENTORY_SEMANTIC_VIEW | INVENTORY | SEMANTIC VIEW |
| **Cortex Search** | PRODUCT_SEARCH_SERVICE, LABEL_SEARCH_SERVICE | PRODUCTS | CORTEX SEARCH |
| | SOCIAL_SEARCH_SERVICE | SOCIAL | CORTEX SEARCH |
| **Cortex Agents** | AGENTIC_COMMERCE_ASSISTANT (Beauty Advisor) | UTIL | AGENT (17 tools) |
| | EXECUTIVE_PRODUCT_360 | UTIL | AGENT (6 tools) |
| **MCP Server** | AGENTIC_COMMERCE_MCP_SERVER | UTIL | MCP SERVER |
| **Streamlit** | EXECUTIVE_PRODUCT_360 | UTIL | STREAMLIT |
| **Notebook** | NRFDEMO_MULTIMODAL_PROCESSING | UTIL | NOTEBOOK |
| **SPCS** | AGENT_COMMERCE_BACKEND | UTIL | SERVICE |
| | AGENT_COMMERCE_POOL | - | COMPUTE POOL |
| **DMFs** | COST_EXCEEDS_PRICE (custom) + FRESHNESS, NULL_COUNT, ROW_COUNT (built-in) | PRODUCTS | DMF |
| **Stages** | PRODUCT_LABELS_STAGE, PRODUCT_MEDIA_STAGE | PRODUCTS | STAGE |
| | FACE_IMAGES_STAGE | CUSTOMERS | STAGE |
| | EXECUTIVE_360_STAGE, CSV_DATA_STAGE | UTIL | STAGE |

## Stage Architecture

This demo uses a **two-stage design** for product label images:

| Stage | Contents | Purpose |
|-------|----------|---------|
| `PRODUCTS.PRODUCT_LABELS_STAGE` | 2,001 unique PNGs | Source for AI extraction via Dynamic Table (`AI_COMPLETE('claude-opus-4-6', ...)`) |
| `PRODUCTS.PRODUCT_MEDIA_STAGE/labels/` | 2,000 PNGs | URL references for `GetLabelURL` tool (presigned URLs for chat display) |

The `GetLabelURL` UDF generates presigned URLs from `PRODUCT_MEDIA_STAGE` paths, not `PRODUCT_LABELS_STAGE`. This is intentional — the media stage paths are stored in the `PRODUCT_MEDIA` table's `label_image_url` column and referenced by Cortex Search results.

## Docker Requirements

- **Docker Desktop** must be installed and the daemon running
- **No Docker Hub account required** - the image is built locally from the `backend/` directory
- Authentication to Snowflake's image registry uses `snow spcs image-registry login` (authenticates via your active Snowflake connection)
- The backend is a FastAPI service that handles face analysis (skin tone, undertone, face embeddings)

## Test Questions

### Beauty Advisor Agent (AGENTIC_COMMERCE_ASSISTANT)

| # | Question | Tests |
|---|----------|-------|
| 1 | Can you recommend face products for my oily skin with warm undertone | ProductAnalyst semantic view query with skin_type filter |
| 2 | Compare these 2 foundations for me - Summer Fridays Luxe Foundation and Drunk Elephant Pro Foundation | Multi-product lookup and comparison |
| 3 | How are the reviews for Summer Fridays Luxe Foundation on your website | SocialSearch / SocialAnalyst |
| 4 | Do you have it in stock? | InventoryAnalyst follow-up context |
| 5 | Add it to my cart and checkout | ACP cart flow: CreateCart, AddItem, Checkout |
| 6 | List the ingredients and any warnings I should be aware of for Summer Fridays Luxe Foundation | LabelSearch + GetLabelURL |

### Executive Product 360 Agent (EXECUTIVE_PRODUCT_360)

| # | Question | Tests |
|---|----------|-------|
| 1 | What are my top products in past 6 months | ProductAnalyst + CheckoutAnalyst |
| 2 | Why am I doing better in lip than others? | Cross-tool analysis (Product + Social + Checkout) |
| 3 | What has been my stock levels across non lip products | InventoryAnalyst filtering |
| 4 | Summarize the findings and send email to cdo@operations.com | EmailSender tool |

## Repository Structure

```
agent_commerce_beauty_advisor_v2/
├── LICENSE
├── README.md
├── .gitattributes              # Git LFS tracking for images
├── backend/
│   ├── Dockerfile              # Multi-stage build, linux/amd64
│   ├── requirements-final.txt  # Python dependencies
│   └── app/
│       ├── __init__.py
│       └── main.py             # FastAPI backend (face analysis)
├── data/
│   ├── csv/                    # 23 CSV files (all table data)
│   ├── face_images/            # 200 customer face JPGs
│   ├── product_labels/         # 2,002 product label PNGs (AI source)
│   ├── product_media/
│   │   └── labels/             # 2,000 product label PNGs (URL refs)
│   └── streamlit/
│       └── executive_product_360.py
├── notebooks/
│   └── NRFDEMO_MULTIMODAL_PROCESSING.ipynb
└── sql/
    ├── 01_setup_infrastructure.sql
    ├── 02_create_tables.sql
    ├── 03_load_data.sql
    ├── 04_create_views.sql
    ├── 05_create_udfs_procedures.sql
    ├── 06_create_cortex_search.sql
    ├── 07_create_semantic_views.sql
    ├── 08_create_agents.sql
    ├── 09_deploy_spcs.sql
    ├── 10_setup_dmfs.sql
    └── 99_cleanup.sql
```

## Data Summary

| Schema | Table | Rows |
|--------|-------|------|
| PRODUCTS | PRODUCTS | ~2,000 |
| PRODUCTS | PRODUCT_VARIANTS | ~8,000 |
| PRODUCTS | PRODUCT_MEDIA | ~10,000 |
| PRODUCTS | PRODUCT_LABELS | ~2,000 |
| PRODUCTS | PRODUCT_INGREDIENTS | ~28,000 |
| PRODUCTS | PRODUCT_WARNINGS | ~4,000 |
| PRODUCTS | PRICE_HISTORY | ~20,000 |
| PRODUCTS | PROMOTIONS | ~355 |
| SOCIAL | PRODUCT_REVIEWS | ~19,000 |
| SOCIAL | SOCIAL_MENTIONS | ~19,000 |
| SOCIAL | INFLUENCER_MENTIONS | ~33,000 |
| INVENTORY | LOCATIONS | ~125 |
| INVENTORY | STOCK_LEVELS | ~20,000 |
| INVENTORY | INVENTORY_TRANSACTIONS | ~37,000 |
| CUSTOMERS | CUSTOMERS | ~26,000 |
| CUSTOMERS | SKIN_ANALYSIS_HISTORY | ~67,000 |
| CART_OLTP | CART_SESSIONS | ~2,000 |
| CART_OLTP | CART_ITEMS | ~5,000 |
| CART_OLTP | ORDERS | ~827 |
| CART_OLTP | ORDER_ITEMS | ~2,080 |
| CART_OLTP | PAYMENT_METHODS | ~1,025 |
| CART_OLTP | PAYMENT_TRANSACTIONS | ~823 |
| CART_OLTP | FULFILLMENT_OPTIONS | 6 |

## Key Features

- **Face Analysis**: Upload a photo to get skin tone, undertone, and personalized product recommendations
- **Customer Identification**: Face embedding matching to identify returning customers (privacy-first verification flow)
- **Color Matching**: Find products matching customer's skin tone using color distance algorithm
- **Label Intelligence**: AI-extracted ingredient and warning data from 2,000+ product labels via Dynamic Table + Claude
- **Cortex Search**: Semantic search across products, labels, and social content
- **ACP-Compliant Checkout**: Full cart lifecycle (create, add, update, remove, checkout) via hybrid tables
- **Executive Analytics**: Cross-domain analytics with email reporting via Streamlit dashboard
- **MCP Server**: Expose Beauty Advisor as an MCP tool for integration with other agents

## Notebook

`NRFDEMO_MULTIMODAL_PROCESSING.ipynb` demonstrates the AISQL pipeline:
1. `AI_COMPLETE` with `claude-opus-4-6` to extract text from product label images
2. `TO_FILE` to write extracted text back to stage
3. Dynamic Table (`PRODUCT_LABEL_EXTRACT`) for continuous processing
4. Cortex Search Service for semantic search over extracted content
5. Cortex Agent integration for end-to-end retrieval
