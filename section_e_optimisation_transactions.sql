set search_path to sokomart;

show search_path;


-- =============================================================
-- q21. read a query plan (explain analyze)
-- result: 91 rows (screenshot: screenshots/q21_query_plan.png)
-- =============================================================
/*
top_node | join_methods_used      | scan_on_orders | scan_on_customers | estimated_vs_actual_rows_orders | planning_ms | execution_ms | result_rows
---------|------------------------|----------------|-------------------|---------------------------------|-------------|--------------|------------
Sort     | Nested Loop, Hash Join | Seq Scan       | Seq Scan          | 2083 vs 2061                    | 128.812     | 22.625       | 91
*/

explain (analyze, buffers)
select c.customer_id, c.first_name, c.last_name, sum(i.line_total) as revenue
from customers c
join orders o on o.customer_id = c.customer_id
join order_items i on i.order_id = o.order_id
where c.county = 'Kisumu'
  and o.order_status = 'completed'
  and o.order_date >= '2026-09-01' and o.order_date < '2026-10-01'
group by c.customer_id, c.first_name, c.last_name
order by revenue desc;

-- =============================================================
-- q22. prove the indexes help
-- result: multiple plans (screenshot: screenshots/q22_indexes.png)
-- =============================================================
/*
query | scan_before | execution_ms_before | scan_after       | execution_ms_after | rows
------|-------------|---------------------|------------------|--------------------|-----
(1)   | Seq Scan    | 2.733               | Bitmap Heap Scan | 0.095              | 11
(2)   | Seq Scan    | 2.730               | Seq Scan         | 4.619              | 1
(3)   | Seq Scan    | 8.838               | Bitmap Heap Scan | 0.341              | 358
*/

DROP INDEX IF EXISTS 
    sokomart.idx_customers_county, 
    sokomart.idx_customers_registration_date,
    sokomart.idx_products_category, 
    sokomart.idx_orders_customer_id, 
    sokomart.idx_orders_order_date,
    sokomart.idx_orders_status_date, 
    sokomart.idx_orders_customer_date,
    sokomart.idx_order_items_product_id, 
    sokomart.idx_payments_order_id,
    sokomart.idx_payments_status_method, 
    sokomart.idx_payments_payment_date,
    sokomart.idx_price_history_product_id, 
    sokomart.idx_status_history_order_id;

-- 2. Update stats
ANALYZE sokomart.orders, sokomart.payments, sokomart.order_items;

-- 3. Run Query (1) BEFORE
EXPLAIN ANALYZE 
SELECT order_id, order_date, total_amount FROM orders WHERE customer_id = 408 ORDER BY order_date;

-- 4. Run Query (2) BEFORE
EXPLAIN ANALYZE 
SELECT * FROM payments WHERE order_id = 25000;

-- 5. Run Query (3) BEFORE
EXPLAIN ANALYZE 
SELECT order_id, quantity, line_total FROM order_items WHERE product_id = 71;


-- customer access paths
CREATE INDEX IF NOT EXISTS idx_customers_county            ON sokomart.customers (county);
CREATE INDEX IF NOT EXISTS idx_customers_registration_date ON sokomart.customers (registration_date);

-- product access paths
CREATE INDEX IF NOT EXISTS idx_products_category           ON sokomart.products (category);

-- order access paths
CREATE INDEX IF NOT EXISTS idx_orders_customer_id          ON sokomart.orders (customer_id);
CREATE INDEX IF NOT EXISTS idx_orders_order_date           ON sokomart.orders (order_date);
CREATE INDEX IF NOT EXISTS idx_orders_status_date          ON sokomart.orders (order_status, order_date);
CREATE INDEX IF NOT EXISTS idx_orders_customer_date        ON sokomart.orders (customer_id, order_date);

-- order item access paths (uq_order_items_order_product already covers order_id lookups)
CREATE INDEX IF NOT EXISTS idx_order_items_product_id      ON sokomart.order_items (product_id);

-- payment access paths
CREATE INDEX IF NOT EXISTS idx_payments_order_id           ON sokomart.payments (order_id);
CREATE INDEX IF NOT EXISTS idx_payments_status_method      ON sokomart.payments (payment_status, payment_method);
CREATE INDEX IF NOT EXISTS idx_payments_payment_date       ON sokomart.payments (payment_date);

-- history tables
CREATE INDEX IF NOT EXISTS idx_price_history_product_id    ON sokomart.product_price_history (product_id);
CREATE INDEX IF NOT EXISTS idx_status_history_order_id     ON sokomart.order_status_history (order_id);

ANALYZE sokomart.customers, sokomart.products, sokomart.orders,
        sokomart.order_items, sokomart.payments;

-- 1. Run Query (1) AFTER
EXPLAIN ANALYZE 
SELECT order_id, order_date, total_amount FROM orders WHERE customer_id = 408 ORDER BY order_date;

-- 2. Run Query (2) AFTER
EXPLAIN ANALYZE 
SELECT * FROM payments WHERE order_id = 25000;

-- 3. Run Query (3) AFTER
EXPLAIN ANALYZE 
SELECT order_id, quantity, line_total FROM order_items WHERE product_id = 71;

CREATE INDEX idx_orders_pending_date ON orders(order_date) WHERE order_status = 'pending';

EXPLAIN ANALYZE 
SELECT * FROM orders 
WHERE order_status = 'pending' AND order_date < '2026-10-25';

SELECT 
    pg_size_pretty(pg_relation_size('idx_orders_pending_date')) AS partial_index_size,
    pg_size_pretty(pg_relation_size('idx_orders_order_date')) AS full_index_size;

-- =============================================================
-- q23. transactions you can see
-- result: multiple outputs (screenshot: screenshots/q23_transactions.png)
-- =============================================================

-- (a)
-- 1 row
select avg(unit_price) from products where category = 'Beauty';
begin;
update products set unit_price = round(unit_price * 0.9, 2) where category = 'Beauty';
select avg(unit_price) from products where category = 'Beauty';
rollback;
select avg(unit_price) from products where category = 'Beauty';

-- (b)
-- 2 rows (the select query after rollback)
select product_id, stock_quantity from products where product_id in (59, 166);
begin;
update products set stock_quantity = stock_quantity + 40 where product_id = 59;
insert into audit_logs (table_name, record_id, action, old_data, new_data) 
values ('products', 59, 'UPDATE', null, null);
savepoint after_restock;
update products set stock_quantity = 0 where product_id = 166;
select product_id, stock_quantity from products where product_id in (59, 166);
rollback to savepoint after_restock;
commit;
select product_id, stock_quantity from products where product_id in (59, 166);

-- (c)
-- 1 row
begin;
update products set stock_quantity = stock_quantity + 1 where product_id = 166;
-- update products set stock_quantity = -5 where product_id = 166; -- throws error
commit;
select product_id, stock_quantity from products where product_id = 166;

-- =============================================================
-- q24. clean up the duplicate payments
-- result: multiple outputs (screenshot: screenshots/q24_dedup_payments.png)
-- =============================================================
-- (a)
-- 1 row
with ranked_payments as (
    select payment_id, row_number() over (partition by payment_id, order_id, payment_date, payment_method, amount, payment_status, transaction_reference order by loaded_at, staging_id) as copy_no
    from payment_staging
)
select 
    count(distinct payment_id) filter (where copy_no > 1) as duplicated_payments,
    count(*) filter (where copy_no > 1) as extra_rows_to_delete,
    max(copy_no) as max_copies
from ranked_payments;

-- (b)
-- 10 rows
with ranked_payments as (
    select staging_id, payment_id, transaction_reference, amount, source_file, loaded_at,
           row_number() over (partition by payment_id, order_id, payment_date, payment_method, amount, payment_status, transaction_reference order by loaded_at, staging_id) as copy_no
    from payment_staging
)
select * from ranked_payments where copy_no > 1 order by staging_id limit 10;




-- (c)
-- 1 row

select count(*) as staging_rows_before, count(distinct payment_id) as distinct_payments_before from payment_staging;
begin;
with duplicates as (
    select staging_id, row_number() over (partition by payment_id, order_id, payment_date, payment_method, amount, payment_status, transaction_reference order by loaded_at, staging_id) as copy_no
    from payment_staging
)
delete from payment_staging using duplicates where payment_staging.staging_id = duplicates.staging_id and duplicates.copy_no > 1;

select 
    count(*) as staging_rows_after, 
    count(distinct payment_id) as distinct_payments_after,
    sum(amount) as staged_amount_after,
    (sum(amount) = (select sum(amount) from payments)) as same_payments_in_payments_table
from payment_staging;
commit;

-- (d)
create unique index idx_payment_staging_unique on payment_staging(payment_id);
insert into payment_staging (payment_id, order_id, payment_date, payment_method, amount, payment_status, transaction_reference, source_file, loaded_at)
values (1, 1, '2026-01-01', 'card', 100, 'successful', 'txn1', 'test.csv', current_timestamp);

-- =============================================================
-- q25. three months in a row (gaps and islands)
-- result: 10 rows (screenshot: screenshots/q25_three_months.png)
-- =============================================================
with customer_months as (
    select distinct 
        o.customer_id, 
        c.first_name || ' ' || c.last_name as full_name,
        c.county,
        date_trunc('month', o.order_date) as purchase_month
    from orders o
    join customers c on o.customer_id = c.customer_id
    where o.order_status = 'completed'
),
numbered_months as (
    select 
        customer_id,
        full_name,
        county,
        purchase_month,
        row_number() over (partition by customer_id order by purchase_month) as rn,
        extract(year from purchase_month) * 12 + extract(month from purchase_month) as month_num
    from customer_months
),
grouped_streaks as (
    select 
        customer_id,
        full_name,
        county,
        (month_num - rn) as streak_group,
        min(purchase_month) as streak_start_month,
        max(purchase_month) as streak_end_month,
        count(*) as streak_length
    from numbered_months
    group by customer_id, full_name, county, (month_num - rn)
    having count(*) >= 3
),
longest_streaks as (
    select 
        customer_id,
        full_name,
        county,
        streak_start_month,
        streak_end_month,
        streak_length,
        row_number() over (partition by customer_id order by streak_length desc, streak_start_month asc) as streak_rank
    from grouped_streaks
)
select 
    customer_id,
    full_name,
    county,
    to_char(streak_start_month, 'yyyy-mm') as streak_start_month,
    to_char(streak_end_month, 'yyyy-mm') as streak_end_month,
    streak_length
from longest_streaks
where streak_rank = 1
order by streak_length desc, customer_id
limit 10;

-- q25 second query
-- 1 row

with customer_months as (
    select distinct o.customer_id, date_trunc('month', o.order_date) as purchase_month
    from orders o
    where o.order_status = 'completed'
),
numbered_months as (
    select customer_id, 
           row_number() over (partition by customer_id order by purchase_month) as rn,
           extract(year from purchase_month) * 12 + extract(month from purchase_month) as month_num
    from customer_months
),
grouped_streaks as (
    select customer_id, count(*) as streak_length
    from numbered_months
    group by customer_id, (month_num - rn)
    having count(*) >= 3
)
select 
    count(distinct customer_id) as customers_with_3plus_streak,
    max(streak_length) as longest_streak
from grouped_streaks;