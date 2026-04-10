import streamlit as st
from snowflake.snowpark.context import get_active_session
import pandas as pd

st.set_page_config(
    page_title="Executive Product 360",
    page_icon="📊",
    layout="wide",
    initial_sidebar_state="collapsed"
)

ACCENT = "#29B5E8"
SUCCESS = "#21C354"
WARNING = "#FACA2B"
DANGER = "#FF4B4B"

st.markdown("""
<style>
    .main-header {
        font-size: 2.5rem;
        font-weight: 700;
        color: #1E1E1E;
        margin-bottom: 0.5rem;
    }
    .sub-header {
        font-size: 1rem;
        color: #666;
        margin-bottom: 2rem;
    }
    .metric-card {
        background: linear-gradient(135deg, #ffffff 0%, #f8f9fa 100%);
        border-radius: 12px;
        padding: 1.5rem;
        box-shadow: 0 2px 8px rgba(0,0,0,0.08);
        border-left: 4px solid;
        height: 140px;
    }
    .metric-label {
        font-size: 0.85rem;
        color: #666;
        font-weight: 500;
        text-transform: uppercase;
        letter-spacing: 0.5px;
    }
    .metric-value {
        font-size: 2.2rem;
        font-weight: 700;
        color: #1E1E1E;
        margin: 0.25rem 0;
    }
    .metric-delta-positive {
        color: #21C354;
        font-size: 0.9rem;
        font-weight: 600;
    }
    .metric-delta-negative {
        color: #FF4B4B;
        font-size: 0.9rem;
        font-weight: 600;
    }
    .section-title {
        font-size: 1.25rem;
        font-weight: 600;
        color: #1E1E1E;
        margin: 2rem 0 1rem 0;
        padding-bottom: 0.5rem;
        border-bottom: 2px solid #f0f0f0;
    }
    .intelligence-btn {
        background: linear-gradient(135deg, #29B5E8 0%, #1a8fc7 100%);
        color: white;
        padding: 12px 24px;
        border-radius: 8px;
        text-decoration: none;
        font-weight: 600;
        display: inline-flex;
        align-items: center;
        gap: 8px;
        transition: transform 0.2s, box-shadow 0.2s;
    }
    .intelligence-btn:hover {
        transform: translateY(-2px);
        box-shadow: 0 4px 12px rgba(41, 181, 232, 0.4);
    }
</style>
""", unsafe_allow_html=True)

@st.cache_resource
def get_session():
    return get_active_session()

@st.cache_data(ttl=300)
def get_revenue_metrics():
    session = get_session()
    df = session.sql("""
        SELECT 
            COALESCE(SUM(total_cents) / 100.0, 0) as total_revenue,
            COUNT(DISTINCT order_id) as total_orders,
            AVG(total_cents) / 100.0 as avg_order_value
        FROM AGENT_COMMERCE.CART_OLTP.ORDERS
    """).to_pandas()
    return df

@st.cache_data(ttl=300)
def get_customer_metrics():
    session = get_session()
    df = session.sql("""
        SELECT 
            COUNT(DISTINCT customer_id) as total_customers,
            COUNT(DISTINCT CASE WHEN is_active = TRUE THEN customer_id END) as active_customers,
            SUM(points_balance) as total_points
        FROM AGENT_COMMERCE.CUSTOMERS.CUSTOMERS
    """).to_pandas()
    return df

@st.cache_data(ttl=300)
def get_inventory_metrics():
    session = get_session()
    df = session.sql("""
        SELECT 
            COUNT(DISTINCT location_id) as total_locations,
            SUM(quantity_on_hand) as total_units,
            COUNT(CASE WHEN quantity_on_hand < reorder_point THEN 1 END) as low_stock_count
        FROM AGENT_COMMERCE.INVENTORY.STOCK_LEVELS
    """).to_pandas()
    return df

@st.cache_data(ttl=300)
def get_social_metrics():
    session = get_session()
    df = session.sql("""
        SELECT 
            COUNT(*) as total_reviews,
            ROUND(AVG(rating), 2) as avg_rating
        FROM AGENT_COMMERCE.SOCIAL.PRODUCT_REVIEWS
    """).to_pandas()
    return df

@st.cache_data(ttl=300)
def get_product_metrics():
    session = get_session()
    df = session.sql("""
        SELECT COUNT(DISTINCT product_id) as total_products
        FROM AGENT_COMMERCE.PRODUCTS.PRODUCTS
    """).to_pandas()
    return df

@st.cache_data(ttl=300)
def get_loyalty_breakdown():
    session = get_session()
    df = session.sql("""
        SELECT 
            loyalty_tier,
            COUNT(*) as customer_count
        FROM AGENT_COMMERCE.CUSTOMERS.CUSTOMERS
        GROUP BY loyalty_tier
        ORDER BY customer_count DESC
    """).to_pandas()
    return df

@st.cache_data(ttl=300)
def get_category_breakdown():
    session = get_session()
    df = session.sql("""
        SELECT 
            category,
            COUNT(*) as product_count,
            ROUND(AVG(current_price), 2) as avg_price
        FROM AGENT_COMMERCE.PRODUCTS.PRODUCTS
        GROUP BY category
        ORDER BY product_count DESC
        LIMIT 10
    """).to_pandas()
    return df

@st.cache_data(ttl=300)
def get_low_stock_items():
    session = get_session()
    df = session.sql("""
        SELECT 
            p.name as product_name,
            i.quantity_on_hand,
            i.reorder_point,
            l.city as location
        FROM AGENT_COMMERCE.INVENTORY.STOCK_LEVELS i
        JOIN AGENT_COMMERCE.PRODUCTS.PRODUCTS p ON i.product_id = p.product_id
        JOIN AGENT_COMMERCE.INVENTORY.LOCATIONS l ON i.location_id = l.location_id
        WHERE i.quantity_on_hand < i.reorder_point
        ORDER BY i.quantity_on_hand ASC
        LIMIT 10
    """).to_pandas()
    return df

@st.cache_data(ttl=300)
def get_top_rated_products():
    session = get_session()
    df = session.sql("""
        SELECT 
            p.name as product_name,
            p.brand,
            ROUND(AVG(r.rating), 2) as avg_rating,
            COUNT(r.review_id) as review_count
        FROM AGENT_COMMERCE.SOCIAL.PRODUCT_REVIEWS r
        JOIN AGENT_COMMERCE.PRODUCTS.PRODUCTS p ON r.product_id = p.product_id
        GROUP BY p.name, p.brand
        HAVING COUNT(r.review_id) >= 5
        ORDER BY avg_rating DESC, review_count DESC
        LIMIT 10
    """).to_pandas()
    return df

def format_currency(value):
    if value >= 1000000:
        return f"${value/1000000:.1f}M"
    elif value >= 1000:
        return f"${value/1000:.1f}K"
    return f"${value:,.0f}"

def format_number(value):
    if value >= 1000000:
        return f"{value/1000000:.1f}M"
    elif value >= 1000:
        return f"{value/1000:.1f}K"
    return f"{value:,.0f}"

col_header, col_btn = st.columns([3, 1])
with col_header:
    st.markdown('<p class="main-header">📊 Executive Product 360</p>', unsafe_allow_html=True)
    st.markdown('<p class="sub-header">Real-time business intelligence dashboard</p>', unsafe_allow_html=True)

with col_btn:
    st.markdown("""
    <a href="https://ai.snowflake.com/sfsehol/si_ae_enablement_retail_kvldzi/#/ai" 
       class="intelligence-btn" target="_blank">
        💬 Ask Snowflake Intelligence
    </a>
    """, unsafe_allow_html=True)

try:
    revenue = get_revenue_metrics()
    customers = get_customer_metrics()
    inventory = get_inventory_metrics()
    social = get_social_metrics()
    products = get_product_metrics()

    total_revenue = revenue['TOTAL_REVENUE'].iloc[0] if not revenue.empty else 0
    total_orders = revenue['TOTAL_ORDERS'].iloc[0] if not revenue.empty else 0
    aov = revenue['AVG_ORDER_VALUE'].iloc[0] if not revenue.empty else 0
    total_customers = customers['TOTAL_CUSTOMERS'].iloc[0] if not customers.empty else 0
    active_customers = customers['ACTIVE_CUSTOMERS'].iloc[0] if not customers.empty else 0
    total_points = customers['TOTAL_POINTS'].iloc[0] if not customers.empty else 0
    total_locations = inventory['TOTAL_LOCATIONS'].iloc[0] if not inventory.empty else 0
    total_units = inventory['TOTAL_UNITS'].iloc[0] if not inventory.empty else 0
    low_stock = inventory['LOW_STOCK_COUNT'].iloc[0] if not inventory.empty else 0
    total_reviews = social['TOTAL_REVIEWS'].iloc[0] if not social.empty else 0
    avg_rating = social['AVG_RATING'].iloc[0] if not social.empty else 0
    total_products = products['TOTAL_PRODUCTS'].iloc[0] if not products.empty else 0

    col1, col2, col3, col4 = st.columns(4)
    
    with col1:
        st.markdown(f"""
        <div class="metric-card" style="border-color: {ACCENT};">
            <p class="metric-label">💰 Total Revenue</p>
            <p class="metric-value">{format_currency(total_revenue)}</p>
            <p class="metric-delta-positive">↑ From {format_number(total_orders)} orders</p>
        </div>
        """, unsafe_allow_html=True)
    
    with col2:
        st.markdown(f"""
        <div class="metric-card" style="border-color: {SUCCESS};">
            <p class="metric-label">👥 Active Customers</p>
            <p class="metric-value">{format_number(active_customers)}</p>
            <p class="metric-delta-positive">↑ {format_number(total_points)} loyalty points</p>
        </div>
        """, unsafe_allow_html=True)
    
    with col3:
        st.markdown(f"""
        <div class="metric-card" style="border-color: {WARNING};">
            <p class="metric-label">📦 Inventory Units</p>
            <p class="metric-value">{format_number(total_units)}</p>
            <p class="metric-delta-negative">⚠️ {format_number(low_stock)} low stock alerts</p>
        </div>
        """, unsafe_allow_html=True)
    
    with col4:
        st.markdown(f"""
        <div class="metric-card" style="border-color: {SUCCESS};">
            <p class="metric-label">⭐ Avg Rating</p>
            <p class="metric-value">{avg_rating:.1f}</p>
            <p class="metric-delta-positive">↑ From {format_number(total_reviews)} reviews</p>
        </div>
        """, unsafe_allow_html=True)

    st.markdown("---")

    col_left, col_right = st.columns(2)
    
    with col_left:
        st.markdown('<p class="section-title">👥 Customer Loyalty Distribution</p>', unsafe_allow_html=True)
        loyalty_df = get_loyalty_breakdown()
        if not loyalty_df.empty:
            st.bar_chart(loyalty_df.set_index('LOYALTY_TIER')['CUSTOMER_COUNT'])
        
        st.markdown('<p class="section-title">🏷️ Product Categories</p>', unsafe_allow_html=True)
        category_df = get_category_breakdown()
        if not category_df.empty:
            st.dataframe(
                category_df.rename(columns={
                    'CATEGORY': 'Category',
                    'PRODUCT_COUNT': 'Products',
                    'AVG_PRICE': 'Avg Price ($)'
                }),
                use_container_width=True
            )
    
    with col_right:
        st.markdown('<p class="section-title">⚠️ Low Stock Alerts</p>', unsafe_allow_html=True)
        low_stock_df = get_low_stock_items()
        if not low_stock_df.empty:
            st.dataframe(
                low_stock_df.rename(columns={
                    'PRODUCT_NAME': 'Product',
                    'QUANTITY_ON_HAND': 'On Hand',
                    'REORDER_POINT': 'Reorder At',
                    'LOCATION': 'Location'
                }),
                use_container_width=True
            )
        else:
            st.info("No low stock items")
        
        st.markdown('<p class="section-title">⭐ Top Rated Products</p>', unsafe_allow_html=True)
        top_rated_df = get_top_rated_products()
        if not top_rated_df.empty:
            st.dataframe(
                top_rated_df.rename(columns={
                    'PRODUCT_NAME': 'Product',
                    'BRAND': 'Brand',
                    'AVG_RATING': 'Rating',
                    'REVIEW_COUNT': 'Reviews'
                }),
                use_container_width=True
            )

    st.markdown("---")
    
    col_info1, col_info2, col_info3 = st.columns(3)
    with col_info1:
        st.metric("Total Products", format_number(total_products))
    with col_info2:
        st.metric("Warehouse Locations", format_number(total_locations))
    with col_info3:
        st.metric("Avg Order Value", format_currency(aov))

except Exception as e:
    st.error(f"Error loading data: {str(e)}")
    st.info("This dashboard requires connection to the AGENT_COMMERCE database.")

st.markdown("""
<div style="text-align: center; padding: 2rem; color: #888; font-size: 0.85rem;">
    Executive Product 360 Dashboard | Powered by Snowflake Cortex
</div>
""", unsafe_allow_html=True)
