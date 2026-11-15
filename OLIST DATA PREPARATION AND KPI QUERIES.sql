-- =========================================================
-- DATA PREPARATION: ONE REVIEW PER ORDER (LATEST REVIEW)
-- =========================================================
 
CREATE TABLE reviews_clean AS
SELECT order_id, review_score
FROM (SELECT order_id, review_score,ROW_NUMBER() OVER (PARTITION BY order_id 
ORDER BY review_answer_timestamp DESC, review_id DESC) AS rn FROM reviews) x WHERE rn = 1;
 
SELECT COUNT(*) AS reviews_clean_rows FROM reviews_clean;           -- 98673
 
-- =========================================================
-- KPI 1: WEEKDAY VS WEEKEND PAYMENT STATISTICS
-- =========================================================
 
SELECT CASE WHEN DAYOFWEEK(o.order_purchase_timestamp) IN (1,7) THEN 'Weekend' ELSE 'Weekday' END AS day_type,
       COUNT(DISTINCT o.order_id) AS total_orders,
       ROUND(SUM(p.payment_value),2) AS total_payment,
       ROUND(AVG(p.payment_value),2) AS avg_payment_value,
       ROUND(SUM(p.payment_value) / COUNT(DISTINCT o.order_id),2) AS avg_payment_per_order
FROM orders o
JOIN payments p ON o.order_id = p.order_id
GROUP BY day_type;
-- Weekday 76593 | 12367988.08 | 154.44 | 161.48
-- Weekend 22847 |  3640884.04 | 152.95 | 159.36
 
-- Payment type breakdown
SELECT day_type, payment_type,
       COUNT(*) AS total_payments,
       ROUND(SUM(payment_value),2) AS total_value,
       ROUND(100 * COUNT(*) / SUM(COUNT(*)) OVER (PARTITION BY day_type),1) AS pct_in_day_type
FROM (SELECT p.payment_type, p.payment_value, 
	  CASE WHEN DAYOFWEEK(o.order_purchase_timestamp) IN (1,7) THEN 'Weekend' ELSE 'Weekday' END AS day_type
    FROM orders o JOIN payments p ON o.order_id = p.order_id) t
GROUP BY day_type, payment_type
ORDER BY day_type, total_payments DESC;
-- credit_card: Weekday 72.7% | Weekend 78.2%     boleto: Weekday 20.1% | Weekend 15.3%
 
-- =========================================================
-- KPI 2: ORDERS WITH REVIEW SCORE 5 AND PAYMENT TYPE CREDIT CARD
-- =========================================================
 
SELECT COUNT(DISTINCT p.order_id) AS orders_score5_credit_card
FROM payments p
JOIN reviews_clean r ON p.order_id = r.order_id
WHERE r.review_score = 5 AND p.payment_type = 'credit_card';   -- 43928
 
-- Payment type vs satisfaction
SELECT p.payment_type,
       COUNT(DISTINCT p.order_id) AS total_orders,
       COUNT(DISTINCT CASE WHEN r.review_score = 5 THEN p.order_id END) AS score5_orders,
       ROUND(100 * COUNT(DISTINCT CASE WHEN r.review_score = 5 THEN p.order_id END) / COUNT(DISTINCT p.order_id),1) AS pct_score5
FROM payments p
JOIN reviews_clean r ON p.order_id = r.order_id
GROUP BY p.payment_type
ORDER BY total_orders DESC;
 
-- =========================================================
-- KPI 3: AVERAGE DELIVERY TIME FOR PET SHOP
-- =========================================================
 
SELECT COUNT(*) AS pet_shop_orders,
       ROUND(AVG(TIMESTAMPDIFF(SECOND, order_purchase_timestamp, order_delivered_customer_date) / 86400),2) AS avg_delivery_days
FROM orders
WHERE order_delivered_customer_date IS NOT NULL
  AND order_id IN (SELECT i.order_id
                   FROM order_items i
                   JOIN products p ON i.product_id = p.product_id
                   WHERE p.product_category_name = 'pet_shop');
-- 1688 orders | 11.37 days
 
-- =========================================================
-- KPI 4: AVG ORDER PRICE AND PAYMENT AMOUNT - SAO PAULO CUSTOMERS
-- =========================================================
 
SELECT CASE WHEN c.customer_city = 'sao paulo' THEN 'Sao Paulo' ELSE 'Other Cities' END AS region,
       COUNT(*) AS total_orders,
       ROUND(AVG(i.order_price),2) AS avg_order_price,
       ROUND(AVG(p.order_payment),2) AS avg_payment_value
FROM orders o
JOIN customers c ON o.customer_id = c.customer_id
LEFT JOIN (SELECT order_id, SUM(price) AS order_price
           FROM order_items GROUP BY order_id) i ON o.order_id = i.order_id
LEFT JOIN (SELECT order_id, SUM(payment_value) AS order_payment
           FROM payments GROUP BY order_id) p ON o.order_id = p.order_id
GROUP BY region;
-- Sao Paulo    15540 | 124.33 | 141.79
-- Other Cities 83901 | 140.24 | 164.55
 
-- =========================================================
-- KPI 5: SHIPPING DAYS VS REVIEW SCORE
-- =========================================================
 
SELECT r.review_score,
       COUNT(*) AS total_orders,
       ROUND(AVG(TIMESTAMPDIFF(SECOND, o.order_purchase_timestamp, o.order_delivered_customer_date) / 86400),2) AS avg_shipping_days
FROM orders o
JOIN reviews_clean r ON o.order_id = r.order_id
WHERE o.order_delivered_customer_date IS NOT NULL
GROUP BY r.review_score
ORDER BY r.review_score;
-- 1: 21.32 | 2: 16.64 | 3: 14.26 | 4: 12.31 | 5: 10.68
 
-- =========================================================
-- DASHBOARD CARDS
-- =========================================================
 
SELECT (SELECT COUNT(*) FROM orders) AS total_orders,
       (SELECT ROUND(SUM(payment_value),2) FROM payments) AS total_sales,
       (SELECT COUNT(DISTINCT customer_unique_id) FROM customers) AS total_customers,
       (SELECT COUNT(*) FROM sellers) AS total_sellers,
       (SELECT ROUND(AVG(review_score),2) FROM reviews_clean) AS avg_review_score;
-- 99441 | 16008872.12 | 96096 | 3095 | 4.09
 
-- =========================================================
-- TOP 10 PRODUCT CATEGORIES BY SALES
-- =========================================================
 
SELECT COALESCE(t.product_category_name_english, p.product_category_name) AS category,
       ROUND(SUM(i.price),0) AS total_sales
FROM order_items i
JOIN products p ON i.product_id = p.product_id
LEFT JOIN product_category_translation t ON p.product_category_name = t.product_category_name
GROUP BY category
ORDER BY total_sales DESC
LIMIT 10;
-- health_beauty, watches_gifts, bed_bath_table ...