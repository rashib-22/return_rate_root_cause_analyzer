-- =============================================================
-- FILE  : 01_create_schema.sql
-- PROJECT: Return Rate Root Cause Analyzer — Quick Commerce
-- PURPOSE: Create DB + all 5 tables with indexes & FK constraints
-- HOW TO USE: Open in MySQL Workbench → Run All (Ctrl+Shift+Enter)
-- =============================================================

CREATE DATABASE IF NOT EXISTS return_analyzer
    CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

USE return_analyzer;

-- Drop in reverse FK order so reruns don't fail
DROP TABLE IF EXISTS returns;
DROP TABLE IF EXISTS orders;
DROP TABLE IF EXISTS products;
DROP TABLE IF EXISTS customers;
DROP TABLE IF EXISTS delivery_slots;

-- ─────────────────────────────────────────────────────────────
-- TABLE 1: products  (459 rows — SKU master catalogue)
-- ─────────────────────────────────────────────────────────────
CREATE TABLE products (
    sku_id           VARCHAR(10)   NOT NULL PRIMARY KEY,
    product_name     VARCHAR(120)  NOT NULL,
    brand            VARCHAR(60)   NOT NULL,
    brand_tier       VARCHAR(10)   NOT NULL,   -- Budget / Mid / Premium
    category         VARCHAR(60)   NOT NULL,
    sub_category     VARCHAR(60)   NOT NULL,
    mrp              DECIMAL(10,2) NOT NULL,
    selling_price    DECIMAL(10,2) NOT NULL,
    weight_grams     INT           NOT NULL,
    is_perishable    TINYINT(1)    NOT NULL DEFAULT 0,
    shelf_life_days  INT           NOT NULL,
    base_return_rate DECIMAL(5,3)  NOT NULL,
    is_active        TINYINT(1)    NOT NULL DEFAULT 1,
    INDEX idx_cat    (category),
    INDEX idx_tier   (brand_tier),
    INDEX idx_perish (is_perishable)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ─────────────────────────────────────────────────────────────
-- TABLE 2: customers  (18,000 rows)
-- ─────────────────────────────────────────────────────────────
CREATE TABLE customers (
    customer_id       VARCHAR(10)   NOT NULL PRIMARY KEY,
    full_name         VARCHAR(100)  NOT NULL,
    email             VARCHAR(120)  NOT NULL,
    phone             VARCHAR(15)   NOT NULL,
    city              VARCHAR(30)   NOT NULL,
    pincode           VARCHAR(10)   NOT NULL,
    join_date         DATE          NOT NULL,
    tenure_days       INT           NOT NULL,
    segment           VARCHAR(15)   NOT NULL,   -- New/Growing/Loyal/Champion
    age_group         VARCHAR(10)   NOT NULL,
    gender            VARCHAR(10)   NOT NULL,
    has_subscription  TINYINT(1)    NOT NULL DEFAULT 0,
    preferred_slot    VARCHAR(50)   NULL,
    avg_order_value   DECIMAL(10,2) NOT NULL,
    lifetime_orders   INT           NOT NULL DEFAULT 0,
    referral_source   VARCHAR(40)   NOT NULL,
    INDEX idx_city    (city),
    INDEX idx_seg     (segment),
    INDEX idx_tenure  (tenure_days)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ─────────────────────────────────────────────────────────────
-- TABLE 3: delivery_slots  (6 rows — slot reference table)
-- ─────────────────────────────────────────────────────────────
CREATE TABLE delivery_slots (
    slot_id              VARCHAR(6)   NOT NULL PRIMARY KEY,
    slot_name            VARCHAR(50)  NOT NULL,
    slot_start           VARCHAR(8)   NOT NULL,
    slot_end             VARCHAR(8)   NOT NULL,
    sla_target_minutes   INT          NOT NULL DEFAULT 20,
    sla_breach_rate      DECIMAL(4,3) NOT NULL,
    demand_weight        DECIMAL(4,2) NOT NULL,
    recommended_capacity VARCHAR(10)  NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ─────────────────────────────────────────────────────────────
-- TABLE 4: orders  (80,000 rows — core transaction table)
-- ─────────────────────────────────────────────────────────────
CREATE TABLE orders (
    order_id              VARCHAR(12)   NOT NULL PRIMARY KEY,
    customer_id           VARCHAR(10)   NOT NULL,
    sku_id                VARCHAR(10)   NOT NULL,
    category              VARCHAR(60)   NOT NULL,
    sub_category          VARCHAR(60)   NOT NULL,
    brand_tier            VARCHAR(10)   NOT NULL,
    city                  VARCHAR(30)   NOT NULL,
    pincode               VARCHAR(10)   NOT NULL,
    order_date            DATE          NOT NULL,
    order_month           VARCHAR(7)    NOT NULL,
    order_quarter         VARCHAR(12)   NOT NULL,
    order_year            SMALLINT      NOT NULL,
    order_dow             VARCHAR(10)   NOT NULL,
    is_weekend            TINYINT(1)    NOT NULL DEFAULT 0,
    delivery_slot         VARCHAR(50)   NOT NULL,
    quantity              INT           NOT NULL,
    mrp                   DECIMAL(10,2) NOT NULL,
    discount_amount       DECIMAL(10,2) NOT NULL DEFAULT 0,
    discount_pct          DECIMAL(5,1)  NOT NULL DEFAULT 0,
    total_paid            DECIMAL(10,2) NOT NULL,
    payment_method        VARCHAR(20)   NOT NULL,
    order_source          VARCHAR(20)   NOT NULL,
    sla_breach            TINYINT(1)    NOT NULL DEFAULT 0,
    delivery_minutes      INT           NOT NULL,
    customer_segment      VARCHAR(15)   NOT NULL,
    customer_tenure_days  INT           NOT NULL,
    is_perishable         TINYINT(1)    NOT NULL DEFAULT 0,
    dark_store_id         VARCHAR(8)    NOT NULL,
    delivery_agent_id     VARCHAR(8)    NOT NULL,
    is_returned           TINYINT(1)    NOT NULL DEFAULT 0,
    return_probability    DECIMAL(6,4)  NOT NULL DEFAULT 0,
    FOREIGN KEY (customer_id) REFERENCES customers(customer_id),
    FOREIGN KEY (sku_id)      REFERENCES products(sku_id),
    INDEX idx_date      (order_date),
    INDEX idx_month     (order_month),
    INDEX idx_city      (city),
    INDEX idx_cat       (category),
    INDEX idx_slot      (delivery_slot),
    INDEX idx_seg       (customer_segment),
    INDEX idx_returned  (is_returned),
    INDEX idx_sla       (sla_breach),
    INDEX idx_store     (dark_store_id),
    INDEX idx_agent     (delivery_agent_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ─────────────────────────────────────────────────────────────
-- TABLE 5: returns  (16,713 rows — one row per return event)
-- ─────────────────────────────────────────────────────────────
CREATE TABLE returns (
    return_id               VARCHAR(12)   NOT NULL PRIMARY KEY,
    order_id                VARCHAR(12)   NOT NULL,
    customer_id             VARCHAR(10)   NOT NULL,
    sku_id                  VARCHAR(10)   NOT NULL,
    category                VARCHAR(60)   NOT NULL,
    sub_category            VARCHAR(60)   NOT NULL,
    brand_tier              VARCHAR(10)   NOT NULL,
    city                    VARCHAR(30)   NOT NULL,
    return_date             DATE          NOT NULL,
    return_month            VARCHAR(7)    NOT NULL,
    days_to_return          INT           NOT NULL DEFAULT 0,
    return_reason           VARCHAR(60)   NOT NULL,
    return_reason_group     VARCHAR(20)   NOT NULL,  -- Logistics / Quality / Customer
    refund_amount           DECIMAL(10,2) NOT NULL,
    reverse_logistics_cost  DECIMAL(10,2) NOT NULL,
    total_loss              DECIMAL(10,2) NOT NULL,
    resolution_days         INT           NOT NULL DEFAULT 1,
    refund_mode             VARCHAR(30)   NOT NULL,
    customer_segment        VARCHAR(15)   NOT NULL,
    delivery_slot           VARCHAR(50)   NOT NULL,
    sla_breached            TINYINT(1)    NOT NULL DEFAULT 0,
    is_perishable           TINYINT(1)    NOT NULL DEFAULT 0,
    order_total_paid        DECIMAL(10,2) NOT NULL,
    dark_store_id           VARCHAR(8)    NOT NULL,
    delivery_agent_id       VARCHAR(8)    NOT NULL,
    FOREIGN KEY (order_id)    REFERENCES orders(order_id),
    FOREIGN KEY (customer_id) REFERENCES customers(customer_id),
    FOREIGN KEY (sku_id)      REFERENCES products(sku_id),
    INDEX idx_reason    (return_reason),
    INDEX idx_cat       (category),
    INDEX idx_city      (city),
    INDEX idx_date      (return_date),
    INDEX idx_seg       (customer_segment),
    INDEX idx_slot      (delivery_slot),
    INDEX idx_store     (dark_store_id),
    INDEX idx_agent     (delivery_agent_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

SELECT 'return_analyzer schema created successfully' AS status;
SHOW TABLES;

use return_analyzer