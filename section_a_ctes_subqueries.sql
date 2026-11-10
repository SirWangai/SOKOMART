-- q1. big spenders of 2025 (cte + scalar subquery)
-- result
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

-- q1 second query: counts and averages
-- result:

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


-- q2. premium-priced products (correlated subquery)
-- result:
select 
    product_id,
    product_name,
    category,
    unit_price,
    (select avg(unit_price) from products p2 where p2.category = p1.category) as category_avg_price,
    unit_price - (select avg(unit_price) from products p2 where p2.category = p1.category) as price_gap
from products p1
where product_status = 'active'
  and unit_price > (select avg(unit_price) from products p2 where p2.category = p1.category)
order by category, price_gap desc;

-- q2 second query: count per category
-- result:
select 
    category,
    count(*) as premium_product_count
from products p1
where product_status = 'active'
  and unit_price > (select avg(unit_price) from products p2 where p2.category = p1.category)
group by category
order by category;


-- q3. 2026 monthly profit and loss (chained ctes)
-- result: 10 rows

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


-- q4. cross-category shoppers in nakuru (derived table)
-- result: [row count] rows
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

-- q4 second query: counts
-- result:

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


