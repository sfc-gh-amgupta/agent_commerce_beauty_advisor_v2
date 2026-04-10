-- =============================================================================
-- 07: Create Semantic Views
-- =============================================================================
USE ROLE AGENT_COMMERCE_ROLE;
USE DATABASE AGENT_COMMERCE;
USE WAREHOUSE AGENT_COMMERCE_WH;

USE SCHEMA PRODUCTS;

create or replace semantic view PRODUCT_SEMANTIC_VIEW
	tables (
		PRICE_HIST as AGENT_COMMERCE.PRODUCTS.PRICE_HISTORY primary key (HISTORY_ID) with synonyms=('price changes','price trends','pricing history') comment='Historical price changes',
		PRODUCT as AGENT_COMMERCE.PRODUCTS.PRODUCTS primary key (PRODUCT_ID) with synonyms=('beauty products','cosmetics','items','makeup','products') comment='Core product catalog',
		PROMO as AGENT_COMMERCE.PRODUCTS.PROMOTIONS primary key (PROMOTION_ID) with synonyms=('coupons','deals','discounts','offers','promotions','sales') comment='Active and past promotions',
		VARIANT as AGENT_COMMERCE.PRODUCTS.PRODUCT_VARIANTS primary key (VARIANT_ID) with synonyms=('colors','options','shades','sizes','variants') comment='Product variants (shades, sizes)'
	)
	relationships (
		PRICE_HIST(PRODUCT_ID) references PRODUCT(PRODUCT_ID),
		VARIANT(PRODUCT_ID) references PRODUCT(PRODUCT_ID)
	)
	facts (
		PRICE_HIST.PREVIOUS_PRICE as price_hist.previous_price comment='Previous price before change',
		PRICE_HIST.PRICE as price_hist.price comment='Price at a point in time',
		PRODUCT.BASE_PRICE as product.base_price with synonyms=('msrp','original price','regular price') comment='Base/regular price',
		PRODUCT.CURRENT_PRICE as product.current_price with synonyms=('cost','price','sale price') comment='Current selling price',
		PRODUCT.SPF_VALUE as product.spf_value comment='SPF value if applicable',
		PROMO.DISCOUNT_VALUE as promo.discount_value with synonyms=('discount','off','savings') comment='Discount value (percentage or fixed amount)',
		PROMO.MIN_PURCHASE_AMOUNT as promo.min_purchase_amount comment='Minimum purchase required for promotion',
		VARIANT.PRICE_MODIFIER as variant.price_modifier comment='Price adjustment for variant'
	)
	dimensions (
		PRICE_HIST.CHANGE_REASON as price_hist.change_reason comment='Reason for price change',
		PRICE_HIST.EFFECTIVE_DATE as price_hist.effective_date comment='Date price became effective',
		PRICE_HIST.HISTORY_ID as price_hist.history_id comment='Unique price history ID',
		PRICE_HIST.PRODUCT_ID as price_hist.product_id comment='Product ID',
		PRODUCT.BRAND as product.brand with synonyms=('brand name','company','manufacturer') comment='Brand name',
		PRODUCT.CATEGORY as product.category with synonyms=('product category','product type','type') comment='Top-level category: face, lips, eyes, skincare, nails, tools, fragrance',
		PRODUCT.COLOR_HEX as product.color_hex comment='Color in hex format',
		PRODUCT.COLOR_NAME as product.color_name with synonyms=('color','shade','shade name') comment='Color/shade name',
		PRODUCT.FINISH as product.finish with synonyms=('formula','texture') comment='Product finish: matte, satin, glossy, shimmer',
		PRODUCT.IS_ACTIVE as product.is_active with synonyms=('available','in stock') comment='Whether product is currently available',
		PRODUCT.IS_CRUELTY_FREE as product.is_cruelty_free comment='Whether product is cruelty-free',
		PRODUCT.IS_FEATURED as product.is_featured comment='Whether product is featured',
		PRODUCT.IS_VEGAN as product.is_vegan comment='Whether product is vegan',
		PRODUCT.LAUNCH_DATE as product.launch_date comment='Product launch date',
		PRODUCT.NAME as product.name with synonyms=('product','product name','title') comment='Product name',
		PRODUCT.PRODUCT_ID as product.product_id comment='Unique product UUID - ALWAYS include in SELECT',
		PRODUCT.SKIN_TONE_COMPATIBILITY as product.skin_tone_compatibility with synonyms=('compatible skin tones','skin tone','skin tone match') comment='Compatible skin tones array: fair, light, medium, tan, deep',
		PRODUCT.SKIN_TYPE_COMPATIBILITY as product.skin_type_compatibility with synonyms=('combination skin','dry skin','normal skin','oily skin','sensitive skin','skin type') comment='Compatible skin types array: oily, dry, normal, combination',
		PRODUCT.SKU as product.sku comment='Stock keeping unit',
		PRODUCT.SUBCATEGORY as product.subcategory comment='Product subcategory: foundation, lipstick, mascara, moisturizer, etc.',
		PRODUCT.UNDERTONE_COMPATIBILITY as product.undertone_compatibility with synonyms=('cool undertone','neutral undertone','skin undertone','undertone','undertones','warm undertone') comment='Compatible undertones array: warm, cool, neutral',
		PROMO.DISCOUNT_TYPE as promo.discount_type comment='Type: percentage, fixed, bogo, free_shipping',
		PROMO.END_DATE as promo.end_date comment='Promotion end date',
		PROMO.IS_ACTIVE as promo.is_active comment='Whether promotion is currently active',
		PROMO.NAME as promo.name with synonyms=('deal name','offer name','promo name','sale name') comment='Promotion name',
		PROMO.PROMO_CODE as promo.promo_code with synonyms=('code','coupon code','discount code') comment='Promotional code to apply',
		PROMO.PROMOTION_ID as promo.promotion_id comment='Unique promotion identifier',
		PROMO.START_DATE as promo.start_date comment='Promotion start date',
		VARIANT.IS_AVAILABLE as variant.is_available comment='Whether variant is in stock',
		VARIANT.PRODUCT_ID as variant.product_id comment='Parent product ID',
		VARIANT.SHADE_CODE as variant.shade_code comment='Shade code',
		VARIANT.SHADE_NAME as variant.shade_name comment='Shade name for this variant',
		VARIANT.SIZE as variant.size comment='Product size',
		VARIANT.VARIANT_ID as variant.variant_id comment='Unique variant identifier'
	)
	metrics (
		PRODUCT.AVG_PRICE as AVG(product.current_price) with synonyms=('average price') comment='Average product price',
		PRODUCT.MAX_PRICE as MAX(product.current_price) with synonyms=('highest price','most expensive') comment='Maximum product price',
		PRODUCT.MIN_PRICE as MIN(product.current_price) with synonyms=('cheapest','lowest price') comment='Minimum product price',
		PRODUCT.PRODUCT_COUNT as COUNT(DISTINCT product.product_id) comment='Number of products',
		PROMO.ACTIVE_PROMOS as COUNT(DISTINCT CASE WHEN promo.is_active THEN promo.promotion_id END) comment='Number of active promotions',
		VARIANT.VARIANT_COUNT as COUNT(DISTINCT variant.variant_id) comment='Number of variants'
	)
	comment='Semantic view for product catalog, variants, pricing, and promotions'
	with extension (CA='{"tables":[{"name":"PRICE_HIST","dimensions":[{"name":"CHANGE_REASON"},{"name":"EFFECTIVE_DATE"},{"name":"HISTORY_ID"},{"name":"PRODUCT_ID"}],"facts":[{"name":"PREVIOUS_PRICE"},{"name":"PRICE"}]},{"name":"PRODUCT","dimensions":[{"name":"BRAND"},{"name":"CATEGORY"},{"name":"COLOR_HEX"},{"name":"COLOR_NAME"},{"name":"FINISH"},{"name":"IS_ACTIVE"},{"name":"IS_CRUELTY_FREE"},{"name":"IS_FEATURED"},{"name":"IS_VEGAN"},{"name":"LAUNCH_DATE"},{"name":"NAME"},{"name":"PRODUCT_ID"},{"name":"SKIN_TONE_COMPATIBILITY"},{"name":"SKIN_TYPE_COMPATIBILITY"},{"name":"SKU"},{"name":"SUBCATEGORY"},{"name":"UNDERTONE_COMPATIBILITY"}],"facts":[{"name":"BASE_PRICE"},{"name":"CURRENT_PRICE"},{"name":"SPF_VALUE"}],"metrics":[{"name":"AVG_PRICE"},{"name":"MAX_PRICE"},{"name":"MIN_PRICE"},{"name":"PRODUCT_COUNT"}]},{"name":"PROMO","dimensions":[{"name":"DISCOUNT_TYPE"},{"name":"END_DATE"},{"name":"IS_ACTIVE"},{"name":"NAME"},{"name":"PROMO_CODE"},{"name":"PROMOTION_ID"},{"name":"START_DATE"}],"facts":[{"name":"DISCOUNT_VALUE"},{"name":"MIN_PURCHASE_AMOUNT"}],"metrics":[{"name":"ACTIVE_PROMOS"}]},{"name":"VARIANT","dimensions":[{"name":"IS_AVAILABLE"},{"name":"PRODUCT_ID"},{"name":"SHADE_CODE"},{"name":"SHADE_NAME"},{"name":"SIZE"},{"name":"VARIANT_ID"}],"facts":[{"name":"PRICE_MODIFIER"}],"metrics":[{"name":"VARIANT_COUNT"}]}],"relationships":[{"name":"\\"SYS_RELATIONSHIP_6cea3a19-8e25-47c6-af27-62b7577cdf99\\""},{"name":"\\"SYS_RELATIONSHIP_72867f21-2611-4aa6-b01d-eeb820f1e82f\\""}],"verified_queries":[{"name":"FACE_PRODUCTS_WARM_UNDERTONE","sql":"SELECT product_id, name, brand, category, subcategory, current_price FROM __product WHERE category = ''face'' AND ARRAY_CONTAINS(''warm''::VARIANT, undertone_compatibility) AND is_active = TRUE ORDER BY current_price ASC LIMIT 20","question":"face products for warm undertone","verified_at":1739836800,"verified_by":"admin"},{"name":"FACE_PRODUCTS_OILY_SKIN","sql":"SELECT product_id, name, brand, category, subcategory, current_price FROM __product WHERE category = ''face'' AND ARRAY_CONTAINS(''oily''::VARIANT, skin_type_compatibility) AND is_active = TRUE ORDER BY current_price ASC LIMIT 20","question":"face products for oily skin","verified_at":1739836800,"verified_by":"admin"},{"name":"FACE_PRODUCTS_DRY_WARM","sql":"SELECT product_id, name, brand, category, subcategory, current_price FROM __product WHERE category = ''face'' AND ARRAY_CONTAINS(''dry''::VARIANT, skin_type_compatibility) AND ARRAY_CONTAINS(''warm''::VARIANT, undertone_compatibility) AND is_active = TRUE ORDER BY current_price ASC LIMIT 20","question":"face products for dry skin with warm undertone","verified_at":1739836800,"verified_by":"admin"},{"name":"FOUNDATIONS_MEDIUM_SKIN","sql":"SELECT product_id, name, brand, category, subcategory, current_price FROM __product WHERE subcategory = ''foundation'' AND ARRAY_CONTAINS(''medium''::VARIANT, skin_tone_compatibility) AND is_active = TRUE ORDER BY current_price ASC LIMIT 20","question":"foundations for medium skin tone","verified_at":1739836800,"verified_by":"admin"},{"name":"\\"show me all product categories and brands available\\"","sql":"SELECT\\n  DISTINCT p.category,\\n  p.brand,\\n  COUNT(DISTINCT p.product_id) AS product_count,\\n  AVG(p.current_price) AS avg_price\\nFROM\\n  product AS p\\nWHERE\\n  p.launch_date <= CURRENT_TIMESTAMP()\\nGROUP BY\\n  p.category,\\n  p.brand\\nORDER BY\\n  p.category,\\n  p.brand\\n  /* Generated by Cortex Analyst (request_id: 6771a6b7-9b6c-4ad7-855d-707e4a619fb8) */","question":"show me all product categories and brands available","verified_at":1771345528,"verified_by":"Snowflake at NRF","use_as_onboarding_question":false},{"name":"Compare these 2 foundations for me Summer Fridays Luxe Foundation (ID: 026912b9-b508-421e-b807-7d265158b96a) - $11.67 Drunk Elephant Pro Foundation (ID: add5e831-d751-4f46-9deb-16125149ddab) - $12.87","sql":"SELECT\\n  product_id,\\n  name,\\n  brand,\\n  category,\\n  subcategory,\\n  current_price,\\n  base_price,\\n  color_name,\\n  finish,\\n  is_active,\\n  is_cruelty_free,\\n  is_vegan,\\n  launch_date,\\n  skin_tone_compatibility,\\n  skin_type_compatibility,\\n  undertone_compatibility,\\n  spf_value\\nFROM\\n  product\\nWHERE\\n  product_id IN (\\n    ''026912b9-b508-421e-b807-7d265158b96a'',\\n    ''add5e831-d751-4f46-9deb-16125149ddab''\\n  )\\nORDER BY\\n  name\\n  /* Generated by Cortex Analyst (request_id: 2d2b95ce-216f-4012-aacf-5806c33b9d2f) */","question":"Compare these 2 foundations for me Summer Fridays Luxe Foundation (ID: 026912b9-b508-421e-b807-7d265158b96a) - $11.67 Drunk Elephant Pro Foundation (ID: add5e831-d751-4f46-9deb-16125149ddab) - $12.87","verified_at":1771346244,"verified_by":"Snowflake at NRF","use_as_onboarding_question":false}]}');

USE SCHEMA SOCIAL;

create or replace semantic view SOCIAL_PROOF_SEMANTIC_VIEW
	tables (
		INFLUENCER as AGENT_COMMERCE.SOCIAL.INFLUENCER_MENTIONS primary key (MENTION_ID) with synonyms=('creator content','influencer posts','influencer reviews','influencers') comment='Influencer product mentions and reviews',
		MENTION as AGENT_COMMERCE.SOCIAL.SOCIAL_MENTIONS primary key (MENTION_ID) with synonyms=('mentions','posts','social media','social posts') comment='Social media mentions of products',
		PRODUCT as AGENT_COMMERCE.PRODUCTS.PRODUCTS primary key (PRODUCT_ID) comment='Product catalog for category filtering',
		REVIEW as AGENT_COMMERCE.SOCIAL.PRODUCT_REVIEWS primary key (REVIEW_ID) with synonyms=('customer reviews','feedback','ratings','reviews') comment='Customer product reviews',
		TRENDING as AGENT_COMMERCE.SOCIAL.TRENDING_PRODUCTS primary key (TREND_ID) with synonyms=('hot products','popular','trending','viral') comment='Currently trending products'
	)
	relationships (
		INFLUENCER(PRODUCT_ID) references PRODUCT(PRODUCT_ID),
		MENTION(PRODUCT_ID) references PRODUCT(PRODUCT_ID),
		REVIEW(PRODUCT_ID) references PRODUCT(PRODUCT_ID),
		TRENDING(PRODUCT_ID) references PRODUCT(PRODUCT_ID)
	)
	facts (
		INFLUENCER.COMMENTS as influencer.comments comment='Content comments',
		INFLUENCER.ENGAGEMENT_RATE as influencer.engagement_rate comment='Engagement rate',
		INFLUENCER.FOLLOWER_COUNT as influencer.follower_count comment='Influencer follower count',
		INFLUENCER.LIKES as influencer.likes comment='Content likes',
		INFLUENCER.VIEWS as influencer.views comment='Content views',
		MENTION.AUTHOR_FOLLOWER_COUNT as mention.author_follower_count comment='Author follower count',
		MENTION.COMMENTS as mention.comments comment='Number of comments',
		MENTION.LIKES as mention.likes comment='Number of likes',
		MENTION.SENTIMENT_SCORE as mention.sentiment_score comment='Sentiment score (-1 to 1)',
		MENTION.SHARES as mention.shares comment='Number of shares',
		MENTION.VIEWS as mention.views comment='Number of views',
		REVIEW.HELPFUL_VOTES as review.helpful_votes comment='Number of helpful votes',
		REVIEW.RATING as review.rating with synonyms=('review rating','score','stars') comment='Star rating (1-5)',
		TRENDING.MENTION_VELOCITY as trending.mention_velocity comment='Mentions per hour',
		TRENDING.TREND_RANK as trending.trend_rank comment='Position in trending list',
		TRENDING.TREND_SCORE as trending.trend_score comment='Calculated trend score'
	)
	dimensions (
		INFLUENCER.CONTENT_TYPE as influencer.content_type comment='Type: post, story, reel, video',
		INFLUENCER.INFLUENCER_HANDLE as influencer.influencer_handle with synonyms=('blogger','creator','influencer') comment='Influencer social handle',
		INFLUENCER.INFLUENCER_NAME as influencer.influencer_name comment='Influencer display name',
		INFLUENCER.INFLUENCER_SKIN_TONE as influencer.influencer_skin_tone comment='Influencer skin tone',
		INFLUENCER.IS_SPONSORED as influencer.is_sponsored with synonyms=('ad','paid','partnership','sponsored') comment='Whether content is sponsored',
		INFLUENCER.MENTION_ID as influencer.mention_id comment='Unique influencer mention ID',
		INFLUENCER.PLATFORM as influencer.platform comment='Platform',
		INFLUENCER.POST_URL as influencer.post_url comment='Link to content',
		INFLUENCER.POSTED_AT as influencer.posted_at comment='When content was posted',
		INFLUENCER.PRODUCT_ID as influencer.product_id comment='Product featured',
		MENTION.AUTHOR_HANDLE as mention.author_handle with synonyms=('author','handle','poster','username') comment='Author social handle',
		MENTION.CONTENT_TEXT as mention.content_text comment='Post content',
		MENTION.MENTION_ID as mention.mention_id comment='Unique mention identifier',
		MENTION.PLATFORM as mention.platform with synonyms=('channel','social network') comment='Platform: instagram, tiktok, youtube, twitter',
		MENTION.POST_URL as mention.post_url comment='Link to original post',
		MENTION.POSTED_AT as mention.posted_at comment='When post was made',
		MENTION.PRODUCT_ID as mention.product_id comment='Product mentioned',
		MENTION.SENTIMENT_LABEL as mention.sentiment_label with synonyms=('mood','sentiment','tone') comment='Sentiment: positive, neutral, negative',
		PRODUCT.BRAND as product.brand comment='Product brand',
		PRODUCT.CATEGORY as product.category with synonyms=('product category','product type') comment='Product category: face, lips, eyes, skincare, nails, tools, fragrance',
		PRODUCT.NAME as product.name with synonyms=('product name') comment='Product name',
		PRODUCT.PRODUCT_ID as product.product_id comment='Product identifier',
		PRODUCT.SUBCATEGORY as product.subcategory comment='Product subcategory',
		REVIEW.CREATED_AT as review.created_at comment='When review was posted',
		REVIEW.PLATFORM as review.platform comment='Platform: website, app, bazaarvoice',
		REVIEW.PRODUCT_ID as review.product_id comment='Product being reviewed',
		REVIEW.REVIEW_ID as review.review_id comment='Unique review identifier',
		REVIEW.REVIEW_TEXT as review.review_text with synonyms=('comment','feedback text','review') comment='Full review text',
		REVIEW.REVIEWER_SKIN_TONE as review.reviewer_skin_tone comment='Reviewer skin tone',
		REVIEW.REVIEWER_SKIN_TYPE as review.reviewer_skin_type comment='Reviewer skin type',
		REVIEW.REVIEWER_UNDERTONE as review.reviewer_undertone comment='Reviewer undertone',
		REVIEW.TITLE as review.title comment='Review title',
		REVIEW.VERIFIED_PURCHASE as review.verified_purchase comment='Whether reviewer is verified buyer',
		TRENDING.IS_VIRAL as trending.is_viral comment='Whether product is currently viral',
		TRENDING.PRODUCT_ID as trending.product_id comment='Trending product',
		TRENDING.TREND_ID as trending.trend_id comment='Unique trend record ID',
		TRENDING.VIRAL_REASON as trending.viral_reason comment='Reason for virality'
	)
	metrics (
		INFLUENCER.INFLUENCER_MENTION_COUNT as COUNT(DISTINCT influencer.mention_id) comment='Number of influencer mentions',
		MENTION.MENTION_COUNT as COUNT(DISTINCT mention.mention_id) comment='Number of social mentions',
		MENTION.TOTAL_ENGAGEMENT as SUM(mention.likes + mention.comments + mention.shares) comment='Total social engagement',
		REVIEW.AVG_RATING as AVG(review.rating) with synonyms=('average rating','average stars') comment='Average review rating',
		REVIEW.REVIEW_COUNT as COUNT(DISTINCT review.review_id) comment='Number of reviews',
		TRENDING.VIRAL_PRODUCT_COUNT as COUNT(DISTINCT CASE WHEN trending.is_viral THEN trending.product_id END) comment='Number of currently viral products'
	)
	comment='Semantic view for reviews, social mentions, and influencer content'
	with extension (CA='{"tables":[{"name":"INFLUENCER","dimensions":[{"name":"CONTENT_TYPE"},{"name":"INFLUENCER_HANDLE"},{"name":"INFLUENCER_NAME"},{"name":"INFLUENCER_SKIN_TONE"},{"name":"IS_SPONSORED"},{"name":"MENTION_ID"},{"name":"PLATFORM"},{"name":"POST_URL"},{"name":"POSTED_AT"},{"name":"PRODUCT_ID"}],"facts":[{"name":"COMMENTS"},{"name":"ENGAGEMENT_RATE"},{"name":"FOLLOWER_COUNT"},{"name":"LIKES"},{"name":"VIEWS"}],"metrics":[{"name":"INFLUENCER_MENTION_COUNT"}]},{"name":"MENTION","dimensions":[{"name":"AUTHOR_HANDLE"},{"name":"CONTENT_TEXT"},{"name":"MENTION_ID"},{"name":"PLATFORM"},{"name":"POST_URL"},{"name":"POSTED_AT"},{"name":"PRODUCT_ID"},{"name":"SENTIMENT_LABEL"}],"facts":[{"name":"AUTHOR_FOLLOWER_COUNT"},{"name":"COMMENTS"},{"name":"LIKES"},{"name":"SENTIMENT_SCORE"},{"name":"SHARES"},{"name":"VIEWS"}],"metrics":[{"name":"MENTION_COUNT"},{"name":"TOTAL_ENGAGEMENT"}]},{"name":"PRODUCT","dimensions":[{"name":"BRAND"},{"name":"CATEGORY"},{"name":"NAME"},{"name":"PRODUCT_ID"},{"name":"SUBCATEGORY"}]},{"name":"REVIEW","dimensions":[{"name":"CREATED_AT"},{"name":"PLATFORM"},{"name":"PRODUCT_ID"},{"name":"REVIEW_ID"},{"name":"REVIEW_TEXT"},{"name":"REVIEWER_SKIN_TONE"},{"name":"REVIEWER_SKIN_TYPE"},{"name":"REVIEWER_UNDERTONE"},{"name":"TITLE"},{"name":"VERIFIED_PURCHASE"}],"facts":[{"name":"HELPFUL_VOTES"},{"name":"RATING"}],"metrics":[{"name":"AVG_RATING"},{"name":"REVIEW_COUNT"}]},{"name":"TRENDING","dimensions":[{"name":"IS_VIRAL"},{"name":"PRODUCT_ID"},{"name":"TREND_ID"},{"name":"VIRAL_REASON"}],"facts":[{"name":"MENTION_VELOCITY"},{"name":"TREND_RANK"},{"name":"TREND_SCORE"}],"metrics":[{"name":"VIRAL_PRODUCT_COUNT"}]}],"relationships":[{"name":"\\"SYS_RELATIONSHIP_00088877-a4e6-4cfc-9bd8-ce1a52e0ecd2\\""},{"name":"\\"SYS_RELATIONSHIP_645f3655-2533-4b91-aa56-09cd271cea6e\\""},{"name":"\\"SYS_RELATIONSHIP_c7ed9fdf-51d8-4d44-ac46-35ccac4edca9\\""},{"name":"\\"SYS_RELATIONSHIP_7e0fa7ad-7fbc-4ca3-9660-1981cbd0f14b\\""}],"verified_queries":[{"name":"reviews and ratings for product_id 026912b9-b508-421e-b807-7d265158b96a","sql":"SELECT\\n  product_id,\\n  COUNT(DISTINCT review_id) AS review_count,\\n  AVG(rating) AS avg_rating,\\n  MIN(rating) AS min_rating,\\n  MAX(rating) AS max_rating,\\n  MIN(created_at) AS earliest_review_date,\\n  MAX(created_at) AS latest_review_date\\nFROM\\n  review\\nWHERE\\n  product_id = ''026912b9-b508-421e-b807-7d265158b96a''\\n  AND created_at <= CURRENT_TIMESTAMP()\\nGROUP BY\\n  product_id\\nORDER BY\\n  latest_review_date DESC NULLS LAST\\n  /* Generated by Cortex Analyst (request_id: 0050ff61-d587-40f3-92d8-fabd7ef0a2dd) */","question":"reviews and ratings for product_id 026912b9-b508-421e-b807-7d265158b96a","verified_at":1774324738,"verified_by":"Amit Gupta","use_as_onboarding_question":false}]}');

USE SCHEMA CART_OLTP;

create or replace semantic view CART_SEMANTIC_VIEW
	tables (
		SESSION as AGENT_COMMERCE.CART_OLTP.CART_SESSIONS primary key (SESSION_ID) with synonyms=('checkout','cart','shopping cart','basket') comment='Cart/checkout sessions (Hybrid Table)',
		ITEM as AGENT_COMMERCE.CART_OLTP.CART_ITEMS primary key (ITEM_ID) with synonyms=('cart items','line items','items','products in cart') comment='Items in cart session (Hybrid Table)',
		ORDER_TBL as AGENT_COMMERCE.CART_OLTP.ORDERS primary key (ORDER_ID) with synonyms=('orders','purchases','transactions') comment='Completed orders (Hybrid Table)',
		ORDER_ITEM as AGENT_COMMERCE.CART_OLTP.ORDER_ITEMS primary key (ORDER_ITEM_ID) with synonyms=('order items','purchased items') comment='Items in completed order (Hybrid Table)',
		FULFILLMENT as AGENT_COMMERCE.CART_OLTP.FULFILLMENT_OPTIONS primary key (OPTION_ID) with synonyms=('shipping options','delivery options','fulfillment') comment='Available shipping/pickup options (Hybrid Table)',
		PRODUCT as AGENT_COMMERCE.PRODUCTS.PRODUCTS primary key (PRODUCT_ID) comment='Product catalog for category filtering'
	)
	relationships (
		ITEM(PRODUCT_ID) references PRODUCT(PRODUCT_ID),
		ITEM(SESSION_ID) references SESSION(SESSION_ID),
		ORDER_TBL(SESSION_ID) references SESSION(SESSION_ID),
		ORDER_ITEM(ORDER_ID) references ORDER_TBL(ORDER_ID),
		ORDER_ITEM(PRODUCT_ID) references PRODUCT(PRODUCT_ID)
	)
	facts (
		SESSION.SUBTOTAL_CENTS as session.subtotal_cents with synonyms=('subtotal','items total','cart subtotal') comment='Cart subtotal in cents',
		SESSION.TAX_CENTS as session.tax_cents comment='Tax amount in cents',
		SESSION.SHIPPING_CENTS as session.shipping_cents comment='Shipping cost in cents',
		SESSION.DISCOUNT_CENTS as session.discount_cents with synonyms=('discount','savings') comment='Discount amount in cents',
		SESSION.TOTAL_CENTS as session.total_cents with synonyms=('total','grand total','cart total') comment='Total amount in cents',
		SESSION.APPLIED_LOYALTY_POINTS as session.applied_loyalty_points comment='Loyalty points applied',
		ITEM.QUANTITY as item.quantity with synonyms=('qty','count') comment='Quantity of item',
		ITEM.UNIT_PRICE_CENTS as item.unit_price_cents comment='Price per unit in cents',
		ITEM.SUBTOTAL_CENTS as item.subtotal_cents comment='Line item subtotal in cents',
		ORDER_TBL.SUBTOTAL_CENTS as order_tbl.subtotal_cents comment='Order subtotal in cents',
		ORDER_TBL.TAX_CENTS as order_tbl.tax_cents comment='Order tax in cents',
		ORDER_TBL.SHIPPING_CENTS as order_tbl.shipping_cents comment='Order shipping in cents',
		ORDER_TBL.DISCOUNT_CENTS as order_tbl.discount_cents comment='Order discount in cents',
		ORDER_TBL.TOTAL_CENTS as order_tbl.total_cents comment='Order total in cents',
		FULFILLMENT.PRICE_CENTS as fulfillment.price_cents comment='Shipping option price in cents',
		FULFILLMENT.FREE_THRESHOLD_CENTS as fulfillment.free_threshold_cents comment='Minimum for free shipping in cents',
		FULFILLMENT.ESTIMATED_DAYS_MIN as fulfillment.estimated_days_min comment='Minimum delivery days',
		FULFILLMENT.ESTIMATED_DAYS_MAX as fulfillment.estimated_days_max comment='Maximum delivery days'
	)
	dimensions (
		SESSION.SESSION_ID as session.session_id comment='Unique session identifier',
		SESSION.CUSTOMER_ID as session.customer_id comment='Customer identifier',
		SESSION.STATUS as session.status with synonyms=('cart status','checkout status') comment='Status: active, pending_payment, completed, expired',
		SESSION.CURRENCY as session.currency comment='Currency code',
		SESSION.FULFILLMENT_TYPE as session.fulfillment_type with synonyms=('delivery type','shipping type') comment='Type: shipping or pickup',
		SESSION.IS_GIFT as session.is_gift comment='Whether order is a gift',
		SESSION.IS_VALID as session.is_valid comment='Whether checkout is valid',
		SESSION.CREATED_AT as session.created_at comment='When cart was created',
		SESSION.COMPLETED_AT as session.completed_at comment='When checkout completed',
		ITEM.ITEM_ID as item.item_id comment='Unique cart item ID',
		ITEM.SESSION_ID as item.session_id comment='Session this item belongs to',
		ITEM.PRODUCT_ID as item.product_id comment='Product in cart',
		ITEM.VARIANT_ID as item.variant_id comment='Variant in cart',
		ITEM.PRODUCT_NAME as item.product_name comment='Product name',
		ITEM.VARIANT_NAME as item.variant_name comment='Variant name',
		ITEM.ADDED_AT as item.added_at comment='When item was added',
		ORDER_TBL.ORDER_ID as order_tbl.order_id comment='Unique order identifier',
		ORDER_TBL.ORDER_NUMBER as order_tbl.order_number with synonyms=('order number','confirmation number') comment='Human-readable order number',
		ORDER_TBL.SESSION_ID as order_tbl.session_id comment='Original checkout session',
		ORDER_TBL.STATUS as order_tbl.status with synonyms=('order status','order state') comment='Status: pending, confirmed, shipped, delivered',
		ORDER_TBL.TRACKING_NUMBER as order_tbl.tracking_number comment='Shipment tracking number',
		ORDER_TBL.CREATED_AT as order_tbl.created_at comment='When order was placed',
		ORDER_TBL.SHIPPED_AT as order_tbl.shipped_at comment='When order shipped',
		ORDER_TBL.DELIVERED_AT as order_tbl.delivered_at comment='When order was delivered',
		ORDER_ITEM.ORDER_ITEM_ID as order_item.order_item_id comment='Unique order item ID',
		ORDER_ITEM.ORDER_ID as order_item.order_id comment='Order this item belongs to',
		ORDER_ITEM.PRODUCT_ID as order_item.product_id comment='Product purchased',
		ORDER_ITEM.PRODUCT_NAME as order_item.product_name comment='Product name at time of order',
		ORDER_ITEM.QUANTITY as order_item.quantity comment='Quantity purchased',
		ORDER_ITEM.UNIT_PRICE_CENTS as order_item.unit_price_cents comment='Unit price at time of order',
		ORDER_ITEM.SUBTOTAL_CENTS as order_item.subtotal_cents comment='Line subtotal at time of order',
		FULFILLMENT.OPTION_ID as fulfillment.option_id comment='Unique option ID',
		FULFILLMENT.NAME as fulfillment.name with synonyms=('shipping option','shipping method','delivery method') comment='Shipping option name',
		FULFILLMENT.FULFILLMENT_TYPE as fulfillment.fulfillment_type comment='Type: shipping or pickup',
		FULFILLMENT.CARRIER as fulfillment.carrier comment='Shipping carrier',
		PRODUCT.PRODUCT_ID as product.product_id comment='Product identifier',
		PRODUCT.CATEGORY as product.category with synonyms=('product category','product type') comment='Product category: face, lips, eyes, skincare, nails, tools, fragrance',
		PRODUCT.SUBCATEGORY as product.subcategory comment='Product subcategory',
		PRODUCT.BRAND as product.brand comment='Product brand',
		PRODUCT.NAME as product.name with synonyms=('product name') comment='Product name'
	)
	metrics (
		SESSION.CART_COUNT as COUNT(DISTINCT session.session_id) comment='Number of checkout sessions',
		SESSION.COMPLETED_CART_COUNT as COUNT(DISTINCT CASE WHEN session.status = 'completed' THEN session.session_id END) comment='Number of completed checkouts',
		SESSION.AVG_CART_VALUE as AVG(session.total_cents) / 100.0 with synonyms=('average order value','aov') comment='Average cart value in dollars',
		ITEM.TOTAL_ITEMS as SUM(item.quantity) comment='Total items across all carts',
		ORDER_TBL.ORDER_COUNT as COUNT(DISTINCT order_tbl.order_id) comment='Number of orders',
		ORDER_TBL.TOTAL_REVENUE as SUM(order_tbl.total_cents) / 100.0 with synonyms=('revenue','sales') comment='Total revenue in dollars'
	)
	comment='Semantic view for cart sessions, cart items, orders, and order items (Hybrid Tables)';

USE SCHEMA CUSTOMERS;

create or replace semantic view CUSTOMER_SEMANTIC_VIEW
	tables (
		CUSTOMER as AGENT_COMMERCE.CUSTOMERS.CUSTOMERS primary key (CUSTOMER_ID) with synonyms=('customers','users','members','shoppers','buyers') comment='Customer profiles with loyalty and skin profile information',
		ANALYSIS as AGENT_COMMERCE.CUSTOMERS.SKIN_ANALYSIS_HISTORY primary key (ANALYSIS_ID) with synonyms=('skin analysis','color analysis','beauty analysis','face analysis') comment='History of skin tone and color analysis sessions'
	)
	relationships (
		ANALYSIS(CUSTOMER_ID) references CUSTOMER(CUSTOMER_ID)
	)
	facts (
		CUSTOMER.POINTS_BALANCE as customer.points_balance with synonyms=('loyalty points','rewards points','points') comment='Current loyalty points balance',
		CUSTOMER.LIFETIME_POINTS as customer.lifetime_points comment='Total points earned over lifetime',
		ANALYSIS.CONFIDENCE_SCORE as analysis.confidence_score comment='Confidence score of the analysis (0-1)'
	)
	dimensions (
		CUSTOMER.CUSTOMER_ID as customer.customer_id comment='Unique customer identifier',
		CUSTOMER.EMAIL as customer.email comment='Customer email address',
		CUSTOMER.FIRST_NAME as customer.first_name comment='Customer first name',
		CUSTOMER.LAST_NAME as customer.last_name comment='Customer last name',
		CUSTOMER.LOYALTY_TIER as customer.loyalty_tier with synonyms=('tier','membership level','status') comment='Loyalty program tier: Bronze, Silver, Gold, Platinum',
		CUSTOMER.IS_ACTIVE as customer.is_active comment='Whether customer account is active',
		CUSTOMER.CREATED_AT as customer.created_at comment='Date customer joined',
		ANALYSIS.ANALYSIS_ID as analysis.analysis_id comment='Unique analysis session ID',
		ANALYSIS.CUSTOMER_ID as analysis.customer_id comment='Customer who was analyzed',
		ANALYSIS.SKIN_HEX as analysis.skin_hex with synonyms=('skin tone','skin shade','complexion','skin color') comment='Detected skin color in hex format',
		ANALYSIS.UNDERTONE as analysis.undertone with synonyms=('skin undertone','warm','cool','neutral') comment='Skin undertone: warm, cool, or neutral',
		ANALYSIS.FITZPATRICK_TYPE as analysis.fitzpatrick_type with synonyms=('fitzpatrick scale','fitzpatrick','skin type number') comment='Fitzpatrick skin type (1-6)',
		ANALYSIS.MONK_SHADE as analysis.monk_shade with synonyms=('monk skin tone','monk scale','mst') comment='Monk Skin Tone scale (1-10)',
		ANALYSIS.MAKEUP_DETECTED as analysis.makeup_detected comment='Whether makeup was detected during analysis',
		ANALYSIS.ANALYZED_AT as analysis.analyzed_at comment='When the analysis was performed'
	)
	metrics (
		CUSTOMER.CUSTOMER_COUNT as COUNT(DISTINCT customer.customer_id) comment='Number of customers',
		CUSTOMER.AVG_POINTS as AVG(customer.points_balance) comment='Average loyalty points balance',
		CUSTOMER.TOTAL_POINTS as SUM(customer.points_balance) comment='Total loyalty points across customers',
		ANALYSIS.ANALYSIS_COUNT as COUNT(DISTINCT analysis.analysis_id) comment='Number of skin analyses performed'
	)
	comment='Semantic view for customer data, loyalty, and skin analysis';

USE SCHEMA INVENTORY;

create or replace semantic view INVENTORY_SEMANTIC_VIEW
	tables (
		LOCATION as AGENT_COMMERCE.INVENTORY.LOCATIONS primary key (LOCATION_ID) with synonyms=('locations','stores','warehouses','shops') comment='Physical store and warehouse locations',
		STOCK as AGENT_COMMERCE.INVENTORY.STOCK_LEVELS primary key (STOCK_ID) with synonyms=('inventory','stock','availability','quantities') comment='Current stock levels by location',
		PRODUCT as AGENT_COMMERCE.PRODUCTS.PRODUCTS primary key (PRODUCT_ID) comment='Product catalog for category filtering'
	)
	relationships (
		STOCK(LOCATION_ID) references LOCATION(LOCATION_ID),
		STOCK(PRODUCT_ID) references PRODUCT(PRODUCT_ID)
	)
	facts (
		LOCATION.LATITUDE as location.latitude comment='Location latitude',
		LOCATION.LONGITUDE as location.longitude comment='Location longitude',
		STOCK.QUANTITY_ON_HAND as stock.quantity_on_hand with synonyms=('on hand','available','in stock','qty') comment='Total quantity on hand',
		STOCK.QUANTITY_RESERVED as stock.quantity_reserved with synonyms=('reserved','held','allocated') comment='Quantity reserved for orders',
		STOCK.REORDER_POINT as stock.reorder_point comment='Quantity threshold to trigger reorder',
		STOCK.REORDER_QUANTITY as stock.reorder_quantity comment='Standard reorder quantity'
	)
	dimensions (
		LOCATION.LOCATION_ID as location.location_id comment='Unique location identifier',
		LOCATION.NAME as location.name with synonyms=('store name','warehouse name','location name') comment='Location name',
		LOCATION.LOCATION_TYPE as location.location_type with synonyms=('type') comment='Type: warehouse, store, popup',
		LOCATION.LOCATION_CODE as location.location_code comment='Location code',
		LOCATION.CITY as location.city comment='City',
		LOCATION.STATE as location.state comment='State/Province',
		LOCATION.POSTAL_CODE as location.postal_code with synonyms=('zip','zip code') comment='Postal/ZIP code',
		LOCATION.COUNTRY as location.country comment='Country code',
		LOCATION.IS_ACTIVE as location.is_active comment='Whether location is active',
		LOCATION.IS_PICKUP_ENABLED as location.is_pickup_enabled with synonyms=('bopis','buy online pickup in store','curbside','pickup available') comment='Whether pickup is available',
		STOCK.STOCK_ID as stock.stock_id comment='Unique stock record identifier',
		STOCK.PRODUCT_ID as stock.product_id comment='Product identifier',
		STOCK.VARIANT_ID as stock.variant_id comment='Variant identifier',
		STOCK.LOCATION_ID as stock.location_id comment='Location identifier',
		STOCK.LAST_RESTOCK_DATE as stock.last_restock_date comment='Date of last restock',
		PRODUCT.PRODUCT_ID as product.product_id comment='Product identifier',
		PRODUCT.CATEGORY as product.category with synonyms=('product category','product type') comment='Product category: face, lips, eyes, skincare, nails, tools, fragrance',
		PRODUCT.SUBCATEGORY as product.subcategory comment='Product subcategory',
		PRODUCT.BRAND as product.brand comment='Product brand',
		PRODUCT.NAME as product.name with synonyms=('product name') comment='Product name'
	)
	metrics (
		LOCATION.LOCATION_COUNT as COUNT(DISTINCT location.location_id) comment='Number of locations',
		STOCK.TOTAL_ON_HAND as SUM(stock.quantity_on_hand) comment='Total quantity on hand across locations',
		STOCK.TOTAL_RESERVED as SUM(stock.quantity_reserved) comment='Total quantity reserved',
		STOCK.TOTAL_AVAILABLE as SUM(stock.quantity_on_hand - stock.quantity_reserved) with synonyms=('available inventory','sellable inventory') comment='Total available inventory (on hand minus reserved)',
		STOCK.LOW_STOCK_COUNT as COUNT(DISTINCT CASE WHEN stock.quantity_on_hand <= stock.reorder_point THEN stock.stock_id END) comment='Number of products at or below reorder point'
	)
	comment='Semantic view for inventory levels and store locations';

