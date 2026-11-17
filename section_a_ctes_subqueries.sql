set search_path to sokomart;

show search_path;


-- =============================================================
-- SECTION A: CTEs and subqueries
-- =============================================================

-- =============================================================
-- Q1. Big spenders of 2025 (CTE + scalar subquery)
-- Result: 1432 rows (screenshot: screenshots/q01_big_spenders.png)
-- =============================================================
with customer_2025_revenue as (
    select 
        c.customer_id,
        c.first_name || ' ' || c.last_name as full_name,
        c.county,
        sum(i.line_total) as total_spent_2025
    from customers c
    join orders o on c.customer_id = o.customer_id
    join order_items i on o.order_id = i.order_id
    where o.order_status = 'completed'
      and o.order_date >= '2025-01-01' and o.order_date < '2026-01-01'
    group by c.customer_id, c.first_name, c.last_name, c.county
)
select 
    customer_id,
    full_name,
    county,
    total_spent_2025,
    (select avg(total_spent_2025) from customer_2025_revenue) as avg_spent_2025,
    (total_spent_2025 - (select avg(total_spent_2025) from customer_2025_revenue)) as amount_above_avg
from customer_2025_revenue
where total_spent_2025 > (select avg(total_spent_2025) from customer_2025_revenue)
order by total_spent_2025 desc;

-- Q1 second query: counts and averages
with customer_2025_revenue as (
    select c.customer_id, sum(i.line_total) as total_spent_2025
    from customers c
    join orders o on c.customer_id = o.customer_id
    join order_items i on o.order_id = i.order_id
    where o.order_status = 'completed'
      and o.order_date >= '2025-01-01' and o.order_date < '2026-01-01'
    group by c.customer_id
)
select 
    count(*) as customers_who_bought_in_2025,
    avg(total_spent_2025) as avg_spent_2025,
    count(*) filter (where total_spent_2025 > (select avg(total_spent_2025) from customer_2025_revenue)) as main_query_rows
from customer_2025_revenue;


-- =============================================================
-- Q2. Premium-priced products (correlated subquery)
-- Result: 104 rows (screenshot: screenshots/q02_premium_products.png)
-- =============================================================
select 
    product_id,
    product_name,
    category,
    unit_price,
    ROUND((select avg(unit_price) from products p2 where p2.category = p1.category), 2) as category_avg_price,
    ROUND(unit_price - (select avg(unit_price) from products p2 where p2.category = p1.category), 2) as price_gap
from products p1
where product_status = 'active'
  and unit_price > (select avg(unit_price) from products p2 where p2.category = p1.category)
order by category, price_gap desc;

-- Q2 second query: count per category
select 
    category,
    count(*) as premium_product_count
from products p1
where product_status = 'active'
  and unit_price > (select avg(unit_price) from products p2 where p2.category = p1.category)
group by category
order by category;


-- =============================================================
-- Q3. 2026 monthly profit and loss (chained CTEs)
-- Result: 10 rows (screenshot: screenshots/q03_monthly_pl_2026.png)
-- =============================================================
with order_lines_2026 as (
    select 
        date_trunc('month', o.order_date) as month,
        i.line_total as line_revenue,
        (i.quantity * p.cost_price) as line_cost
    from orders o
    join order_items i on o.order_id = i.order_id
    join products p on i.product_id = p.product_id
    where o.order_status = 'completed'
      and o.order_date >= '2026-01-01' and o.order_date < '2026-11-01'
),
monthly_totals as (
    select 
        month,
        sum(line_revenue) as revenue,
        sum(line_cost) as cost
    from order_lines_2026
    group by month
),
monthly_profit as (
    select 
        month,
        revenue,
        cost,
        (revenue - cost) as gross_profit
    from monthly_totals
)
select 
    to_char(month, 'yyyy-mm') as month,
    revenue,
    cost,
    gross_profit,
    round((gross_profit / revenue) * 100, 2) as margin_pct
from monthly_profit
order by month;


-- =============================================================
-- Q4. Cross-category shoppers in Nakuru (derived table)
-- Result: 346 rows (screenshot: screenshots/q04_nakuru_cross_category.png)
-- =============================================================
select 
    c.customer_id,
    c.first_name || ' ' || c.last_name as full_name,
    c.county,
    sub.category_count,
    sub.total_spent
from customers c
join (
    select 
        o.customer_id,
        count(distinct p.category) as category_count,
        sum(i.line_total) as total_spent
    from orders o
    join order_items i on o.order_id = i.order_id
    join products p on i.product_id = p.product_id
    where o.order_status = 'completed'
    group by o.customer_id
) sub on c.customer_id = sub.customer_id
where c.county = 'Nakuru'
  and sub.category_count >= 3
order by sub.category_count desc, sub.total_spent desc;

-- Q4 second query: counts
select 
    count(*) as qualifying_nakuru_customers,
    count(*) filter (where sub.category_count = 5) as bought_all_5_categories
from customers c
join (
    select o.customer_id, count(distinct p.category) as category_count
    from orders o
    join order_items i on o.order_id = i.order_id
    join products p on i.product_id = p.product_id
    where o.order_status = 'completed'
    group by o.customer_id
) sub on c.customer_id = sub.customer_id
where c.county = 'Nakuru'
  and sub.category_count >= 3;


-- =============================================================
-- Q5. Products nobody has ordered (NOT EXISTS)
-- Result: 24 rows (screenshot: screenshots/q05_unordered_products.png)
-- =============================================================
select 
    product_id,
    product_name,
    category,
    product_status,
    stock_quantity,
    created_at
from products p
where not exists (
    select 1 
    from order_items i 
    where i.product_id = p.product_id
)
order by category, product_name;