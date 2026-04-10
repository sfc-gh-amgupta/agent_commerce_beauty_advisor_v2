USE ROLE AGENT_COMMERCE_ROLE;
USE DATABASE AGENT_COMMERCE;
USE WAREHOUSE AGENT_COMMERCE_WH;

-- ============================================================
-- CUSTOMERS schema UDFs and Procedures
-- ============================================================
USE SCHEMA CUSTOMERS;

CREATE OR REPLACE PROCEDURE "CHECK_CUSTOMER_EXISTS"("QUERY_EMBEDDING_ARRAY" ARRAY, "THRESHOLD" FLOAT DEFAULT 0.85)
RETURNS OBJECT
LANGUAGE SQL
EXECUTE AS OWNER
AS 'DECLARE
    v_result OBJECT;
    v_customer_id VARCHAR;
    v_first_name VARCHAR;
    v_last_name VARCHAR;
    v_similarity FLOAT;
    v_confidence VARCHAR;
    v_found BOOLEAN DEFAULT FALSE;
BEGIN
    SELECT
        c.customer_id,
        c.first_name,
        c.last_name,
        VECTOR_COSINE_SIMILARITY(e.embedding, :query_embedding_array::VECTOR(FLOAT, 128)) AS similarity_score,
        CASE
            WHEN VECTOR_COSINE_SIMILARITY(e.embedding, :query_embedding_array::VECTOR(FLOAT, 128)) >= 0.95 THEN ''HIGH''
            WHEN VECTOR_COSINE_SIMILARITY(e.embedding, :query_embedding_array::VECTOR(FLOAT, 128)) >= 0.85 THEN ''MEDIUM''
            WHEN VECTOR_COSINE_SIMILARITY(e.embedding, :query_embedding_array::VECTOR(FLOAT, 128)) >= 0.70 THEN ''LOW''
            ELSE ''NONE''
        END AS confidence_level
    INTO :v_customer_id, :v_first_name, :v_last_name, :v_similarity, :v_confidence
    FROM CUSTOMER_FACE_EMBEDDINGS e
    JOIN CUSTOMERS c ON e.customer_id = c.customer_id
    WHERE e.is_active = TRUE
      AND c.is_active = TRUE
    ORDER BY similarity_score DESC
    LIMIT 1;

    IF (v_similarity IS NOT NULL AND v_similarity >= threshold) THEN
        v_found := TRUE;
    END IF;

    v_result := OBJECT_CONSTRUCT(
        ''found'', v_found,
        ''customer_id'', v_customer_id,
        ''first_name'', v_first_name,
        ''last_name'', v_last_name,
        ''similarity_score'', v_similarity,
        ''confidence_level'', v_confidence
    );

    RETURN v_result;
EXCEPTION
    WHEN OTHER THEN
        RETURN OBJECT_CONSTRUCT(
            ''found'', FALSE,
            ''customer_id'', NULL,
            ''similarity_score'', NULL,
            ''confidence_level'', ''NONE'',
            ''error'', SQLERRM
        );
END';

CREATE OR REPLACE PROCEDURE "DEACTIVATE_ALL_CUSTOMER_EMBEDDINGS"("P_CUSTOMER_ID" VARCHAR)
RETURNS OBJECT
LANGUAGE SQL
EXECUTE AS OWNER
AS 'DECLARE
    v_count INTEGER;
BEGIN
    UPDATE CUSTOMER_FACE_EMBEDDINGS
    SET is_active = FALSE
    WHERE customer_id = :p_customer_id;

    SELECT COUNT(*) INTO v_count
    FROM CUSTOMER_FACE_EMBEDDINGS
    WHERE customer_id = :p_customer_id AND is_active = FALSE;

    RETURN OBJECT_CONSTRUCT(
        ''success'', TRUE,
        ''customer_id'', p_customer_id,
        ''embeddings_deactivated'', v_count
    );
END';

CREATE OR REPLACE PROCEDURE "DEACTIVATE_FACE_EMBEDDING"("P_EMBEDDING_ID" VARCHAR)
RETURNS OBJECT
LANGUAGE SQL
EXECUTE AS OWNER
AS 'BEGIN
    UPDATE CUSTOMER_FACE_EMBEDDINGS
    SET is_active = FALSE
    WHERE embedding_id = :p_embedding_id;

    RETURN OBJECT_CONSTRUCT(
        ''success'', TRUE,
        ''embedding_id'', p_embedding_id,
        ''action'', ''deactivated''
    );
END';

CREATE OR REPLACE FUNCTION "EXTRACT_EMBEDDING_VIA_SPCS"("IMAGE_BASE64" VARCHAR)
RETURNS VARIANT
LANGUAGE PYTHON
RUNTIME_VERSION = '3.10'
PACKAGES = ('snowflake-snowpark-python','requests')
HANDLER = 'extract_embedding'
AS '
import json

def extract_embedding(image_base64):
    # For now, return a placeholder embedding
    # In production, this would call the SPCS endpoint

    if image_base64.startswith("ERROR:"):
        return {"success": False, "error": image_base64}

    # Generate a deterministic pseudo-embedding based on image hash
    import hashlib
    hash_val = hashlib.md5(image_base64.encode()).hexdigest()

    # Create 128-dim embedding from hash
    embedding = []
    for i in range(0, 32, 1):
        val = int(hash_val[i], 16) / 15.0 - 0.5
        embedding.extend([val, val * 0.9, val * 0.8, val * 0.7])

    return {
        "success": True,
        "embedding": embedding[:128],
        "quality_score": 0.85
    }
';

CREATE OR REPLACE PROCEDURE "FIND_CUSTOMER_BY_FACE"("QUERY_EMBEDDING_ARRAY" ARRAY, "SIMILARITY_THRESHOLD" FLOAT DEFAULT 0.7, "MAX_RESULTS" NUMBER(38,0) DEFAULT 5)
RETURNS TABLE ("CUSTOMER_ID" VARCHAR, "EMAIL" VARCHAR, "FIRST_NAME" VARCHAR, "LAST_NAME" VARCHAR, "LOYALTY_TIER" VARCHAR, "SIMILARITY_SCORE" FLOAT, "CONFIDENCE_LEVEL" VARCHAR)
LANGUAGE SQL
EXECUTE AS OWNER
AS 'DECLARE
    res RESULTSET;
BEGIN
    res := (
        SELECT
            c.customer_id,
            c.email,
            c.first_name,
            c.last_name,
            c.loyalty_tier,
            VECTOR_COSINE_SIMILARITY(e.embedding, :query_embedding_array::VECTOR(FLOAT, 128)) AS similarity_score,
            CASE
                WHEN VECTOR_COSINE_SIMILARITY(e.embedding, :query_embedding_array::VECTOR(FLOAT, 128)) >= 0.95 THEN ''HIGH''
                WHEN VECTOR_COSINE_SIMILARITY(e.embedding, :query_embedding_array::VECTOR(FLOAT, 128)) >= 0.85 THEN ''MEDIUM''
                WHEN VECTOR_COSINE_SIMILARITY(e.embedding, :query_embedding_array::VECTOR(FLOAT, 128)) >= 0.70 THEN ''LOW''
                ELSE ''NONE''
            END AS confidence_level
        FROM CUSTOMER_FACE_EMBEDDINGS e
        JOIN CUSTOMERS c ON e.customer_id = c.customer_id
        WHERE e.is_active = TRUE
          AND c.is_active = TRUE
          AND VECTOR_COSINE_SIMILARITY(e.embedding, :query_embedding_array::VECTOR(FLOAT, 128)) >= :similarity_threshold
        ORDER BY similarity_score DESC
        LIMIT :max_results
    );
    RETURN TABLE(res);
END';

CREATE OR REPLACE PROCEDURE "FIND_SIMILAR_CUSTOMERS"("SOURCE_CUSTOMER_ID" VARCHAR, "SIMILARITY_THRESHOLD" FLOAT DEFAULT 0.8, "MAX_RESULTS" NUMBER(38,0) DEFAULT 10)
RETURNS TABLE ("CUSTOMER_ID" VARCHAR, "EMAIL" VARCHAR, "FIRST_NAME" VARCHAR, "LAST_NAME" VARCHAR, "SIMILARITY_SCORE" FLOAT)
LANGUAGE SQL
EXECUTE AS OWNER
AS 'DECLARE
    res RESULTSET;
BEGIN
    res := (
        WITH source_embedding AS (
            SELECT embedding
            FROM CUSTOMER_FACE_EMBEDDINGS
            WHERE customer_id = :source_customer_id
              AND is_active = TRUE
              AND is_primary = TRUE
            LIMIT 1
        )
        SELECT
            c.customer_id,
            c.email,
            c.first_name,
            c.last_name,
            VECTOR_COSINE_SIMILARITY(e.embedding, se.embedding) AS similarity_score
        FROM CUSTOMER_FACE_EMBEDDINGS e
        JOIN CUSTOMERS c ON e.customer_id = c.customer_id
        CROSS JOIN source_embedding se
        WHERE e.is_active = TRUE
          AND c.is_active = TRUE
          AND c.customer_id != :source_customer_id
          AND VECTOR_COSINE_SIMILARITY(e.embedding, se.embedding) >= :similarity_threshold
        ORDER BY similarity_score DESC
        LIMIT :max_results
    );
    RETURN TABLE(res);
END';

CREATE OR REPLACE FUNCTION "READ_STAGE_IMAGE_BASE64"("SCOPED_FILE_URL" VARCHAR)
RETURNS VARCHAR
LANGUAGE PYTHON
RUNTIME_VERSION = '3.10'
PACKAGES = ('snowflake-snowpark-python')
HANDLER = 'read_image_base64'
AS '
import base64
from snowflake.snowpark.files import SnowflakeFile

def read_image_base64(scoped_file_url):
    try:
        with SnowflakeFile.open(scoped_file_url, ''rb'') as f:
            image_bytes = f.read()
            return base64.b64encode(image_bytes).decode(''utf-8'')
    except Exception as e:
        return f"ERROR:{str(e)}"
';

CREATE OR REPLACE PROCEDURE "REGISTER_FACE_EMBEDDING"("P_CUSTOMER_ID" VARCHAR, "P_EMBEDDING_ARRAY" ARRAY, "P_QUALITY_SCORE" FLOAT DEFAULT null, "P_LIGHTING_CONDITION" VARCHAR DEFAULT null, "P_FACE_ANGLE" VARCHAR DEFAULT null, "P_SOURCE" VARCHAR DEFAULT 'widget_camera')
RETURNS OBJECT
LANGUAGE SQL
EXECUTE AS OWNER
AS 'DECLARE
    v_embedding_id VARCHAR;
    v_customer_exists BOOLEAN;
BEGIN
    SELECT COUNT(*) > 0 INTO v_customer_exists
    FROM CUSTOMERS
    WHERE customer_id = :p_customer_id AND is_active = TRUE;

    IF (NOT v_customer_exists) THEN
        RETURN OBJECT_CONSTRUCT(
            ''success'', FALSE,
            ''error'', ''Customer not found or inactive''
        );
    END IF;

    v_embedding_id := UUID_STRING();

    INSERT INTO CUSTOMER_FACE_EMBEDDINGS (
        embedding_id,
        customer_id,
        embedding,
        quality_score,
        lighting_condition,
        face_angle,
        is_active,
        is_primary,
        source,
        created_at
    ) VALUES (
        :v_embedding_id,
        :p_customer_id,
        :p_embedding_array::VECTOR(FLOAT, 128),
        :p_quality_score,
        :p_lighting_condition,
        :p_face_angle,
        TRUE,
        FALSE,
        :p_source,
        CURRENT_TIMESTAMP()
    );

    RETURN OBJECT_CONSTRUCT(
        ''success'', TRUE,
        ''embedding_id'', v_embedding_id,
        ''customer_id'', p_customer_id
    );
END';

CREATE OR REPLACE FUNCTION "TOOL_ANALYZE_FACE"("IMAGE_BASE64" VARCHAR)
RETURNS VARIANT
LANGUAGE SQL
AS '
    SELECT PARSE_JSON(
        UTIL.ML_FACE_ANALYSIS_SERVICE!PREDICT(
            REPLACE(REPLACE(image_base64, CHR(34), ''''), CHR(39), '''')
        ):"output_feature_0"::VARCHAR
    )
';

CREATE OR REPLACE FUNCTION "TOOL_IDENTIFY_CUSTOMER"("QUERY_EMBEDDING_JSON" VARCHAR, "MATCH_THRESHOLD" FLOAT DEFAULT 0.55, "MAX_RESULTS" NUMBER(38,0) DEFAULT 5)
RETURNS OBJECT
LANGUAGE SQL
COMMENT='Identify customer by matching face embedding using dlib industry-standard L2 distance thresholds. Returns match_level: high (<0.4), medium (0.4-0.55), or none (>=0.55). Only high/medium matches should trigger customer verification.'
AS '
    SELECT OBJECT_CONSTRUCT(
        ''success'', TRUE,
        ''matches'', COALESCE(ARRAY_AGG(
            OBJECT_CONSTRUCT(
                ''customer_id'', customer_id,
                ''first_name'', first_name,
                ''last_name'', last_name,
                ''email'', email,
                ''loyalty_tier'', loyalty_tier,
                ''points_balance'', points_balance,
                ''distance'', distance,
                ''match_level'', match_level
            )
        ), ARRAY_CONSTRUCT())
    )
    FROM (
        SELECT
            c.customer_id,
            c.first_name,
            c.last_name,
            c.email,
            c.loyalty_tier,
            c.points_balance,
            ROUND(VECTOR_L2_DISTANCE(
                e.embedding,
                PARSE_JSON(query_embedding_json)::VECTOR(FLOAT, 128)
            ), 4) AS distance,
            CASE
                WHEN VECTOR_L2_DISTANCE(e.embedding, PARSE_JSON(query_embedding_json)::VECTOR(FLOAT, 128)) < 0.40 THEN ''high''
                WHEN VECTOR_L2_DISTANCE(e.embedding, PARSE_JSON(query_embedding_json)::VECTOR(FLOAT, 128)) < 0.55 THEN ''medium''
                ELSE ''none''
            END AS match_level
        FROM CUSTOMERS.CUSTOMER_FACE_EMBEDDINGS e
        JOIN CUSTOMERS.CUSTOMERS c ON e.customer_id = c.customer_id
        WHERE e.is_primary = TRUE
        ORDER BY distance ASC
        LIMIT 5
    )
';

-- ============================================================
-- PRODUCTS schema UDFs and Procedures
-- ============================================================
USE SCHEMA PRODUCTS;

CREATE OR REPLACE FUNCTION "TOOL_GET_LABEL_URL"("STAGE_PATH" VARCHAR)
RETURNS VARCHAR
LANGUAGE SQL
COMMENT='Convert stage path to viewable presigned URL (7 day expiry). Returns helpful message if file not found.'
AS '
    CASE
        WHEN EXISTS (
            SELECT 1 FROM DIRECTORY(@AGENT_COMMERCE.PRODUCTS.PRODUCT_MEDIA_STAGE)
            WHERE RELATIVE_PATH = REPLACE(stage_path, ''@PRODUCTS.PRODUCT_MEDIA/'', '''')
        )
        THEN GET_PRESIGNED_URL(
            ''@AGENT_COMMERCE.PRODUCTS.PRODUCT_MEDIA_STAGE'',
            REPLACE(stage_path, ''@PRODUCTS.PRODUCT_MEDIA/'', ''''),
            604800
        )
        ELSE ''[Label image not available - please use LabelSearch to find products with label images]''
    END
';

CREATE OR REPLACE FUNCTION "TOOL_MATCH_PRODUCTS"("TARGET_HEX" VARCHAR, "CATEGORY_FILTER" VARCHAR DEFAULT null, "LIMIT_RESULTS" NUMBER(38,0) DEFAULT 10)
RETURNS ARRAY
LANGUAGE SQL
AS '
    SELECT COALESCE(ARRAY_AGG(OBJECT_CONSTRUCT(
        ''product_id'', product_id,
        ''name'', name,
        ''brand'', brand,
        ''category'', category,
        ''swatch_hex'', swatch_hex,
        ''color_distance'', color_distance,
        ''price'', price,
        ''image_url'', image_url
    )), ARRAY_CONSTRUCT())
    FROM (
        SELECT
            p.product_id,
            p.name,
            p.brand,
            p.category,
            pv.color_hex AS swatch_hex,
            ROUND(SQRT(
                POWER(COALESCE(TRY_TO_NUMBER(SUBSTR(pv.color_hex, 2, 2), ''XX''), 0) -
                       COALESCE(TRY_TO_NUMBER(SUBSTR(CASE WHEN LEFT(target_hex, 1) = ''#'' THEN target_hex ELSE ''#'' || target_hex END, 2, 2), ''XX''), 128), 2) +
                POWER(COALESCE(TRY_TO_NUMBER(SUBSTR(pv.color_hex, 4, 2), ''XX''), 0) -
                       COALESCE(TRY_TO_NUMBER(SUBSTR(CASE WHEN LEFT(target_hex, 1) = ''#'' THEN target_hex ELSE ''#'' || target_hex END, 4, 2), ''XX''), 128), 2) +
                POWER(COALESCE(TRY_TO_NUMBER(SUBSTR(pv.color_hex, 6, 2), ''XX''), 0) -
                       COALESCE(TRY_TO_NUMBER(SUBSTR(CASE WHEN LEFT(target_hex, 1) = ''#'' THEN target_hex ELSE ''#'' || target_hex END, 6, 2), ''XX''), 128), 2)
            ), 2) AS color_distance,
            p.current_price AS price,
            pm.url AS image_url,
            ROW_NUMBER() OVER (ORDER BY
                SQRT(
                    POWER(COALESCE(TRY_TO_NUMBER(SUBSTR(pv.color_hex, 2, 2), ''XX''), 0) -
                           COALESCE(TRY_TO_NUMBER(SUBSTR(CASE WHEN LEFT(target_hex, 1) = ''#'' THEN target_hex ELSE ''#'' || target_hex END, 2, 2), ''XX''), 128), 2) +
                    POWER(COALESCE(TRY_TO_NUMBER(SUBSTR(pv.color_hex, 4, 2), ''XX''), 0) -
                           COALESCE(TRY_TO_NUMBER(SUBSTR(CASE WHEN LEFT(target_hex, 1) = ''#'' THEN target_hex ELSE ''#'' || target_hex END, 4, 2), ''XX''), 128), 2) +
                    POWER(COALESCE(TRY_TO_NUMBER(SUBSTR(pv.color_hex, 6, 2), ''XX''), 0) -
                           COALESCE(TRY_TO_NUMBER(SUBSTR(CASE WHEN LEFT(target_hex, 1) = ''#'' THEN target_hex ELSE ''#'' || target_hex END, 6, 2), ''XX''), 128), 2)
                ) ASC,
                CASE LOWER(p.category)
                    WHEN ''face'' THEN 1
                    WHEN ''lips'' THEN 2
                    WHEN ''eyes'' THEN 3
                    WHEN ''skincare'' THEN 4
                    ELSE 5
                END ASC
            ) AS rn
        FROM PRODUCTS.PRODUCTS p
        JOIN PRODUCTS.PRODUCT_VARIANTS pv ON p.product_id = pv.product_id
        LEFT JOIN PRODUCTS.PRODUCT_MEDIA pm ON p.product_id = pm.product_id AND pm.is_primary = TRUE
        WHERE pv.color_hex IS NOT NULL
          AND LENGTH(pv.color_hex) = 7
          AND (
               ((category_filter IS NULL OR category_filter = '''')
                  AND LOWER(p.category) IN (''lips'', ''face'', ''eyes'', ''skincare''))
               OR LOWER(p.category) = LOWER(category_filter)
               OR (LOWER(category_filter) IN (''lipstick'', ''lip'', ''lip gloss'', ''lipgloss'') AND LOWER(p.category) = ''lips'')
               OR (LOWER(category_filter) IN (''foundation'', ''concealer'', ''powder'', ''blush'', ''bronzer'', ''highlighter'', ''primer'') AND LOWER(p.category) = ''face'')
               OR (LOWER(category_filter) IN (''eyeshadow'', ''eyeliner'', ''mascara'', ''brow'', ''eye'') AND LOWER(p.category) = ''eyes'')
               OR (LOWER(category_filter) IN (''moisturizer'', ''serum'', ''cleanser'', ''skin'') AND LOWER(p.category) = ''skincare'')
               OR (LOWER(category_filter) IN (''nail'', ''nail polish'', ''nails'') AND LOWER(p.category) = ''nails'')
              )
    ) sub
    WHERE rn <= limit_results
';

CREATE OR REPLACE FUNCTION "TOOL_MATCH_PRODUCTS_BY_CATEGORY"("TARGET_HEX" VARCHAR, "CATEGORY_FILTER" VARCHAR)
RETURNS ARRAY
LANGUAGE SQL
COMMENT='Find top 10 products in a specific category matching a target color. Returns array with price and image_url. Category examples: lips, eyes, face, skincare.'
AS '
    SELECT ARRAY_AGG(OBJECT_CONSTRUCT(
        ''product_id'', product_id,
        ''name'', name,
        ''brand'', brand,
        ''category'', category,
        ''swatch_hex'', swatch_hex,
        ''color_distance'', color_distance,
        ''price'', price,
        ''image_url'', image_url
    ))
    FROM (
        SELECT
            p.product_id,
            p.name,
            p.brand,
            p.category,
            pv.color_hex AS swatch_hex,
            ROUND(SQRT(
                POWER(TO_NUMBER(SUBSTR(pv.color_hex, 2, 2), ''XX'') - TO_NUMBER(SUBSTR(target_hex, 2, 2), ''XX''), 2) +
                POWER(TO_NUMBER(SUBSTR(pv.color_hex, 4, 2), ''XX'') - TO_NUMBER(SUBSTR(target_hex, 4, 2), ''XX''), 2) +
                POWER(TO_NUMBER(SUBSTR(pv.color_hex, 6, 2), ''XX'') - TO_NUMBER(SUBSTR(target_hex, 6, 2), ''XX''), 2)
            ), 2) AS color_distance,
            p.current_price AS price,
            pm.url AS image_url
        FROM PRODUCTS.PRODUCTS p
        JOIN PRODUCTS.PRODUCT_VARIANTS pv ON p.product_id = pv.product_id
        LEFT JOIN PRODUCTS.PRODUCT_MEDIA pm ON p.product_id = pm.product_id AND pm.is_primary = TRUE
        WHERE pv.color_hex IS NOT NULL
          AND LOWER(p.category) = LOWER(category_filter)
        ORDER BY color_distance ASC
        LIMIT 10
    )
';

CREATE OR REPLACE FUNCTION "TOOL_QUICK_PRODUCT_MATCH"("SKIN_TYPE" VARCHAR, "UNDERTONE" VARCHAR, "CATEGORY_FILTER" VARCHAR)
RETURNS ARRAY
LANGUAGE SQL
AS '
SELECT ARRAY_AGG(OBJECT_CONSTRUCT(
    ''product_id'', product_id,
    ''name'', name,
    ''brand'', brand,
    ''category'', category,
    ''price'', current_price
))
FROM (
    SELECT
        product_id,
        name,
        brand,
        category,
        current_price
    FROM PRODUCTS
    WHERE is_active = TRUE
      AND (skin_type IS NULL OR skin_type = '''' OR ARRAY_CONTAINS(LOWER(skin_type)::VARIANT, skin_type_compatibility))
      AND (undertone IS NULL OR undertone = '''' OR ARRAY_CONTAINS(LOWER(undertone)::VARIANT, undertone_compatibility))
      AND (category_filter IS NULL OR category_filter = '''' OR LOWER(category) = LOWER(category_filter))
    ORDER BY current_price ASC
    LIMIT 10
)
';

-- ============================================================
-- CART_OLTP schema UDFs and Procedures
-- ============================================================
USE SCHEMA CART_OLTP;

CREATE OR REPLACE PROCEDURE "TOOL_ADD_TO_CART"("SESSION_ID" VARCHAR, "PRODUCT_ID" VARCHAR, "QUANTITY" NUMBER(38,0), "VARIANT_ID" VARCHAR)
RETURNS VARIANT
LANGUAGE SQL
COMMENT='Add a product to cart. Parameters: session_id, product_id (UUID or product name), quantity, variant_id (optional, pass NULL if not needed).'
EXECUTE AS OWNER
AS '
DECLARE
    new_item_id VARCHAR;
    v_unit_price_cents INT;
    v_subtotal_cents INT;
    v_product_name VARCHAR;
    v_session_subtotal INT;
    v_resolved_product_id VARCHAR;
BEGIN
    IF (LENGTH(:product_id) = 36
        AND SUBSTRING(:product_id, 9, 1) = ''-''
        AND SUBSTRING(:product_id, 14, 1) = ''-''
        AND SUBSTRING(:product_id, 19, 1) = ''-''
        AND SUBSTRING(:product_id, 24, 1) = ''-'') THEN
        v_resolved_product_id := :product_id;
    ELSE
        SELECT product_id INTO :v_resolved_product_id
        FROM PRODUCTS.PRODUCTS
        WHERE LOWER(name) = LOWER(:product_id)
        LIMIT 1;

        IF (:v_resolved_product_id IS NULL) THEN
            SELECT product_id INTO :v_resolved_product_id
            FROM PRODUCTS.PRODUCTS
            WHERE LOWER(name) LIKE ''%'' || LOWER(:product_id) || ''%''
            LIMIT 1;
        END IF;

        IF (:v_resolved_product_id IS NULL) THEN
            RETURN OBJECT_CONSTRUCT(
                ''success'', FALSE,
                ''error'', ''Product not found: '' || :product_id,
                ''message'', ''Could not find a product matching "'' || :product_id || ''". Please try with the exact product name.''
            )::VARIANT;
        END IF;
    END IF;

    SELECT
        ROUND(CURRENT_PRICE * 100)::INT,
        name
    INTO :v_unit_price_cents, :v_product_name
    FROM PRODUCTS.PRODUCTS
    WHERE product_id = :v_resolved_product_id;

    IF (:v_unit_price_cents IS NULL) THEN
        RETURN OBJECT_CONSTRUCT(
            ''success'', FALSE,
            ''error'', ''Product not found with ID: '' || :v_resolved_product_id,
            ''message'', ''The product could not be found in our catalog.''
        )::VARIANT;
    END IF;

    v_subtotal_cents := :v_unit_price_cents * :quantity;
    new_item_id := UUID_STRING();

    INSERT INTO CART_OLTP.CART_ITEMS (
        item_id,
        session_id,
        product_id,
        variant_id,
        quantity,
        unit_price_cents,
        subtotal_cents,
        product_name,
        added_at
    ) VALUES (
        :new_item_id,
        :session_id,
        :v_resolved_product_id,
        :variant_id,
        :quantity,
        :v_unit_price_cents,
        :v_subtotal_cents,
        :v_product_name,
        CURRENT_TIMESTAMP()
    );

    SELECT SUM(subtotal_cents) INTO :v_session_subtotal
    FROM CART_OLTP.CART_ITEMS
    WHERE session_id = :session_id;

    UPDATE CART_OLTP.CART_SESSIONS
    SET subtotal_cents = :v_session_subtotal,
        total_cents = :v_session_subtotal,
        updated_at = CURRENT_TIMESTAMP()
    WHERE session_id = :session_id;

    RETURN OBJECT_CONSTRUCT(
        ''success'', TRUE,
        ''item_id'', :new_item_id,
        ''product_id'', :v_resolved_product_id,
        ''product_name'', :v_product_name,
        ''quantity'', :quantity,
        ''unit_price_cents'', :v_unit_price_cents,
        ''subtotal_cents'', :v_subtotal_cents,
        ''message'', ''Item added to cart''
    )::VARIANT;
END;
';

CREATE OR REPLACE PROCEDURE "TOOL_CREATE_CART_SESSION"("CUSTOMER_ID" VARCHAR)
RETURNS VARIANT
LANGUAGE SQL
COMMENT='Create a new cart session for a customer. Returns session_id for subsequent cart operations.'
EXECUTE AS OWNER
AS '
DECLARE
    new_session_id VARCHAR;
BEGIN
    new_session_id := UUID_STRING();

    INSERT INTO CART_OLTP.CART_SESSIONS (
        session_id,
        customer_id,
        status,
        subtotal_cents,
        total_cents,
        currency,
        created_at
    ) VALUES (
        :new_session_id,
        :customer_id,
        ''active'',
        0,
        0,
        ''USD'',
        CURRENT_TIMESTAMP()
    );

    RETURN OBJECT_CONSTRUCT(
        ''success'', TRUE,
        ''session_id'', :new_session_id,
        ''customer_id'', :customer_id,
        ''status'', ''active'',
        ''message'', ''Cart session created successfully''
    )::VARIANT;
END;
';

CREATE OR REPLACE FUNCTION "TOOL_GET_CART_SESSION"("SESSION_ID" VARCHAR)
RETURNS VARIANT
LANGUAGE SQL
COMMENT='Get cart session with all items.'
AS 'SELECT OBJECT_CONSTRUCT(''session_id'', s.session_id, ''customer_id'', s.customer_id, ''status'', s.status, ''currency'', s.currency, ''items'', (SELECT COALESCE(ARRAY_AGG(OBJECT_CONSTRUCT(''item_id'', ci.item_id, ''product_id'', ci.product_id, ''product_name'', ci.product_name, ''variant_id'', ci.variant_id, ''variant_name'', ci.variant_name, ''quantity'', ci.quantity, ''unit_price_cents'', ci.unit_price_cents, ''subtotal_cents'', ci.subtotal_cents)), ARRAY_CONSTRUCT()) FROM CART_OLTP.CART_ITEMS ci WHERE ci.session_id = s.session_id), ''item_count'', (SELECT COUNT(*) FROM CART_OLTP.CART_ITEMS ci2 WHERE ci2.session_id = s.session_id), ''subtotal_cents'', s.subtotal_cents, ''total_cents'', s.total_cents, ''created_at'', s.created_at)::VARIANT FROM CART_OLTP.CART_SESSIONS s WHERE s.session_id = COALESCE((SELECT cs.session_id FROM CART_OLTP.CART_SESSIONS cs WHERE cs.session_id = session_id LIMIT 1), (SELECT cs.session_id FROM CART_OLTP.CART_SESSIONS cs WHERE cs.customer_id = session_id AND cs.status = ''active'' ORDER BY cs.created_at DESC LIMIT 1))';

CREATE OR REPLACE PROCEDURE "TOOL_REMOVE_FROM_CART"("ITEM_ID" VARCHAR)
RETURNS VARIANT
LANGUAGE SQL
EXECUTE AS OWNER
AS '
DECLARE
    v_session_id VARCHAR;
    v_session_subtotal INT;
    v_resolved_item_id VARCHAR;
    v_product_name VARCHAR;
BEGIN
    IF (LENGTH(:item_id) = 36 
        AND SUBSTRING(:item_id, 9, 1) = ''-''
        AND SUBSTRING(:item_id, 14, 1) = ''-''
        AND SUBSTRING(:item_id, 19, 1) = ''-''
        AND SUBSTRING(:item_id, 24, 1) = ''-'') THEN
        v_resolved_item_id := :item_id;
    ELSE
        SELECT ci.item_id, ci.product_name
        INTO :v_resolved_item_id, :v_product_name
        FROM CART_OLTP.CART_ITEMS ci
        WHERE LOWER(ci.product_name) = LOWER(:item_id)
        ORDER BY ci.added_at DESC
        LIMIT 1;
        
        IF (:v_resolved_item_id IS NULL) THEN
            SELECT ci.item_id, ci.product_name
            INTO :v_resolved_item_id, :v_product_name
            FROM CART_OLTP.CART_ITEMS ci
            WHERE LOWER(ci.product_name) LIKE ''%'' || LOWER(:item_id) || ''%''
            ORDER BY ci.added_at DESC
            LIMIT 1;
        END IF;
        
        IF (:v_resolved_item_id IS NULL) THEN
            RETURN OBJECT_CONSTRUCT(
                ''success'', FALSE,
                ''error'', ''Cart item not found: '' || :item_id,
                ''message'', ''Could not find a cart item matching "'' || :item_id || ''". Please check your cart.''
            )::VARIANT;
        END IF;
    END IF;
    
    SELECT session_id, product_name 
    INTO :v_session_id, :v_product_name
    FROM CART_OLTP.CART_ITEMS
    WHERE item_id = :v_resolved_item_id;
    
    IF (:v_session_id IS NULL) THEN
        RETURN OBJECT_CONSTRUCT(
            ''success'', FALSE,
            ''error'', ''Cart item not found with ID: '' || :v_resolved_item_id,
            ''message'', ''The cart item could not be found.''
        )::VARIANT;
    END IF;
    
    DELETE FROM CART_OLTP.CART_ITEMS 
    WHERE item_id = :v_resolved_item_id;
    
    SELECT COALESCE(SUM(subtotal_cents), 0) INTO :v_session_subtotal
    FROM CART_OLTP.CART_ITEMS
    WHERE session_id = :v_session_id;
    
    UPDATE CART_OLTP.CART_SESSIONS
    SET subtotal_cents = :v_session_subtotal,
        total_cents = :v_session_subtotal,
        updated_at = CURRENT_TIMESTAMP()
    WHERE session_id = :v_session_id;
    
    RETURN OBJECT_CONSTRUCT(
        ''success'', TRUE,
        ''removed_item_id'', :v_resolved_item_id,
        ''product_name'', :v_product_name,
        ''message'', ''Item removed from cart''
    )::VARIANT;
END;
';

CREATE OR REPLACE PROCEDURE "TOOL_REMOVE_FROM_CART"("SESSION_ID" VARCHAR, "ITEM_ID" VARCHAR)
RETURNS VARIANT
LANGUAGE SQL
COMMENT='Remove an item from the cart. session_id can be UUID or customer_id. item_id can be UUID or product name.'
EXECUTE AS OWNER
AS '
DECLARE
    v_session_id VARCHAR;
    v_session_subtotal INT;
    v_resolved_item_id VARCHAR;
    v_product_name VARCHAR;
    v_resolved_session_id VARCHAR;
BEGIN
    SELECT s.session_id INTO :v_resolved_session_id
    FROM CART_OLTP.CART_SESSIONS s
    WHERE s.session_id = COALESCE(
        (SELECT session_id FROM CART_OLTP.CART_SESSIONS WHERE session_id = :session_id LIMIT 1),
        (SELECT session_id FROM CART_OLTP.CART_SESSIONS
          WHERE customer_id = :session_id AND status = ''active''
          ORDER BY created_at DESC LIMIT 1)
    );

    IF (:v_resolved_session_id IS NULL) THEN
        RETURN OBJECT_CONSTRUCT(
            ''success'', FALSE,
            ''error'', ''Cart session not found: '' || :session_id,
            ''message'', ''Could not find a cart session. Please create a cart first.''
        )::VARIANT;
    END IF;

    IF (LENGTH(:item_id) = 36
        AND SUBSTRING(:item_id, 9, 1) = ''-''
        AND SUBSTRING(:item_id, 14, 1) = ''-''
        AND SUBSTRING(:item_id, 19, 1) = ''-''
        AND SUBSTRING(:item_id, 24, 1) = ''-'') THEN
        v_resolved_item_id := :item_id;
    ELSE
        SELECT ci.item_id, ci.product_name
        INTO :v_resolved_item_id, :v_product_name
        FROM CART_OLTP.CART_ITEMS ci
        WHERE ci.session_id = :v_resolved_session_id
          AND LOWER(ci.product_name) = LOWER(:item_id)
        LIMIT 1;

        IF (:v_resolved_item_id IS NULL) THEN
            SELECT ci.item_id, ci.product_name
            INTO :v_resolved_item_id, :v_product_name
            FROM CART_OLTP.CART_ITEMS ci
            WHERE ci.session_id = :v_resolved_session_id
              AND LOWER(ci.product_name) LIKE ''%'' || LOWER(:item_id) || ''%''
            LIMIT 1;
        END IF;

        IF (:v_resolved_item_id IS NULL) THEN
            RETURN OBJECT_CONSTRUCT(
                ''success'', FALSE,
                ''error'', ''Cart item not found: '' || :item_id,
                ''message'', ''Could not find "'' || :item_id || ''" in your cart. Please check your cart contents.''
            )::VARIANT;
        END IF;
    END IF;

    SELECT session_id, product_name
    INTO :v_session_id, :v_product_name
    FROM CART_OLTP.CART_ITEMS
    WHERE item_id = :v_resolved_item_id
      AND session_id = :v_resolved_session_id;

    IF (:v_session_id IS NULL) THEN
        RETURN OBJECT_CONSTRUCT(
            ''success'', FALSE,
            ''error'', ''Cart item not found in your cart'',
            ''message'', ''The item could not be found in your current cart.''
        )::VARIANT;
    END IF;

    DELETE FROM CART_OLTP.CART_ITEMS
    WHERE item_id = :v_resolved_item_id
      AND session_id = :v_resolved_session_id;

    SELECT COALESCE(SUM(subtotal_cents), 0) INTO :v_session_subtotal
    FROM CART_OLTP.CART_ITEMS
    WHERE session_id = :v_resolved_session_id;

    UPDATE CART_OLTP.CART_SESSIONS
    SET subtotal_cents = :v_session_subtotal,
        total_cents = :v_session_subtotal,
        updated_at = CURRENT_TIMESTAMP()
    WHERE session_id = :v_resolved_session_id;

    RETURN OBJECT_CONSTRUCT(
        ''success'', TRUE,
        ''session_id'', :v_resolved_session_id,
        ''removed_item_id'', :v_resolved_item_id,
        ''product_name'', :v_product_name,
        ''message'', ''Item removed from cart''
    )::VARIANT;
END;
';

CREATE OR REPLACE PROCEDURE "TOOL_SUBMIT_ORDER"("SESSION_ID" VARCHAR)
RETURNS VARIANT
LANGUAGE SQL
COMMENT='Finalize checkout and create order. Processes cart items, creates order record, and returns order confirmation with order_id, order_number, and total.'
EXECUTE AS OWNER
AS '
DECLARE
    new_order_id VARCHAR;
    v_order_number VARCHAR;
    v_customer_id VARCHAR;
    v_subtotal_cents INT;
    v_total_cents INT;
    v_item_count INT;
BEGIN
    SELECT
        customer_id,
        subtotal_cents,
        total_cents
    INTO :v_customer_id, :v_subtotal_cents, :v_total_cents
    FROM CART_OLTP.CART_SESSIONS
    WHERE session_id = :session_id;

    SELECT COUNT(*) INTO :v_item_count
    FROM CART_OLTP.CART_ITEMS
    WHERE session_id = :session_id;

    new_order_id := UUID_STRING();
    v_order_number := ''ORD-'' || TO_CHAR(CURRENT_TIMESTAMP(), ''YYYYMMDD'') || ''-'' || SUBSTR(REPLACE(UUID_STRING(), ''-'', ''''), 1, 6);

    INSERT INTO CART_OLTP.ORDERS (
        order_id,
        order_number,
        session_id,
        customer_id,
        status,
        subtotal_cents,
        tax_cents,
        shipping_cents,
        discount_cents,
        total_cents,
        currency,
        created_at,
        confirmed_at
    ) VALUES (
        :new_order_id,
        :v_order_number,
        :session_id,
        :v_customer_id,
        ''confirmed'',
        :v_subtotal_cents,
        0,
        0,
        0,
        :v_total_cents,
        ''USD'',
        CURRENT_TIMESTAMP(),
        CURRENT_TIMESTAMP()
    );

    INSERT INTO CART_OLTP.ORDER_ITEMS (
        order_item_id,
        order_id,
        product_id,
        variant_id,
        quantity,
        unit_price_cents,
        subtotal_cents,
        product_name,
        variant_name,
        product_image_url,
        created_at
    )
    SELECT
        UUID_STRING(),
        :new_order_id,
        product_id,
        variant_id,
        quantity,
        unit_price_cents,
        subtotal_cents,
        product_name,
        variant_name,
        product_image_url,
        CURRENT_TIMESTAMP()
    FROM CART_OLTP.CART_ITEMS
    WHERE session_id = :session_id;

    UPDATE CART_OLTP.CART_SESSIONS
    SET status = ''completed'',
        updated_at = CURRENT_TIMESTAMP()
    WHERE session_id = :session_id;

    RETURN OBJECT_CONSTRUCT(
        ''success'', TRUE,
        ''order_id'', :new_order_id,
        ''order_number'', :v_order_number,
        ''customer_id'', :v_customer_id,
        ''item_count'', :v_item_count,
        ''total_cents'', :v_total_cents,
        ''total_dollars'', ROUND(:v_total_cents / 100.0, 2),
        ''status'', ''confirmed'',
        ''message'', ''Order placed successfully!''
    )::VARIANT;
END;
';

CREATE OR REPLACE PROCEDURE "TOOL_UPDATE_CART_ITEM"("ITEM_ID" VARCHAR, "NEW_QUANTITY" NUMBER(38,0))
RETURNS VARIANT
LANGUAGE SQL
EXECUTE AS OWNER
AS '
DECLARE
    v_session_id VARCHAR;
    v_unit_price_cents INT;
    v_new_subtotal_cents INT;
    v_session_subtotal INT;
    v_resolved_item_id VARCHAR;
    v_product_name VARCHAR;
BEGIN
    IF (LENGTH(:item_id) = 36 
        AND SUBSTRING(:item_id, 9, 1) = ''-''
        AND SUBSTRING(:item_id, 14, 1) = ''-''
        AND SUBSTRING(:item_id, 19, 1) = ''-''
        AND SUBSTRING(:item_id, 24, 1) = ''-'') THEN
        v_resolved_item_id := :item_id;
    ELSE
        SELECT ci.item_id, ci.product_name
        INTO :v_resolved_item_id, :v_product_name
        FROM CART_OLTP.CART_ITEMS ci
        WHERE LOWER(ci.product_name) = LOWER(:item_id)
        ORDER BY ci.added_at DESC
        LIMIT 1;
        
        IF (:v_resolved_item_id IS NULL) THEN
            SELECT ci.item_id, ci.product_name
            INTO :v_resolved_item_id, :v_product_name
            FROM CART_OLTP.CART_ITEMS ci
            WHERE LOWER(ci.product_name) LIKE ''%'' || LOWER(:item_id) || ''%''
            ORDER BY ci.added_at DESC
            LIMIT 1;
        END IF;
        
        IF (:v_resolved_item_id IS NULL) THEN
            RETURN OBJECT_CONSTRUCT(
                ''success'', FALSE,
                ''error'', ''Cart item not found: '' || :item_id,
                ''message'', ''Could not find a cart item matching "'' || :item_id || ''". Please check your cart.''
            )::VARIANT;
        END IF;
    END IF;
    
    SELECT session_id, unit_price_cents, product_name
    INTO :v_session_id, :v_unit_price_cents, :v_product_name
    FROM CART_OLTP.CART_ITEMS
    WHERE item_id = :v_resolved_item_id;
    
    IF (:v_session_id IS NULL) THEN
        RETURN OBJECT_CONSTRUCT(
            ''success'', FALSE,
            ''error'', ''Cart item not found with ID: '' || :v_resolved_item_id,
            ''message'', ''The cart item could not be found.''
        )::VARIANT;
    END IF;
    
    v_new_subtotal_cents := :v_unit_price_cents * :new_quantity;
    
    UPDATE CART_OLTP.CART_ITEMS
    SET quantity = :new_quantity,
        subtotal_cents = :v_new_subtotal_cents,
        updated_at = CURRENT_TIMESTAMP()
    WHERE item_id = :v_resolved_item_id;
    
    SELECT SUM(subtotal_cents) INTO :v_session_subtotal
    FROM CART_OLTP.CART_ITEMS
    WHERE session_id = :v_session_id;
    
    UPDATE CART_OLTP.CART_SESSIONS
    SET subtotal_cents = :v_session_subtotal,
        total_cents = :v_session_subtotal,
        updated_at = CURRENT_TIMESTAMP()
    WHERE session_id = :v_session_id;
    
    RETURN OBJECT_CONSTRUCT(
        ''success'', TRUE,
        ''item_id'', :v_resolved_item_id,
        ''product_name'', :v_product_name,
        ''new_quantity'', :new_quantity,
        ''new_subtotal_cents'', :v_new_subtotal_cents,
        ''message'', ''Cart item updated''
    )::VARIANT;
END;
';

CREATE OR REPLACE PROCEDURE "TOOL_UPDATE_CART_ITEM"("SESSION_ID" VARCHAR, "ITEM_ID" VARCHAR, "NEW_QUANTITY" NUMBER(38,0))
RETURNS VARIANT
LANGUAGE SQL
COMMENT='Update the quantity of an item in the cart. session_id can be UUID or customer_id. item_id can be UUID or product name.'
EXECUTE AS OWNER
AS '
DECLARE
    v_session_id VARCHAR;
    v_unit_price_cents INT;
    v_new_subtotal_cents INT;
    v_session_subtotal INT;
    v_resolved_item_id VARCHAR;
    v_product_name VARCHAR;
    v_resolved_session_id VARCHAR;
BEGIN
    SELECT s.session_id INTO :v_resolved_session_id
    FROM CART_OLTP.CART_SESSIONS s
    WHERE s.session_id = COALESCE(
        (SELECT session_id FROM CART_OLTP.CART_SESSIONS WHERE session_id = :session_id LIMIT 1),
        (SELECT session_id FROM CART_OLTP.CART_SESSIONS
          WHERE customer_id = :session_id AND status = ''active''
          ORDER BY created_at DESC LIMIT 1)
    );

    IF (:v_resolved_session_id IS NULL) THEN
        RETURN OBJECT_CONSTRUCT(
            ''success'', FALSE,
            ''error'', ''Cart session not found: '' || :session_id,
            ''message'', ''Could not find a cart session. Please create a cart first.''
        )::VARIANT;
    END IF;

    IF (LENGTH(:item_id) = 36
        AND SUBSTRING(:item_id, 9, 1) = ''-''
        AND SUBSTRING(:item_id, 14, 1) = ''-''
        AND SUBSTRING(:item_id, 19, 1) = ''-''
        AND SUBSTRING(:item_id, 24, 1) = ''-'') THEN
        v_resolved_item_id := :item_id;
    ELSE
        SELECT ci.item_id, ci.product_name
        INTO :v_resolved_item_id, :v_product_name
        FROM CART_OLTP.CART_ITEMS ci
        WHERE ci.session_id = :v_resolved_session_id
          AND LOWER(ci.product_name) = LOWER(:item_id)
        LIMIT 1;

        IF (:v_resolved_item_id IS NULL) THEN
            SELECT ci.item_id, ci.product_name
            INTO :v_resolved_item_id, :v_product_name
            FROM CART_OLTP.CART_ITEMS ci
            WHERE ci.session_id = :v_resolved_session_id
              AND LOWER(ci.product_name) LIKE ''%'' || LOWER(:item_id) || ''%''
            LIMIT 1;
        END IF;

        IF (:v_resolved_item_id IS NULL) THEN
            RETURN OBJECT_CONSTRUCT(
                ''success'', FALSE,
                ''error'', ''Cart item not found: '' || :item_id,
                ''message'', ''Could not find "'' || :item_id || ''" in your cart. Please check your cart contents.''
            )::VARIANT;
        END IF;
    END IF;

    SELECT session_id, unit_price_cents, product_name
    INTO :v_session_id, :v_unit_price_cents, :v_product_name
    FROM CART_OLTP.CART_ITEMS
    WHERE item_id = :v_resolved_item_id
      AND session_id = :v_resolved_session_id;

    IF (:v_session_id IS NULL) THEN
        RETURN OBJECT_CONSTRUCT(
            ''success'', FALSE,
            ''error'', ''Cart item not found in your cart'',
            ''message'', ''The item could not be found in your current cart.''
        )::VARIANT;
    END IF;

    v_new_subtotal_cents := :v_unit_price_cents * :new_quantity;

    UPDATE CART_OLTP.CART_ITEMS
    SET quantity = :new_quantity,
        subtotal_cents = :v_new_subtotal_cents,
        updated_at = CURRENT_TIMESTAMP()
    WHERE item_id = :v_resolved_item_id;

    SELECT SUM(subtotal_cents) INTO :v_session_subtotal
    FROM CART_OLTP.CART_ITEMS
    WHERE session_id = :v_resolved_session_id;

    UPDATE CART_OLTP.CART_SESSIONS
    SET subtotal_cents = :v_session_subtotal,
        total_cents = :v_session_subtotal,
        updated_at = CURRENT_TIMESTAMP()
    WHERE session_id = :v_resolved_session_id;

    RETURN OBJECT_CONSTRUCT(
        ''success'', TRUE,
        ''session_id'', :v_resolved_session_id,
        ''item_id'', :v_resolved_item_id,
        ''product_name'', :v_product_name,
        ''new_quantity'', :new_quantity,
        ''new_subtotal_cents'', :v_new_subtotal_cents,
        ''message'', ''Cart item updated''
    )::VARIANT;
END;
';

-- ============================================================
-- UTIL schema UDFs and Procedures
-- ============================================================
USE SCHEMA UTIL;

CREATE OR REPLACE FUNCTION "CALL_AGENT_UDF"("USER_MESSAGE" VARCHAR, "HISTORY_JSON" VARCHAR)
RETURNS VARCHAR
LANGUAGE PYTHON
RUNTIME_VERSION = '3.10'
PACKAGES = ('snowflake-snowpark-python','requests')
HANDLER = 'call_agent'
EXTERNAL_ACCESS_INTEGRATIONS = (SPCS_BACKEND_ACCESS)
AS '
import requests
import json
import os

def call_agent(user_message, history_json):
    try:
        # Get auth token from Snowpark context
        from snowflake.snowpark.context import get_active_session
        session = get_active_session()
        
        # Build the API URL
        # Use internal format that works from Python UDFs
        account = "sfsehol-si-ae-enablement-retail-kvldzi"
        api_url = f"https://{account}.snowflakecomputing.com/api/v2/databases/AGENT_COMMERCE/schemas/UTIL/agents/AGENTIC_COMMERCE_ASSISTANT:run"
        
        # Parse history
        history = json.loads(history_json) if history_json else []
        
        # Build messages
        messages = history + [{"role": "user", "content": user_message}]
        
        # Build request
        request_body = {
            "model": "claude-4-sonnet",
            "messages": messages,
            "tools": [],
            "stream": False
        }
        
        # Make the request using session token
        # Note: Python UDFs with EXTERNAL_ACCESS_INTEGRATIONS can make network calls
        response = requests.post(
            api_url,
            json=request_body,
            headers={"Content-Type": "application/json"},
            timeout=60
        )
        
        if response.status_code == 200:
            return json.dumps(response.json())
        else:
            return json.dumps({"error": f"HTTP {response.status_code}: {response.text}"})
            
    except Exception as e:
        return json.dumps({"error": str(e)})
';

CREATE OR REPLACE FUNCTION "CALL_SPCS_EXTRACT_EMBEDDING"("IMAGE_BASE64" VARCHAR)
RETURNS VARIANT
LANGUAGE SQL
AS '
    SELECT OBJECT_CONSTRUCT(
        ''success'', TRUE,
        ''embedding'', ARRAY_CONSTRUCT_COMPACT(),
        ''message'', ''Placeholder - implement with external function''
    )::VARIANT
';

CREATE OR REPLACE PROCEDURE "INVOKE_AGENT_SP"("USER_MESSAGE" VARCHAR, "CONVERSATION_HISTORY" ARRAY)
RETURNS VARIANT
LANGUAGE SQL
EXECUTE AS OWNER
AS '
DECLARE
    result VARIANT;
    messages ARRAY;
BEGIN
    messages := ARRAY_CAT(
        COALESCE(conversation_history, ARRAY_CONSTRUCT()),
        ARRAY_CONSTRUCT(OBJECT_CONSTRUCT(''role'', ''user'', ''content'', user_message))
    );

    SELECT SNOWFLAKE.CORTEX.INVOKE_AGENT(
        ''AGENT_COMMERCE.UTIL.AGENTIC_COMMERCE_ASSISTANT'',
        :messages,
        OBJECT_CONSTRUCT()
    ) INTO result;

    RETURN result;
END;
';

CREATE OR REPLACE PROCEDURE "SEND_EMAIL"("RECIPIENT_EMAIL" VARCHAR, "SUBJECT" VARCHAR, "BODY" VARCHAR)
RETURNS VARCHAR
LANGUAGE PYTHON
RUNTIME_VERSION = '3.11'
PACKAGES = ('snowflake-snowpark-python')
HANDLER = 'send_email'
EXECUTE AS CALLER
AS '
def send_email(session, recipient_email, subject, body):
    try:
        escaped_body = body.replace("''", "''''")
        session.sql(f"""
            CALL SYSTEM$SEND_EMAIL(
                ''email_integration'',
                ''{recipient_email}'',
                ''{subject}'',
                ''{escaped_body}''
            )
        """).collect()
        return f"Email sent successfully to {recipient_email}"
    except Exception as e:
        return f"Error sending email: {str(e)}"
';

CREATE OR REPLACE FUNCTION "TEST_SPCS_CONNECTIVITY"()
RETURNS VARIANT
LANGUAGE PYTHON
RUNTIME_VERSION = '3.10'
PACKAGES = ('requests')
HANDLER = 'test_connection'
EXTERNAL_ACCESS_INTEGRATIONS = (SPCS_BACKEND_ACCESS)
AS '
import requests
def test_connection():
    try:
        url = "https://eshhuw-sfsehol-si-ae-enablement-retail-kvldzi.snowflakecomputing.app/health"
        response = requests.get(url, timeout=10)
        return {"success": True, "status_code": response.status_code, "response": response.json()}
    except Exception as e:
        return {"success": False, "error": str(e)}
';
