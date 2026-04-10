"""
Agent Commerce - SPCS Backend
==============================
FastAPI backend for face recognition, skin analysis, and color matching.
Deployed as Snowpark Container Service.

ARCHITECTURE MODES (Toggle via USE_AGENT_FACE_ANALYSIS env var):
================================================================

V1 - Backend-Analyzed (Default, USE_AGENT_FACE_ANALYSIS=false):
  - Face analysis done LOCALLY in this backend using dlib/mediapipe
  - Pre-analyzed data (embedding, skin_hex) passed to agent in message
  - Agent receives enriched message, calls IdentifyCustomer, MatchProducts
  - Agent instructions: Expect pre-analyzed data in message

V2 - Agent-Orchestrated (USE_AGENT_FACE_ANALYSIS=true):
  - Backend passes base64 image to agent WITHOUT local analysis
  - Agent calls TOOL_ANALYZE_FACE (ML Model Registry service)
  - Agent receives analysis, then calls IdentifyCustomer, MatchProducts
  - Agent instructions: Call AnalyzeFace tool first

Toggle:
  - V1 → V2: Set USE_AGENT_FACE_ANALYSIS=true, update agent instructions
  - V2 → V1: Set USE_AGENT_FACE_ANALYSIS=false, revert agent instructions

IMPORTANT COMPATIBILITY NOTES:
- The Cortex Agent (11_create_cortex_agent.sql) must have matching 
  orchestration instructions for the selected mode.
- Generic tool input_schemas must have ALL parameters in 'required' list to
  avoid "unsupported parameter type: <nil>" errors. See REQUIRED_PARAMS_FIX
  annotations in 11_create_cortex_agent.sql.

Endpoints:
    - POST /health - Health check
    - POST /extract-embedding - Extract face embedding from image
    - POST /analyze-skin - Analyze skin tone and type
    - POST /match-products - Find matching products by color
    - POST /batch-extract - Batch process multiple images
"""

import os
import io
import json
import base64
import logging
from typing import List, Optional, Dict, Any
from datetime import datetime
from pathlib import Path

import numpy as np
from fastapi import FastAPI, HTTPException, UploadFile, File, Form, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles
from fastapi.responses import FileResponse, JSONResponse
from pydantic import BaseModel

# Snowflake connectivity for Cortex Agent
import httpx
import asyncio
from typing import AsyncGenerator

# SPCS provides these environment variables for authentication
SNOWFLAKE_ACCOUNT = os.environ.get("SNOWFLAKE_ACCOUNT", "")
SNOWFLAKE_HOST = os.environ.get("SNOWFLAKE_HOST", "")  # e.g., account.snowflakecomputing.com

# ============================================================================
# FEATURE FLAG: V1 vs V2 Face Analysis
# ============================================================================
# V1 (False/Default): Backend does local face analysis, embeds results in message
# V2 (True): Backend passes image to agent, agent calls TOOL_ANALYZE_FACE
# 
# Toggle: Set USE_AGENT_FACE_ANALYSIS=true in environment to enable V2
# Revert: Set USE_AGENT_FACE_ANALYSIS=false or unset to use V1
# ============================================================================
USE_AGENT_FACE_ANALYSIS = os.environ.get("USE_AGENT_FACE_ANALYSIS", "false").lower() == "true"

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# ============================================================================
# CORTEX AGENT REST API INTEGRATION
# ============================================================================
# Uses the Cortex Agent REST API with SSE streaming
# Docs: https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-agents-run
# ============================================================================

# Agent configuration
AGENT_DATABASE = "AGENT_COMMERCE"
AGENT_SCHEMA = "UTIL"
AGENT_NAME = "AGENTIC_COMMERCE_ASSISTANT"

# Thread storage for conversation continuity
_agent_threads: Dict[str, Dict] = {}


def get_spcs_token() -> Optional[str]:
    """
    Get the OAuth token from SPCS environment.
    In SPCS, the token is available at /snowflake/session/token
    """
    token_path = "/snowflake/session/token"
    try:
        if os.path.exists(token_path):
            with open(token_path, 'r') as f:
                token = f.read().strip()
                logger.info("✅ Got SPCS OAuth token")
                return token
    except Exception as e:
        logger.warning(f"Could not read SPCS token: {e}")
    
    # Fallback: check environment variable (for local dev)
    token = os.environ.get("SNOWFLAKE_TOKEN")
    if token:
        logger.info("✅ Got token from environment variable")
        return token
    
    return None


def get_snowflake_host() -> str:
    """Get the Snowflake host for API calls."""
    # In SPCS, use the host from environment or construct from account
    host = os.environ.get("SNOWFLAKE_HOST")
    if host:
        return host
    
    account = os.environ.get("SNOWFLAKE_ACCOUNT", "")
    if account:
        # Convert account to host format
        # e.g., "xy12345.us-east-1" -> "xy12345.us-east-1.snowflakecomputing.com"
        if ".snowflakecomputing.com" not in account:
            return f"{account}.snowflakecomputing.com"
        return account
    
    return ""


async def invoke_cortex_agent_rest(
    message: str, 
    session_id: str, 
    conversation_history: List[Dict] = None
) -> Dict[str, Any]:
    """
    Invoke the Cortex Agent via REST API with SSE streaming.
    
    Uses: POST /api/v2/databases/{db}/schemas/{schema}/agents/{name}:run
    
    Message should already be enriched with any image analysis data.
    
    Returns accumulated response from all SSE events.
    """
    token = get_spcs_token()
    host = get_snowflake_host()
    
    if not token:
        logger.warning("No authentication token available")
        return {"success": False, "error": "No authentication token"}
    
    if not host:
        logger.warning("No Snowflake host configured")
        return {"success": False, "error": "No Snowflake host configured"}
    
    # Build the API URL
    api_url = f"https://{host}/api/v2/databases/{AGENT_DATABASE}/schemas/{AGENT_SCHEMA}/agents/{AGENT_NAME}:run"
    
    # Build messages array with proper format
    messages = []
    
    # Add conversation history if provided (skip empty messages)
    if conversation_history:
        for msg in conversation_history:
            content = msg.get("content", "")
            if content and content.strip():  # Skip empty messages
                messages.append({
                    "role": msg.get("role", "user"),
                    "content": [{"type": "text", "text": content}]
                })
    
    # Add current user message (already enriched with analysis data if image was uploaded)
    messages.append({
        "role": "user",
        "content": [{"type": "text", "text": message}]
    })
    
    # Build request body
    request_body = {
        "messages": messages
    }
    
    # Add thread info if we have it for this session
    if session_id in _agent_threads:
        thread_info = _agent_threads[session_id]
        request_body["thread_id"] = thread_info.get("thread_id")
        request_body["parent_message_id"] = thread_info.get("last_message_id", 0)
    
    headers = {
        "Authorization": f"Bearer {token}",
        "Content-Type": "application/json",
        "Accept": "text/event-stream"
    }
    
    logger.info(f"📤 Calling Cortex Agent API: {api_url}")
    logger.info(f"📤 Message content: {message[:200] if message else '(empty)'}")
    logger.info(f"📤 Messages count: {len(messages)}")
    
    try:
        async with httpx.AsyncClient(timeout=120.0) as client:
            async with client.stream(
                "POST",
                api_url,
                json=request_body,
                headers=headers
            ) as response:
                
                if response.status_code != 200:
                    error_text = await response.aread()
                    logger.error(f"Agent API error {response.status_code}: {error_text}")
                    return {
                        "success": False,
                        "error": f"API error {response.status_code}: {error_text.decode()}"
                    }
                
                # Parse SSE events and accumulate response
                accumulated_text = ""
                accumulated_thinking = ""
                tools_used = []
                tool_results = []
                tables = []
                thread_id = None
                message_id = None
                
                line_count = 0
                current_event_type = None
                
                async for line in response.aiter_lines():
                    line_count += 1
                    # Log first 10 lines for debugging
                    if line_count <= 10:
                        logger.info(f"📨 SSE line {line_count}: {line[:200] if line else '(empty)'}")
                    
                    if not line:
                        continue
                    
                    # Parse event type line
                    if line.startswith("event:"):
                        current_event_type = line[6:].strip()
                        continue
                    
                    # Parse data line
                    if not line.startswith("data:"):
                        continue
                    
                    data_str = line[5:].strip()  # Remove "data:" prefix
                    if not data_str or data_str == "[DONE]":
                        continue
                    
                    try:
                        event_data = json.loads(data_str)
                    except json.JSONDecodeError:
                        logger.warning(f"⚠️ Could not parse SSE data: {data_str[:100]}")
                        continue
                    
                    # Use event type from "event:" line, or fall back to "type" in data
                    event_type = current_event_type or event_data.get("type", "")
                    
                    # Handle different event types
                    if event_type == "response.text.delta":
                        # Accumulate text response - text can be in different places
                        text = event_data.get("text", "")
                        if not text:
                            delta = event_data.get("delta", {})
                            text = delta.get("text", "")
                        accumulated_text += text
                        
                    elif event_type == "response.thinking.delta":
                        # Agent thinking - accumulate for optional display
                        thinking_text = event_data.get("text", "")
                        if thinking_text:
                            accumulated_thinking += thinking_text
                            if line_count <= 15:
                                logger.info(f"🤔 Agent thinking: {thinking_text[:100]}")
                    
                    elif event_type == "response.tool_use":
                        # Tool was invoked
                        tool_info = {
                            "tool_use_id": event_data.get("tool_use_id"),
                            "type": event_data.get("tool_type"),
                            "name": event_data.get("name"),
                            "input": event_data.get("input")
                        }
                        tools_used.append(tool_info)
                        logger.info(f"🔧 Tool used: {tool_info['name']}")
                    
                    elif event_type == "response.tool_result":
                        # Tool result received
                        tool_result = {
                            "tool_use_id": event_data.get("tool_use_id"),
                            "name": event_data.get("name"),
                            "status": event_data.get("status"),
                            "content": event_data.get("content")
                        }
                        tool_results.append(tool_result)
                    
                    elif event_type == "response.table":
                        # Table data
                        tables.append(event_data.get("content"))
                    
                    elif event_type == "metadata":
                        # Extract thread/message IDs for continuity
                        thread_id = event_data.get("thread_id")
                        message_id = event_data.get("message_id")
                    
                    elif event_type == "response.status":
                        status = event_data.get("status")
                        logger.info(f"📊 Agent status: {status}")
                    
                    elif event_type == "error":
                        error_msg = event_data.get("message", "Unknown error")
                        logger.error(f"❌ Agent error: {error_msg}")
                        return {"success": False, "error": error_msg}
                
                # Store thread info for next message
                if thread_id:
                    _agent_threads[session_id] = {
                        "thread_id": thread_id,
                        "last_message_id": message_id or 0
                    }
                
                logger.info(f"✅ Agent response received ({len(accumulated_text)} chars, {len(tools_used)} tools, {len(tool_results)} results, {len(tables)} tables)")
                
                # Debug log tool results
                for tr in tool_results:
                    logger.info(f"🔧 Tool result: name={tr.get('name')}, content_type={type(tr.get('content'))}")
                
                # Extract structured products from multiple sources
                extracted_products = []
                product_lookup = {}  # UUID -> full product data (for Option 1 filtering)
                customer_match = None
                cart_update = None
                
                # OPTION 1 FIX: Parse products mentioned in agent's TEXT response
                # Pattern: **Product Name** (ID: uuid) - $XX.XX
                def parse_products_from_agent_text(text: str) -> list:
                    """Extract product UUIDs mentioned in agent's formatted text."""
                    import re
                    # Match: **Product Name** (ID: uuid-here) - $price
                    pattern = r'\*\*([^*]+)\*\*\s*\(ID:\s*([a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12})\)\s*-?\s*\$?([\d.]+)?'
                    matches = re.findall(pattern, text, re.IGNORECASE)
                    
                    products = []
                    for name, uuid, price in matches:
                        products.append({
                            "name": name.strip(),
                            "product_id": uuid.lower(),
                            "price": float(price) if price else 0
                        })
                    logger.info(f"📝 Parsed {len(products)} products from agent text (by UUID)")
                    return products
                
                # Helper function to extract product from dict
                def extract_product(item):
                    if not isinstance(item, dict):
                        return None
                    name = item.get("name") or item.get("NAME") or item.get("PRODUCT_NAME")
                    if not name:
                        return None
                    return {
                        "product_id": item.get("product_id") or item.get("PRODUCT_ID") or "",
                        "name": name,
                        "brand": item.get("brand") or item.get("BRAND") or "",
                        "category": item.get("category") or item.get("CATEGORY") or "",
                        "swatch_hex": item.get("swatch_hex") or item.get("SWATCH_HEX") or item.get("color_hex") or item.get("COLOR_HEX") or "#f0f0f0",
                        "color_distance": item.get("color_distance") or item.get("COLOR_DISTANCE") or 5,
                        "price": item.get("price") or item.get("PRICE") or item.get("current_price") or item.get("CURRENT_PRICE") or 0,
                        "image_url": item.get("image_url") or item.get("IMAGE_URL") or item.get("hero_image_url") or item.get("HERO_IMAGE_URL") or "",
                    }
                
                # Helper function to extract customer match from dict
                def extract_customer_match(item):
                    if not isinstance(item, dict):
                        return None
                    customer_id = item.get("customer_id") or item.get("CUSTOMER_ID")
                    first_name = item.get("first_name") or item.get("FIRST_NAME")
                    if not customer_id or not first_name:
                        return None
                    
                    # Calculate confidence from distance (lower distance = higher confidence)
                    distance = item.get("distance") or item.get("DISTANCE") or 0.5
                    match_confidence = item.get("match_confidence") or item.get("MATCH_CONFIDENCE")
                    if match_confidence is None:
                        match_confidence = max(0, 1 - float(distance)) if distance else 0.5
                    
                    return {
                        "customer_id": customer_id,
                        "first_name": first_name,
                        "last_name": item.get("last_name") or item.get("LAST_NAME") or "",
                        "email": item.get("email") or item.get("EMAIL") or "",
                        "loyalty_tier": item.get("loyalty_tier") or item.get("LOYALTY_TIER") or "Member",
                        "points_balance": item.get("points_balance") or item.get("POINTS_BALANCE") or 0,
                        "confidence": float(match_confidence),
                    }
                
                # Source 1: Tool results (from generic functions like MatchProducts)
                for tr in tool_results:
                    tool_name = (tr.get("name") or "").lower()
                    content = tr.get("content")
                    
                    logger.info(f"🔍 Checking tool: {tool_name}")
                    
                    # Unwrap Cortex Agent response format: [{'json': {...}, 'type': 'json'}]
                    if isinstance(content, list) and len(content) > 0:
                        first_item = content[0]
                        if isinstance(first_item, dict) and 'json' in first_item and 'type' in first_item:
                            unwrapped = first_item.get('json', {})
                            logger.info(f"📦 Unwrapped Cortex response: {str(unwrapped)[:200]}")
                            # Check if it's an error response
                            if isinstance(unwrapped, dict) and 'error' in unwrapped and not unwrapped.get('error'):
                                # Empty error object means silent failure - skip
                                logger.warning(f"⚠️ Tool {tool_name} returned empty error response")
                            else:
                                # Replace content with unwrapped data
                                if isinstance(unwrapped, list):
                                    content = unwrapped
                                elif isinstance(unwrapped, dict):
                                    content = unwrapped
                    
                    # Handle product-related tools
                    if any(kw in tool_name for kw in ["match", "product", "search", "analyst"]):
                        logger.info(f"📦 Found product tool, content type: {type(content)}")
                        
                        if isinstance(content, list):
                            for item in content:
                                prod = extract_product(item)
                                if prod:
                                    extracted_products.append(prod)
                        elif isinstance(content, dict):
                            # UX_FIX (2026-01-04): Handle Cortex Agent wrapper format
                            # Tool results come as {'query_id': '...', 'result': '[JSON string]'}
                            result_data = content.get("result")
                            if result_data:
                                # Parse the result - it's usually a JSON string
                                if isinstance(result_data, str):
                                    try:
                                        parsed_result = json.loads(result_data)
                                        if isinstance(parsed_result, list):
                                            for item in parsed_result:
                                                prod = extract_product(item)
                                                if prod:
                                                    extracted_products.append(prod)
                                            logger.info(f"📦 Extracted {len(extracted_products)} products from result key")
                                        elif isinstance(parsed_result, dict):
                                            prod = extract_product(parsed_result)
                                            if prod:
                                                extracted_products.append(prod)
                                    except json.JSONDecodeError:
                                        logger.warning(f"⚠️ Failed to parse result as JSON")
                                elif isinstance(result_data, list):
                                    for item in result_data:
                                        prod = extract_product(item)
                                        if prod:
                                            extracted_products.append(prod)
                            else:
                                # Fallback: check for rows/data/results keys
                                rows = content.get("rows") or content.get("data") or content.get("results") or []
                                if isinstance(rows, list):
                                    for item in rows:
                                        prod = extract_product(item)
                                        if prod:
                                            extracted_products.append(prod)
                                else:
                                    prod = extract_product(content)
                                    if prod:
                                        extracted_products.append(prod)
                        elif isinstance(content, str):
                            try:
                                parsed = json.loads(content)
                                if isinstance(parsed, list):
                                    for item in parsed:
                                        prod = extract_product(item)
                                        if prod:
                                            extracted_products.append(prod)
                                elif isinstance(parsed, dict):
                                    rows = parsed.get("rows") or parsed.get("data") or []
                                    for item in rows:
                                        prod = extract_product(item)
                                        if prod:
                                            extracted_products.append(prod)
                            except json.JSONDecodeError:
                                pass
                    
                    # Handle Customer Identification tool results
                    if "identify" in tool_name or "customer" in tool_name:
                        logger.info(f"👤 Found customer identification tool, content type: {type(content)}")
                        logger.info(f"👤 Content preview: {str(content)[:500]}")
                        
                        matches_to_check = []
                        
                        # First unwrap Cortex Agent format if present
                        actual_content = content
                        if isinstance(content, list) and len(content) > 0:
                            first_item = content[0]
                            if isinstance(first_item, dict) and 'json' in first_item:
                                actual_content = first_item.get('json', {})
                                logger.info(f"👤 Unwrapped to: {str(actual_content)[:300]}")
                        
                        # Check for error response
                        if isinstance(actual_content, dict) and 'error' in actual_content:
                            if actual_content.get('error') == {} or not actual_content.get('error'):
                                logger.warning(f"⚠️ IdentifyCustomer returned empty error - tool call failed silently")
                            else:
                                logger.error(f"❌ IdentifyCustomer error: {actual_content.get('error')}")
                            continue  # Skip to next tool result
                        
                        # Our TOOL_IDENTIFY_CUSTOMER returns: {"success": true, "matches": [...]}
                        if isinstance(actual_content, dict) and "matches" in actual_content:
                            matches_to_check = actual_content.get("matches", [])
                            logger.info(f"👤 Found matches array with {len(matches_to_check)} items")
                        elif isinstance(actual_content, list):
                            matches_to_check = actual_content
                        elif isinstance(actual_content, dict):
                            # Fallback to other dict formats
                            rows = actual_content.get("rows") or actual_content.get("data") or actual_content.get("results") or []
                            if isinstance(rows, list):
                                matches_to_check = rows
                            else:
                                matches_to_check = [actual_content]
                        elif isinstance(actual_content, str):
                            try:
                                parsed = json.loads(actual_content)
                                if isinstance(parsed, dict) and "matches" in parsed:
                                    matches_to_check = parsed.get("matches", [])
                                elif isinstance(parsed, list):
                                    matches_to_check = parsed
                            except json.JSONDecodeError:
                                pass
                        
                        logger.info(f"👤 Processing {len(matches_to_check)} potential matches")
                        
                        # Get the best match (first result with confidence > 0.45)
                        for match_item in matches_to_check:
                            logger.info(f"👤 Checking match: {match_item}")
                            match = extract_customer_match(match_item)
                            if match:
                                conf = match.get("confidence", 0)
                                logger.info(f"👤 Match extracted: {match.get('first_name')} with confidence {conf}")
                                if conf > 0.45:
                                    customer_match = match
                                    logger.info(f"✅ Customer identified: {match.get('first_name')} with confidence {conf:.2f}")
                                    break
                                else:
                                    logger.info(f"⚠️ Match confidence {conf} below threshold 0.45")
                    
                    # Handle Cart tool results
                    if "cart" in tool_name or "acp" in tool_name:
                        if isinstance(content, dict):
                            cart_update = content
                        elif isinstance(content, str):
                            try:
                                cart_update = json.loads(content)
                            except json.JSONDecodeError:
                                pass
                
                # Source 2: Tables (from Cortex Analyst)
                for table in tables:
                    logger.info(f"📊 Checking table: {type(table)}")
                    if isinstance(table, dict):
                        rows = table.get("rows") or table.get("data") or []
                        columns = table.get("columns") or []
                        
                        # Check if this looks like product data
                        col_names = [c.get("name", "").lower() if isinstance(c, dict) else str(c).lower() for c in columns]
                        if any(kw in " ".join(col_names) for kw in ["product", "name", "brand", "price"]):
                            logger.info(f"📦 Found product table with columns: {col_names}")
                            for row in rows:
                                # Row might be dict or list
                                if isinstance(row, dict):
                                    prod = extract_product(row)
                                    if prod:
                                        extracted_products.append(prod)
                                elif isinstance(row, list) and len(row) == len(columns):
                                    # Convert list to dict
                                    row_dict = {}
                                    for i, col in enumerate(columns):
                                        col_name = col.get("name") if isinstance(col, dict) else str(col)
                                        row_dict[col_name] = row[i]
                                    prod = extract_product(row_dict)
                                    if prod:
                                        extracted_products.append(prod)
                    elif isinstance(table, list):
                        for item in table:
                            prod = extract_product(item)
                            if prod:
                                extracted_products.append(prod)
                
                # Source 3: Parse products from text response (fallback)
                # UX_FIX (2026-01-04): Only extract products from text if product tools were actually used
                # This prevents false-positive product cards for non-product queries (e.g., "Clean Beauty")
                product_tools_used = any(
                    t.get("name") in ["MatchProducts", "cortex_search", "ProductSearch"] 
                    for t in tools_used
                )
                if not extracted_products and accumulated_text and product_tools_used:
                    import re
                    
                    # Try multiple patterns in order of specificity
                    found_products = []
                    
                    # Pattern 1: **Product Name** - $XX.XX (with price)
                    price_pattern = r'\*\*([^*]+(?:Foundation|Lipstick|Concealer|Blush|Bronzer|Primer)[^*]*)\*\*\s*-\s*\$?([\d.]+)'
                    matches = re.findall(price_pattern, accumulated_text, re.IGNORECASE)
                    for match in matches:
                        name = match[0].strip()
                        try:
                            price = float(match[1])
                        except:
                            price = 0
                        if name and len(name) > 5:
                            found_products.append({"name": name, "price": price})
                    
                    # Pattern 2: **Product Name** - Description (no price, product keywords)
                    if not found_products:
                        no_price_pattern = r'\*\*([^*]*(?:Foundation|Lipstick|Concealer|Blush|Bronzer|Primer|Beauty)[^*]*)\*\*\s*-\s*([^$\n]+)'
                        matches = re.findall(no_price_pattern, accumulated_text, re.IGNORECASE)
                        for match in matches:
                            name = match[0].strip()
                            if name and len(name) > 5 and len(name) < 100:
                                found_products.append({"name": name, "price": 0})
                    
                    # Pattern 3: Bullet points with product names
                    if not found_products:
                        bullet_pattern = r'[-•]\s*\*\*([^*]+)\*\*'
                        matches = re.findall(bullet_pattern, accumulated_text)
                        for match in matches:
                            name = match.strip()
                            # Filter out non-product items
                            if name and len(name) > 5 and len(name) < 80:
                                if any(kw in name.lower() for kw in ['foundation', 'lipstick', 'beauty', 'concealer', 'blush', 'glow', 'matte', 'pro', 'ultra']):
                                    found_products.append({"name": name, "price": 0})
                    
                    # Convert found products to structured format
                    for prod in found_products[:8]:  # Limit to 8
                        name = prod["name"]
                        # Extract brand (usually first word or two)
                        words = name.split()
                        brand = words[0] if words else ""
                        if len(words) > 1 and words[0].lower() in ['the', 'nars', 'mac', 'nyx']:
                            brand = words[0]
                        elif len(words) > 1:
                            brand = f"{words[0]} {words[1]}" if len(words) > 1 else words[0]
                        
                        extracted_products.append({
                            "product_id": "",
                            "name": name,
                            "brand": brand,
                            "category": "foundation" if "foundation" in name.lower() else "beauty",
                            "swatch_hex": "#f0f0f0",
                            "color_distance": 5,
                            "price": prod["price"],
                            "image_url": "",
                        })
                    
                    if extracted_products:
                        logger.info(f"📦 Extracted {len(extracted_products)} products from text")
                
                # =================================================================
                # OPTION 1 FIX: Filter products to match agent's recommendations
                # =================================================================
                # Build lookup from all products extracted from tools
                for prod in extracted_products:
                    pid = prod.get("product_id", "").lower()
                    if pid and len(pid) == 36:  # Valid UUID
                        product_lookup[pid] = prod
                
                logger.info(f"📦 Built product lookup with {len(product_lookup)} UUIDs from {len(extracted_products)} total products")
                
                # Parse products mentioned in agent's TEXT response
                text_products = parse_products_from_agent_text(accumulated_text)
                
                # If agent mentioned specific products with UUIDs, filter to only those
                if text_products:
                    final_products = []
                    for tp in text_products:
                        uuid = tp["product_id"].lower()
                        if uuid in product_lookup:
                            # Use full data from tool results
                            final_products.append(product_lookup[uuid])
                            logger.info(f"✅ Matched product from text: {tp['name']} (ID: {uuid})")
                        else:
                            # UUID not in lookup - create minimal product from text
                            logger.info(f"⚠️ Product UUID not in lookup, using text data: {tp['name']}")
                            words = tp["name"].split()
                            brand = words[0] if words else ""
                            final_products.append({
                                "product_id": uuid,
                                "name": tp["name"],
                                "brand": brand,
                                "category": "",
                                "swatch_hex": "#f0f0f0",
                                "color_distance": 5,
                                "price": tp.get("price", 0),
                                "image_url": ""
                            })
                    
                    if final_products:
                        extracted_products = final_products
                        logger.info(f"📦 Filtered to {len(extracted_products)} products matching agent text")
                else:
                    # No UUIDs in text - fall back to first 4 from tool results
                    if extracted_products:
                        logger.info(f"📦 No UUIDs in agent text, using first 4 from {len(extracted_products)} tool results")
                        extracted_products = extracted_products[:4]
                
                if extracted_products:
                    logger.info(f"📦 Final product count: {len(extracted_products)}")
                else:
                    logger.info(f"⚠️ No products extracted from {len(tool_results)} tool results, {len(tables)} tables, or text")
                
                return {
                    "success": True,
                    "response": accumulated_text,
                    "thinking": accumulated_thinking if accumulated_thinking else None,
                    "tools_used": [t["name"] for t in tools_used if t.get("name")],
                    "tool_details": tools_used,
                    "tool_results": tool_results,
                    "tables": tables,
                    "thread_id": thread_id,
                    "message_id": message_id,
                    "products": extracted_products if extracted_products else None,
                    "customer_match": customer_match,
                    "cart_update": cart_update
                }
    
    except httpx.TimeoutException:
        logger.error("Agent API request timed out")
        return {"success": False, "error": "Request timed out"}
    except Exception as e:
        logger.error(f"Error calling Agent API: {e}")
        return {"success": False, "error": str(e)}


async def invoke_cortex_agent(message: str, session_id: str) -> Dict[str, Any]:
    """
    Async wrapper for the Cortex Agent call.
    Message should already be enriched with any image analysis data.
    """
    # Get conversation history for this session
    history = _chat_sessions.get(session_id, [])[:-1]  # Exclude current message (just added)
    
    return await invoke_cortex_agent_rest(message, session_id, history)


# Initialize FastAPI app
app = FastAPI(
    title="Agent Commerce Backend",
    description="Face recognition and skin analysis service",
    version="1.0.0"
)

# CORS middleware
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# ============================================================================
# LAZY LOADING OF ML MODELS
# ============================================================================
# Models are loaded on first use to reduce cold start time

_face_recognition = None
_mediapipe_face_mesh = None

def get_face_recognition():
    """Lazy load face_recognition library."""
    global _face_recognition
    if _face_recognition is None:
        try:
            import face_recognition
            _face_recognition = face_recognition
            logger.info("✅ face_recognition loaded successfully")
        except ImportError as e:
            logger.error(f"❌ Failed to load face_recognition: {e}")
            raise HTTPException(status_code=500, detail="Face recognition not available")
    return _face_recognition

def get_mediapipe():
    """Lazy load MediaPipe."""
    global _mediapipe_face_mesh
    if _mediapipe_face_mesh is None:
        try:
            import mediapipe as mp
            _mediapipe_face_mesh = mp.solutions.face_mesh.FaceMesh(
                static_image_mode=True,
                max_num_faces=1,
                min_detection_confidence=0.5
            )
            logger.info("✅ MediaPipe Face Mesh loaded successfully")
        except ImportError as e:
            logger.error(f"❌ Failed to load MediaPipe: {e}")
            raise HTTPException(status_code=500, detail="MediaPipe not available")
    return _mediapipe_face_mesh

# ============================================================================
# REQUEST/RESPONSE MODELS
# ============================================================================

class HealthResponse(BaseModel):
    status: str
    timestamp: str
    version: str

class EmbeddingRequest(BaseModel):
    image_base64: str
    customer_id: Optional[str] = None

class EmbeddingResponse(BaseModel):
    success: bool
    embedding: Optional[List[float]] = None
    quality_score: Optional[float] = None
    face_detected: bool
    error: Optional[str] = None

class BatchEmbeddingRequest(BaseModel):
    images: List[dict]  # [{"image_path": str, "customer_id": str}, ...]

class BatchEmbeddingResponse(BaseModel):
    success: bool
    results: List[dict]
    processed: int
    failed: int

class SkinAnalysisRequest(BaseModel):
    image_base64: str

class SkinAnalysisResponse(BaseModel):
    success: bool
    skin_hex: Optional[str] = None
    skin_rgb: Optional[List[int]] = None
    skin_lab: Optional[List[float]] = None
    lip_hex: Optional[str] = None
    lip_rgb: Optional[List[int]] = None
    fitzpatrick_type: Optional[int] = None
    monk_shade: Optional[int] = None
    undertone: Optional[str] = None
    ita_angle: Optional[float] = None
    confidence_score: Optional[float] = None
    error: Optional[str] = None

class ColorMatchRequest(BaseModel):
    target_hex: str
    color_type: str  # "lipstick", "foundation", "eyeshadow"
    limit: int = 10

class ColorMatchResponse(BaseModel):
    success: bool
    matches: List[dict]
    error: Optional[str] = None

# ============================================================================
# UTILITY FUNCTIONS
# ============================================================================

def decode_base64_image(base64_str: str) -> np.ndarray:
    """Decode base64 string to numpy array (RGB)."""
    try:
        # Handle data URL format
        if "," in base64_str:
            base64_str = base64_str.split(",")[1]
        
        image_bytes = base64.b64decode(base64_str)
        
        from PIL import Image
        image = Image.open(io.BytesIO(image_bytes))
        
        # Convert to RGB if necessary
        if image.mode != 'RGB':
            image = image.convert('RGB')
        
        return np.array(image)
    except Exception as e:
        logger.error(f"Failed to decode image: {e}")
        raise HTTPException(status_code=400, detail=f"Invalid image: {str(e)}")

def rgb_to_hex(rgb: tuple) -> str:
    """Convert RGB tuple to hex string."""
    return f"#{rgb[0]:02x}{rgb[1]:02x}{rgb[2]:02x}"

def rgb_to_lab(rgb: tuple) -> List[float]:
    """Convert RGB to CIELAB color space."""
    # Normalize RGB
    r, g, b = [x / 255.0 for x in rgb]
    
    # Convert to XYZ
    def gamma_correct(c):
        return ((c + 0.055) / 1.055) ** 2.4 if c > 0.04045 else c / 12.92
    
    r, g, b = gamma_correct(r), gamma_correct(g), gamma_correct(b)
    
    x = r * 0.4124564 + g * 0.3575761 + b * 0.1804375
    y = r * 0.2126729 + g * 0.7151522 + b * 0.0721750
    z = r * 0.0193339 + g * 0.1191920 + b * 0.9503041
    
    # Reference white (D65)
    x, y, z = x / 0.95047, y / 1.0, z / 1.08883
    
    def f(t):
        return t ** (1/3) if t > 0.008856 else 7.787 * t + 16/116
    
    L = 116 * f(y) - 16
    a = 500 * (f(x) - f(y))
    b_val = 200 * (f(y) - f(z))
    
    return [round(L, 2), round(a, 2), round(b_val, 2)]

def calculate_ita_angle(lab: List[float]) -> float:
    """Calculate Individual Typology Angle (ITA) for skin classification."""
    L, a, b = lab
    import math
    ita = math.atan2(L - 50, b) * 180 / math.pi
    return round(ita, 2)

def ita_to_fitzpatrick(ita: float) -> int:
    """Convert ITA angle to Fitzpatrick skin type."""
    if ita > 55:
        return 1  # Very fair
    elif ita > 41:
        return 2  # Fair
    elif ita > 28:
        return 3  # Medium
    elif ita > 10:
        return 4  # Olive
    elif ita > -30:
        return 5  # Brown
    else:
        return 6  # Dark brown/black

def ita_to_monk_shade(ita: float) -> int:
    """Convert ITA angle to Monk Skin Tone scale (1-10)."""
    if ita > 55:
        return 1
    elif ita > 48:
        return 2
    elif ita > 41:
        return 3
    elif ita > 34:
        return 4
    elif ita > 28:
        return 5
    elif ita > 19:
        return 6
    elif ita > 10:
        return 7
    elif ita > -10:
        return 8
    elif ita > -30:
        return 9
    else:
        return 10

def determine_undertone(lab: List[float]) -> str:
    """Determine skin undertone from LAB values."""
    L, a, b = lab
    
    # a* positive = red/warm, negative = green/cool
    # b* positive = yellow/warm, negative = blue/cool
    
    warm_score = a + b
    
    if warm_score > 15:
        return "warm"
    elif warm_score < 5:
        return "cool"
    else:
        return "neutral"

# ============================================================================
# FACE DETECTION AND EMBEDDING
# ============================================================================

def extract_face_embedding(image: np.ndarray) -> dict:
    """Extract 128-dimensional face embedding using dlib."""
    face_recognition = get_face_recognition()
    
    # Detect face locations
    face_locations = face_recognition.face_locations(image)
    
    if not face_locations:
        return {
            "success": False,
            "face_detected": False,
            "error": "No face detected"
        }
    
    # Get face encoding (128-dim embedding)
    face_encodings = face_recognition.face_encodings(image, face_locations)
    
    if not face_encodings:
        return {
            "success": False,
            "face_detected": True,
            "error": "Could not extract embedding"
        }
    
    embedding = face_encodings[0].tolist()
    
    # Calculate quality score based on face size
    top, right, bottom, left = face_locations[0]
    face_width = right - left
    face_height = bottom - top
    face_area = face_width * face_height
    image_area = image.shape[0] * image.shape[1]
    face_ratio = face_area / image_area
    
    # Quality score: larger face = better quality
    quality_score = min(1.0, face_ratio * 10)
    
    return {
        "success": True,
        "face_detected": True,
        "embedding": embedding,
        "quality_score": round(quality_score, 3),
        "face_location": {
            "top": top,
            "right": right,
            "bottom": bottom,
            "left": left
        }
    }

# ============================================================================
# SKIN ANALYSIS
# ============================================================================

def analyze_skin(image: np.ndarray) -> dict:
    """Analyze skin tone using MediaPipe face mesh."""
    try:
        import cv2
        face_mesh = get_mediapipe()
        
        # Convert to RGB for MediaPipe
        rgb_image = cv2.cvtColor(image, cv2.COLOR_BGR2RGB) if len(image.shape) == 3 else image
        
        # Process image
        results = face_mesh.process(rgb_image)
        
        if not results.multi_face_landmarks:
            return {
                "success": False,
                "error": "No face detected"
            }
        
        landmarks = results.multi_face_landmarks[0]
        h, w = image.shape[:2]
        
        # Cheek landmarks for skin tone (left and right cheeks)
        # MediaPipe landmark indices for cheeks
        cheek_indices = [50, 101, 118, 119, 47, 100]  # Left cheek
        cheek_indices += [280, 330, 347, 348, 277, 329]  # Right cheek
        
        # Lip landmarks
        lip_indices = [13, 14, 78, 308]  # Upper and lower lip center
        
        # Sample skin colors from cheek regions
        skin_colors = []
        for idx in cheek_indices:
            landmark = landmarks.landmark[idx]
            x, y = int(landmark.x * w), int(landmark.y * h)
            if 0 <= x < w and 0 <= y < h:
                color = image[y, x]
                if len(color) == 3:
                    skin_colors.append(color)
        
        if not skin_colors:
            return {
                "success": False,
                "error": "Could not sample skin colors"
            }
        
        # Average skin color
        avg_skin = np.mean(skin_colors, axis=0).astype(int)
        skin_rgb = tuple(avg_skin.tolist())
        skin_hex = rgb_to_hex(skin_rgb)
        skin_lab = rgb_to_lab(skin_rgb)
        
        # Sample lip colors
        lip_colors = []
        for idx in lip_indices:
            landmark = landmarks.landmark[idx]
            x, y = int(landmark.x * w), int(landmark.y * h)
            if 0 <= x < w and 0 <= y < h:
                color = image[y, x]
                if len(color) == 3:
                    lip_colors.append(color)
        
        lip_rgb = None
        lip_hex = None
        if lip_colors:
            avg_lip = np.mean(lip_colors, axis=0).astype(int)
            lip_rgb = tuple(avg_lip.tolist())
            lip_hex = rgb_to_hex(lip_rgb)
        
        # Calculate skin metrics
        ita_angle = calculate_ita_angle(skin_lab)
        fitzpatrick = ita_to_fitzpatrick(ita_angle)
        monk_shade = ita_to_monk_shade(ita_angle)
        undertone = determine_undertone(skin_lab)
        
        return {
            "success": True,
            "skin_hex": skin_hex,
            "skin_rgb": list(skin_rgb),
            "skin_lab": skin_lab,
            "lip_hex": lip_hex,
            "lip_rgb": list(lip_rgb) if lip_rgb else None,
            "fitzpatrick_type": fitzpatrick,
            "monk_shade": monk_shade,
            "undertone": undertone,
            "ita_angle": ita_angle,
            "confidence_score": 0.9
        }
        
    except Exception as e:
        logger.error(f"Skin analysis failed: {e}")
        return {
            "success": False,
            "error": str(e)
        }

# ============================================================================
# API ENDPOINTS
# ============================================================================

@app.get("/health", response_model=HealthResponse)
@app.post("/health", response_model=HealthResponse)
async def health_check():
    """Health check endpoint."""
    return HealthResponse(
        status="healthy",
        timestamp=datetime.utcnow().isoformat(),
        version="1.0.0"
    )

@app.post("/extract-embedding", response_model=EmbeddingResponse)
async def extract_embedding(request: EmbeddingRequest):
    """Extract face embedding from base64 image."""
    try:
        image = decode_base64_image(request.image_base64)
        result = extract_face_embedding(image)
        
        return EmbeddingResponse(
            success=result.get("success", False),
            embedding=result.get("embedding"),
            quality_score=result.get("quality_score"),
            face_detected=result.get("face_detected", False),
            error=result.get("error")
        )
    except Exception as e:
        logger.error(f"Embedding extraction failed: {e}")
        return EmbeddingResponse(
            success=False,
            face_detected=False,
            error=str(e)
        )

@app.post("/extract-embedding-file")
async def extract_embedding_from_file(file: UploadFile = File(...)):
    """Extract face embedding from uploaded file."""
    try:
        contents = await file.read()
        
        from PIL import Image
        image = Image.open(io.BytesIO(contents))
        if image.mode != 'RGB':
            image = image.convert('RGB')
        
        image_array = np.array(image)
        result = extract_face_embedding(image_array)
        
        return EmbeddingResponse(
            success=result.get("success", False),
            embedding=result.get("embedding"),
            quality_score=result.get("quality_score"),
            face_detected=result.get("face_detected", False),
            error=result.get("error")
        )
    except Exception as e:
        logger.error(f"Embedding extraction failed: {e}")
        return EmbeddingResponse(
            success=False,
            face_detected=False,
            error=str(e)
        )

@app.post("/batch-extract", response_model=BatchEmbeddingResponse)
async def batch_extract_embeddings(request: BatchEmbeddingRequest):
    """Batch process multiple images for embedding extraction."""
    results = []
    processed = 0
    failed = 0
    
    for item in request.images:
        try:
            image_base64 = item.get("image_base64")
            customer_id = item.get("customer_id")
            
            if not image_base64:
                failed += 1
                results.append({
                    "customer_id": customer_id,
                    "success": False,
                    "error": "No image provided"
                })
                continue
            
            image = decode_base64_image(image_base64)
            result = extract_face_embedding(image)
            
            if result.get("success"):
                processed += 1
                results.append({
                    "customer_id": customer_id,
                    "success": True,
                    "embedding": result.get("embedding"),
                    "quality_score": result.get("quality_score")
                })
            else:
                failed += 1
                results.append({
                    "customer_id": customer_id,
                    "success": False,
                    "error": result.get("error")
                })
                
        except Exception as e:
            failed += 1
            results.append({
                "customer_id": item.get("customer_id"),
                "success": False,
                "error": str(e)
            })
    
    return BatchEmbeddingResponse(
        success=failed == 0,
        results=results,
        processed=processed,
        failed=failed
    )

@app.post("/analyze-skin", response_model=SkinAnalysisResponse)
async def analyze_skin_endpoint(request: SkinAnalysisRequest):
    """Analyze skin tone from base64 image."""
    try:
        image = decode_base64_image(request.image_base64)
        result = analyze_skin(image)
        
        return SkinAnalysisResponse(
            success=result.get("success", False),
            skin_hex=result.get("skin_hex"),
            skin_rgb=result.get("skin_rgb"),
            skin_lab=result.get("skin_lab"),
            lip_hex=result.get("lip_hex"),
            lip_rgb=result.get("lip_rgb"),
            fitzpatrick_type=result.get("fitzpatrick_type"),
            monk_shade=result.get("monk_shade"),
            undertone=result.get("undertone"),
            ita_angle=result.get("ita_angle"),
            confidence_score=result.get("confidence_score"),
            error=result.get("error")
        )
    except Exception as e:
        logger.error(f"Skin analysis failed: {e}")
        return SkinAnalysisResponse(
            success=False,
            error=str(e)
        )

@app.post("/analyze-skin-file")
async def analyze_skin_from_file(file: UploadFile = File(...)):
    """Analyze skin tone from uploaded file."""
    try:
        contents = await file.read()
        
        from PIL import Image
        image = Image.open(io.BytesIO(contents))
        if image.mode != 'RGB':
            image = image.convert('RGB')
        
        image_array = np.array(image)
        result = analyze_skin(image_array)
        
        return SkinAnalysisResponse(
            success=result.get("success", False),
            skin_hex=result.get("skin_hex"),
            skin_rgb=result.get("skin_rgb"),
            skin_lab=result.get("skin_lab"),
            lip_hex=result.get("lip_hex"),
            lip_rgb=result.get("lip_rgb"),
            fitzpatrick_type=result.get("fitzpatrick_type"),
            monk_shade=result.get("monk_shade"),
            undertone=result.get("undertone"),
            ita_angle=result.get("ita_angle"),
            confidence_score=result.get("confidence_score"),
            error=result.get("error")
        )
    except Exception as e:
        logger.error(f"Skin analysis failed: {e}")
        return SkinAnalysisResponse(
            success=False,
            error=str(e)
        )

# ============================================================================
# CHAT ENDPOINT - Cortex Agent Integration
# ============================================================================

class ChatRequest(BaseModel):
    message: str
    image_base64: Optional[str] = None
    session_id: Optional[str] = None
    customer_id: Optional[str] = None

class ChatResponse(BaseModel):
    response: str
    session_id: str
    tools_used: Optional[List[str]] = None
    tool_results: Optional[List[Dict[str, Any]]] = None
    tables: Optional[List[Dict[str, Any]]] = None
    analysis_result: Optional[Dict[str, Any]] = None
    products: Optional[List[Dict[str, Any]]] = None
    cart_update: Optional[Dict[str, Any]] = None
    error: Optional[str] = None
    # Timing info
    timing: Optional[Dict[str, float]] = None  # {backend_ms, agent_ms, total_ms}
    # Thinking/reasoning from agent
    thinking: Optional[str] = None
    # Message ID for feedback
    message_id: Optional[str] = None

class FeedbackRequest(BaseModel):
    message_id: str
    session_id: str
    rating: str  # "like" or "dislike"
    feedback_text: Optional[str] = None

class FeedbackResponse(BaseModel):
    success: bool
    message: str

# In-memory session storage (for demo - use Redis in production)
_chat_sessions: Dict[str, List[Dict]] = {}
_widget_config: Dict[str, Any] = None
_feedback_store: Dict[str, Dict] = {}  # message_id -> feedback

@app.post("/api/chat", response_model=ChatResponse)
async def chat_endpoint(request: ChatRequest):
    """
    Main chat endpoint that interacts with the Cortex Agent.
    
    REQUIRES Snowflake Cortex Agent connection - no local fallback.
    """
    import uuid
    import time
    
    # Start timing
    start_time = time.time()
    preprocessing_start = start_time
    
    session_id = request.session_id or str(uuid.uuid4())
    
    # Initialize session if new
    if session_id not in _chat_sessions:
        _chat_sessions[session_id] = []
    
    # Process image and build enriched message if image is present
    enriched_message = request.message
    analysis_data = None
    
    if request.image_base64:
        try:
            if USE_AGENT_FACE_ANALYSIS:
                # ================================================================
                # V2: Agent-Orchestrated Face Analysis
                # ================================================================
                # Pass base64 image to agent, let agent call TOOL_ANALYZE_FACE
                # Agent will receive analysis results and proceed with workflow
                # ================================================================
                logger.info("🔄 V2 Mode: Passing image to agent for analysis")
                
                # Provide minimal analysis_data for frontend display (will be updated by agent)
                analysis_data = {
                    "success": True,
                    "mode": "agent_analyzed",
                    "message": "Image sent to agent for analysis"
                }
                
                enriched_message = f"""The user uploaded a face image for analysis.

**Image Data (base64):**
{request.image_base64}

**User's Request:** {request.message}

IMPORTANT WORKFLOW:
1. First, call AnalyzeFace tool with the base64 image above to get:
   - Face embedding (128-dim vector)
   - Skin tone (hex color)
   - Fitzpatrick type, Monk shade, undertone
   - Lip color

2. After getting the analysis results:
   - Use IdentifyCustomer with the embedding to check for returning customers
   - Use MatchProducts with skin_hex to find matching products

3. Follow the customer verification flow if a match is found."""

                logger.info("📤 V2: Image passed to agent for AnalyzeFace tool call")
                
            else:
                # ================================================================
                # V1: Backend-Analyzed Face Analysis (Default)
                # ================================================================
                # Do local face analysis using dlib/mediapipe
                # Embed results directly in message for agent
                # ================================================================
                logger.info("🔄 V1 Mode: Local face analysis")
                
                image = decode_base64_image(request.image_base64)
                skin_result = analyze_skin(image)
                embedding_result = extract_face_embedding(image)
                
                if skin_result.get("success"):
                    # Get the embedding (128-dim vector)
                    embedding = embedding_result.get("embedding", [])
                    face_detected = embedding_result.get("face_detected", False) and len(embedding) == 128
                    
                    analysis_data = {
                        "success": True,
                        "skin_hex": skin_result.get("skin_hex"),
                        "lip_hex": skin_result.get("lip_hex"),
                        "fitzpatrick": skin_result.get("fitzpatrick_type"),  # Frontend expects 'fitzpatrick'
                        "monk_shade": skin_result.get("monk_shade"),
                        "undertone": skin_result.get("undertone"),
                        "face_detected": face_detected,
                        "quality_score": embedding_result.get("quality_score"),
                        "embedding": embedding if face_detected else None,  # Include full 128-dim embedding
                    }
                    
                    # Build enriched message with FULL analysis results including embedding
                    # The agent needs the embedding to call TOOL_IDENTIFY_CUSTOMER
                    embedding_json = json.dumps(embedding) if face_detected else "null"
                    
                    # LOG THE FULL EMBEDDING for debugging/demo setup
                    if face_detected and embedding:
                        logger.info(f"🧬 REAL EMBEDDING (copy for SQL): {embedding_json}")
                    
                    enriched_message = f"""The user uploaded a face image. Here are the analysis results:

**Skin Analysis Results:**
- Skin Tone: {skin_result.get('skin_hex')} (Monk Shade {skin_result.get('monk_shade')})
- Undertone: {skin_result.get('undertone', 'neutral')}
- Fitzpatrick Type: {skin_result.get('fitzpatrick_type')}
- Lip Color: {skin_result.get('lip_hex', 'N/A')}
- Face Detected: {face_detected}

**Face Embedding (128-dimensional vector for customer identification):**
{embedding_json}

User's request: {request.message}

IMPORTANT: You now have the user's face embedding. Use TOOL_IDENTIFY_CUSTOMER with this embedding to check if they are a returning customer. If a match is found with confidence > 0.45, ask them to confirm their identity (e.g., "Is this you, [Name]?"). Then proceed to recommend products based on their skin tone."""
                    
                    logger.info(f"🎨 V1: Image analyzed locally: skin={skin_result.get('skin_hex')}, monk={skin_result.get('monk_shade')}")
                    
        except Exception as e:
            logger.error(f"Image analysis error: {e}")
            enriched_message = f"[Image uploaded but analysis failed: {str(e)}]\n\n{request.message}"
    
    # Store the ENRICHED user message (so follow-up questions have context)
    _chat_sessions[session_id].append({
        "role": "user",
        "content": enriched_message
    })
    
    # =========================================================================
    # INVOKE CORTEX AGENT (REQUIRED)
    # =========================================================================
    preprocessing_time = (time.time() - preprocessing_start) * 1000  # ms
    agent_start = time.time()
    
    agent_response = await invoke_cortex_agent(
        message=enriched_message,  # Use enriched message with analysis
        session_id=session_id
    )
    
    agent_time = (time.time() - agent_start) * 1000  # ms
    total_time = (time.time() - start_time) * 1000  # ms
    
    timing_info = {
        "preprocessing_ms": round(preprocessing_time, 1),
        "agent_ms": round(agent_time, 1),
        "total_ms": round(total_time, 1)
    }
    logger.info(f"⏱️ Timing: preprocessing={preprocessing_time:.0f}ms, agent={agent_time:.0f}ms, total={total_time:.0f}ms")
    
    if agent_response and agent_response.get("success"):
        logger.info("✅ Cortex Agent response received")
        response_text = agent_response.get("response", "I'm here to help!")
        tools_used = agent_response.get("tools_used", [])
        
        # Generate unique message ID for feedback
        message_id = f"{session_id}_{int(time.time() * 1000)}"
        
        # Merge customer_match into analysis_data if found
        customer_match = agent_response.get("customer_match")
        if customer_match and analysis_data:
            analysis_data["customer_match"] = customer_match
            logger.info(f"👤 Customer match added to analysis: {customer_match.get('first_name')}")
        elif customer_match and not analysis_data:
            # If no analysis but customer match found, create minimal analysis_data
            analysis_data = {
                "success": True,
                "face_detected": True,
                "customer_match": customer_match
            }
        
        # Store assistant response WITH any analysis data
        assistant_content = response_text
        if analysis_data:
            # Append analysis summary to assistant response for future context
            customer_name = analysis_data.get("customer_match", {}).get("first_name", "")
            context_parts = []
            if analysis_data.get('skin_hex'):
                context_parts.append(f"skin tone is {analysis_data.get('skin_hex')}")
            if analysis_data.get('monk_shade'):
                context_parts.append(f"Monk Shade {analysis_data.get('monk_shade')}")
            if analysis_data.get('undertone'):
                context_parts.append(f"{analysis_data.get('undertone')} undertone")
            if customer_name:
                context_parts.append(f"identified as {customer_name}")
            
            if context_parts:
                assistant_content += f"\n\n[Context: User's {', '.join(context_parts)}]"
        
        _chat_sessions[session_id].append({
            "role": "assistant",
            "content": assistant_content,
            "message_id": message_id
        })
        
        return ChatResponse(
            response=response_text,
            session_id=session_id,
            tools_used=tools_used,
            tool_results=agent_response.get("tool_results"),
            tables=agent_response.get("tables"),
            analysis_result=analysis_data or agent_response.get("analysis_result"),  # Use local analysis if available
            products=agent_response.get("products"),
            cart_update=agent_response.get("cart_update"),
            timing=timing_info,
            thinking=agent_response.get("thinking"),
            message_id=message_id
        )
    
    # =========================================================================
    # CORTEX AGENT NOT CONNECTED - Return setup instructions
    # =========================================================================
    logger.warning("⚠️ Cortex Agent not connected")
    
    error_response = """⚠️ **Cortex Agent Not Connected**

The chat assistant requires a connection to Snowflake Cortex Agent.

**To connect:**
1. Ensure the Cortex Agent `AGENTIC_COMMERCE_ASSISTANT` is created in Snowflake
2. Verify the SPCS service has access to the agent
3. Check that the agent tools (UDFs/Procedures) are deployed

**Run in Snowsight:**
```sql
-- Verify agent exists
SHOW AGENTS IN SCHEMA AGENT_COMMERCE.UTIL;

-- Test the agent
SELECT SNOWFLAKE.CORTEX.INVOKE_AGENT(
    'AGENT_COMMERCE.UTIL.AGENTIC_COMMERCE_ASSISTANT',
    PARSE_JSON('[{"role": "user", "content": "Hello"}]'),
    OBJECT_CONSTRUCT()
);
```

Please contact your administrator to complete the Cortex Agent setup."""
    
    # Include specific error if available
    error_detail = agent_response.get("error") if agent_response else "No connection to Cortex Agent"
    
    return ChatResponse(
        response=error_response,
        session_id=session_id,
        tools_used=None,
        tool_results=None,
        tables=None,
        analysis_result=None,
        products=None,
        cart_update=None,
        error=error_detail,
        timing=timing_info
    )

# ============================================================================
# FEEDBACK ENDPOINT - Collect user feedback on agent responses
# ============================================================================

@app.post("/api/feedback", response_model=FeedbackResponse)
async def submit_feedback(request: FeedbackRequest):
    """
    Submit feedback for an agent response.
    
    Stores feedback locally and can optionally call Cortex Agent Feedback API.
    """
    try:
        # Store feedback locally
        _feedback_store[request.message_id] = {
            "session_id": request.session_id,
            "rating": request.rating,
            "feedback_text": request.feedback_text,
            "timestamp": datetime.now().isoformat()
        }
        
        logger.info(f"📝 Feedback received: {request.rating} for message {request.message_id}")
        if request.feedback_text:
            logger.info(f"📝 Feedback text: {request.feedback_text}")
        
        # TODO: Optionally call Cortex Agent Feedback API
        # POST /api/v2/databases/{db}/schemas/{schema}/agents/{name}/feedback
        
        return FeedbackResponse(
            success=True,
            message="Thank you for your feedback!"
        )
    except Exception as e:
        logger.error(f"Error storing feedback: {e}")
        return FeedbackResponse(
            success=False,
            message=f"Failed to store feedback: {str(e)}"
        )

# ============================================================================
# STAGE UPLOAD ENDPOINT - Upload images to Snowflake Stage
# ============================================================================

class StageUploadResponse(BaseModel):
    success: bool
    stage_path: Optional[str] = None
    error: Optional[str] = None

@app.post("/api/upload-image", response_model=StageUploadResponse)
async def upload_image_to_stage(file: UploadFile = File(...)):
    """
    Upload an image to Snowflake Stage for face analysis.
    
    Returns the stage path that can be passed to the Cortex Agent.
    NOTE: Stage upload is disabled - returning error to trigger base64 fallback.
    """
    # Stage upload is not available in current setup - return error to trigger fallback
    return StageUploadResponse(
        success=False,
        stage_path=None,
        error="Stage upload not available - use base64 fallback"
    )
    
    # Original implementation (disabled):
    import uuid
    try:
        from snowflake.snowpark import Session
    except ImportError:
        return StageUploadResponse(
            success=False,
            stage_path=None,
            error="Snowpark not available"
        )
    
    try:
        # Read file contents
        contents = await file.read()
        
        # Generate unique filename
        file_ext = file.filename.split('.')[-1] if file.filename else 'jpg'
        unique_filename = f"{uuid.uuid4()}.{file_ext}"
        
        # Get Snowflake connection from SPCS environment
        token = get_spcs_token()
        host = get_snowflake_host()
        
        if not token or not host:
            # Fallback: Return base64 encoded for local processing
            import base64
            base64_data = base64.b64encode(contents).decode('utf-8')
            return StageUploadResponse(
                success=True,
                stage_path=f"base64:{base64_data[:100]}...",  # Truncated for response
                error="Stage upload not available - using base64 fallback"
            )
        
        # Create Snowpark session using SPCS OAuth token
        connection_params = {
            "host": host,
            "authenticator": "oauth",
            "token": token,
            "database": "AGENT_COMMERCE",
            "schema": "CUSTOMERS",
            "warehouse": "AGENT_COMMERCE_WH"
        }
        
        session = Session.builder.configs(connection_params).create()
        
        # Write to temporary file and upload
        import tempfile
        with tempfile.NamedTemporaryFile(suffix=f".{file_ext}", delete=False) as tmp:
            tmp.write(contents)
            tmp_path = tmp.name
        
        # Upload to stage
        stage_name = "@CUSTOMERS.FACE_UPLOAD_STAGE"
        session.file.put(tmp_path, stage_name, auto_compress=False, overwrite=True)
        
        # Clean up temp file
        import os
        os.unlink(tmp_path)
        
        stage_path = f"{stage_name}/{unique_filename}"
        
        session.close()
        
        logger.info(f"✅ Image uploaded to stage: {stage_path}")
        
        return StageUploadResponse(
            success=True,
            stage_path=stage_path
        )
        
    except Exception as e:
        logger.error(f"Stage upload failed: {e}")
        return StageUploadResponse(
            success=False,
            error=str(e)
        )

# ============================================================================
# CONFIG ENDPOINT - For Admin Panel
# ============================================================================

@app.get("/api/config")
async def get_config():
    """Get current widget configuration."""
    global _widget_config
    if _widget_config is None:
        _widget_config = {
            "retailer_name": "Beauty Store",
            "tagline": "Commerce Assistant",
            "logo_url": None,
            "theme": {
                "primary_color": "#000000",
                "secondary_color": "#E60023",
                "background_color": "#FFFFFF",
                "text_color": "#333333",
                "accent_color": "#C9A050",
                "border_radius": "12px",
                "font_family": "'Helvetica Neue', Arial, sans-serif"
            },
            "widget": {
                "position": "bottom-right",
                "button_text": "Chat with Us",
                "button_icon": "💄",
                "width": "380px",
                "height": "600px"
            },
            "messages": {
                "welcome": "Hi! I'm your Commerce Assistant. How can I help you today?",
                "identity_prompt": "Is this you, {name}?",
                "analysis_complete": "✨ Your Beauty Profile"
            }
        }
    return _widget_config

@app.put("/api/config")
async def update_config(config: Dict[str, Any]):
    """Update widget configuration."""
    global _widget_config
    if _widget_config is None:
        _widget_config = {}
    
    # Deep merge
    def merge(base, updates):
        for key, value in updates.items():
            if isinstance(value, dict) and key in base and isinstance(base[key], dict):
                merge(base[key], value)
            else:
                base[key] = value
    
    merge(_widget_config, config)
    return _widget_config

# ============================================================================
# STATIC FILES - Serve React Frontend
# ============================================================================

# Serve static files from /static directory
STATIC_DIR = Path(__file__).parent.parent / "static"

# FastAPI built-in routes that should NOT be caught by catch-all
RESERVED_PATHS = {"docs", "redoc", "openapi.json", "health"}

@app.on_event("startup")
async def startup_event():
    """Initialize on startup."""
    logger.info("🚀 Agent Commerce Backend starting...")
    logger.info(f"📁 Working directory: {os.getcwd()}")
    logger.info(f"📁 Static directory: {STATIC_DIR}")
    logger.info(f"📁 Static exists: {STATIC_DIR.exists()}")
    
    # List static files if directory exists
    if STATIC_DIR.exists():
        files = list(STATIC_DIR.iterdir())
        logger.info(f"📦 Static files: {[f.name for f in files]}")
        
        # Mount assets subdirectory if it exists
        assets_dir = STATIC_DIR / "assets"
        if assets_dir.exists():
            app.mount("/assets", StaticFiles(directory=assets_dir), name="assets")
            logger.info(f"📦 Assets mounted from {assets_dir}")
    else:
        logger.warning(f"⚠️ Static directory not found: {STATIC_DIR}")

# Root route - serve index.html
@app.get("/")
async def serve_root():
    """Serve the React SPA index.html for root path."""
    logger.info("📥 Serving root route /")
    index_file = STATIC_DIR / "index.html"
    
    if index_file.exists():
        logger.info(f"✅ Found index.html at {index_file}")
        return FileResponse(index_file)
    
    logger.warning(f"⚠️ index.html not found at {index_file}")
    # Fallback if no static files
    return JSONResponse({
        "message": "Agent Commerce Backend",
        "status": "running",
        "docs": "/docs",
        "health": "/health",
        "static_dir": str(STATIC_DIR),
        "static_exists": STATIC_DIR.exists(),
        "note": "Frontend not deployed. Run deploy.sh to build and push frontend."
    })

# Admin route
@app.get("/admin")
async def serve_admin():
    """Serve the admin panel."""
    index_file = STATIC_DIR / "index.html"
    if index_file.exists():
        return FileResponse(index_file)
    raise HTTPException(status_code=404, detail="Admin panel not available - frontend not deployed")

# Demo route
@app.get("/demo")
async def serve_demo():
    """Serve the demo page."""
    index_file = STATIC_DIR / "index.html"
    if index_file.exists():
        return FileResponse(index_file)
    raise HTTPException(status_code=404, detail="Demo page not available - frontend not deployed")

# Catch-all route for SPA and static files - must be last
@app.get("/{full_path:path}")
async def serve_spa(full_path: str):
    """Serve static files or SPA for all non-API/non-reserved routes."""
    logger.info(f"📥 Catch-all route for: /{full_path}")
    
    # Skip reserved FastAPI routes - let FastAPI handle them
    if full_path in RESERVED_PATHS or full_path.startswith("api/"):
        logger.info(f"⏭️ Skipping reserved path: {full_path}")
        raise HTTPException(status_code=404, detail="Not found")
    
    # Try to serve static file directly (e.g., .js, .css, images)
    static_file = STATIC_DIR / full_path
    if static_file.exists() and static_file.is_file():
        logger.info(f"✅ Serving static file: {static_file}")
        return FileResponse(static_file)
    
    # For SPA routes (admin, demo, etc.), serve index.html
    index_file = STATIC_DIR / "index.html"
    if index_file.exists():
        logger.info(f"✅ Serving index.html for SPA route: /{full_path}")
        return FileResponse(index_file)
    
    # No frontend available
    logger.warning(f"⚠️ No frontend for: /{full_path}")
    raise HTTPException(status_code=404, detail="Resource not found")

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)

