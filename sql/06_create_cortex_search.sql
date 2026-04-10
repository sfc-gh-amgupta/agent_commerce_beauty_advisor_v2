USE ROLE AGENT_COMMERCE_ROLE;
USE DATABASE AGENT_COMMERCE;
USE WAREHOUSE AGENT_COMMERCE_WH;

-- ============================================================
-- Cortex Search Services
-- ============================================================

CREATE OR REPLACE CORTEX SEARCH SERVICE PRODUCTS.PRODUCT_SEARCH_SERVICE
    ON CONTENT
    ATTRIBUTES CONTENT_TYPE, ID, PRODUCT_ID, TITLE, BRAND, CATEGORY, SUBCATEGORY, COLOR_NAME, FINISH, CURRENT_PRICE, IS_VEGAN, IS_CRUELTY_FREE, SOURCE_IMAGE_URL, SEVERITY
    WAREHOUSE = 'AGENT_COMMERCE_WH'
    TARGET_LAG = '1 hour'
    COMMENT = 'Unified search across products, labels, ingredients, and warnings'
    REFRESH_MODE = INCREMENTAL
    AS (
        SELECT
            content_type,
            id,
            product_id,
            title,
            content,
            brand,
            category,
            subcategory,
            color_name,
            finish,
            current_price,
            is_vegan,
            is_cruelty_free,
            source_image_url,
            severity
        FROM PRODUCTS.PRODUCT_SEARCH_CONTENT
    );

CREATE OR REPLACE CORTEX SEARCH SERVICE PRODUCTS.LABEL_SEARCH_SERVICE
    ON CONTENT
    ATTRIBUTES CONTENT_TYPE, ID, PRODUCT_ID, PRODUCT_NAME, TITLE, BRAND, CATEGORY, SUBCATEGORY, IS_ALLERGEN, ALLERGEN_TYPE, CURRENT_PRICE, IS_VEGAN, IS_CRUELTY_FREE, LABEL_IMAGE_URL, SEVERITY
    WAREHOUSE = 'AGENT_COMMERCE_WH'
    TARGET_LAG = '1 hour'
    COMMENT = 'Focused search for product label content. Title field contains embedded label_image_url for agent extraction.'
    REFRESH_MODE = INCREMENTAL
    AS (
        SELECT
            content_type,
            id,
            product_id,
            product_name,
            title,
            content,
            brand,
            category,
            subcategory,
            is_allergen,
            allergen_type,
            current_price,
            is_vegan,
            is_cruelty_free,
            label_image_url,
            severity
        FROM PRODUCTS.LABEL_SEARCH_CONTENT
    );

CREATE OR REPLACE CORTEX SEARCH SERVICE SOCIAL.SOCIAL_SEARCH_SERVICE
    ON CONTENT
    ATTRIBUTES CONTENT_TYPE, ID, PRODUCT_ID, TITLE, URL, AUTHOR_HANDLE, AUTHOR_NAME, PLATFORM, RATING, ENGAGEMENT_SCORE, VERIFIED_PURCHASE, SKIN_TONE, SKIN_TYPE, UNDERTONE, SENTIMENT_LABEL, IS_SPONSORED, POSTED_AT
    WAREHOUSE = 'AGENT_COMMERCE_WH'
    TARGET_LAG = '1 hour'
    COMMENT = 'Unified search across reviews, social mentions, and influencer content'
    REFRESH_MODE = INCREMENTAL
    AS (
        SELECT
            content_type, id, product_id, title, content, url,
            author_handle, author_name, platform, rating, engagement_score,
            verified_purchase, skin_tone, skin_type, undertone,
            sentiment_label, is_sponsored, posted_at
        FROM SOCIAL.SOCIAL_SEARCH_CONTENT
    );

-- ============================================================
-- Dynamic Table for Product Label Extraction
-- ============================================================

CREATE OR REPLACE DYNAMIC TABLE PRODUCTS.PRODUCT_LABEL_EXTRACT(
    FILE_PATH,
    SKU,
    BRAND,
    PRODUCT_NAME,
    NET_WEIGHT,
    SPF,
    WARNINGS,
    DIRECTIONS,
    OTHER_INFORMATION,
    INACTIVE_INGREDIENTS,
    RAW_JSON
) TARGET_LAG = '5 minutes' REFRESH_MODE = FULL INITIALIZE = ON_CREATE WAREHOUSE = AGENT_COMMERCE_WH
AS
WITH raw_extraction AS (
    SELECT
        f.FILE_PATH,
        SPLIT_PART(REPLACE(REPLACE(f.FILE_PATH, '.png', ''), '.jpeg', ''), '_', 1) AS SKU,
        AI_COMPLETE(
            'gemini-2.0-flash',
            'Extract ALL information from this cosmetic Drug Facts label. Return ONLY a JSON object:
{
  "brand": "",
  "product_name": "",
  "net_weight": "",
  "spf": "",
  "warnings": [],
  "directions": [],
  "other_information": [],
  "inactive_ingredients": []
}
Include ALL text from Warnings, Directions, and Other Information sections.
Read ONLY what is printed. Do not add ingredients not visible on label.',
            TO_FILE('@AGENT_COMMERCE.PRODUCTS.PRODUCT_LABELS_STAGE', f.FILE_PATH)
        ) AS RAW_RESULT
    FROM AGENT_COMMERCE.PRODUCTS.PRODUCT_LABEL_FILES f
),
parsed AS (
    SELECT
        FILE_PATH,
        SKU,
        RAW_RESULT,
        TRY_PARSE_JSON(REGEXP_SUBSTR(RAW_RESULT, '\\{.*\\}', 1, 1, 's')) AS DATA
    FROM raw_extraction
)
SELECT
    FILE_PATH,
    SKU,
    DATA:brand::VARCHAR AS BRAND,
    DATA:product_name::VARCHAR AS PRODUCT_NAME,
    DATA:net_weight::VARCHAR AS NET_WEIGHT,
    DATA:spf::VARCHAR AS SPF,
    ARRAY_TO_STRING(DATA:warnings, ' | ') AS WARNINGS,
    ARRAY_TO_STRING(DATA:directions, ' | ') AS DIRECTIONS,
    ARRAY_TO_STRING(DATA:other_information, ' | ') AS OTHER_INFORMATION,
    ARRAY_TO_STRING(DATA:inactive_ingredients, ' | ') AS INACTIVE_INGREDIENTS,
    DATA AS RAW_JSON
FROM parsed;
