set search_path to sokomart;

show search_path;

-- =============================================================
-- SECTION B: Window functions
-- =============================================================

-- =============================================================
-- Q6. County leaderboards (DENSE_RANK)
-- Result: 42 rows (screenshot: screenshots/q06_county_leaderboards.png)
-- =============================================================
with customer_lifetime as (
    select 
        c.county, 
        c.customer_id, 
        c.first_name || ' ' || c.last_name as full_name, 
        sum(i.line_total) as total_spent
    from customers c
    join orders o on c.customer_id = o.customer_id
    join order_items i on o.order_id = i.order_id
    where o.order_status = 'completed'
    group by c.county, c.customer_id, c.first_name, c.last_name
),
ranked_customers as (
    select 
        county,
        dense_rank() over (partition by county order by total_spent desc) as county_rank,
        customer_id,
        full_name,
        total_spent
    from customer_lifetime
)
select 
    county,
    county_rank,
    customer_id,
    full_name,
    total_spent
from ranked_customers
where county_rank <= 3
order by county, county_rank, customer_id;


-- =============================================================
-- Q7. Best sellers per category, 2025 (ROW_NUMBER)
-- Result: 15 rows (screenshot: screenshots/q07_best_sellers_2025.png)
-- =============================================================
with product_sales_2025 as (
    select 
        p.category, 
        p.product_id, 
        p.product_name, 
        sum(i.line_total) as revenue, 
        sum(i.quantity) as units_sold
    from products p
    join order_items i on p.product_id = i.product_id
    join orders o on i.order_id = o.order_id
    where o.order_status = 'completed'
      and o.order_date >= '2025-01-01' and o.order_date < '2026-01-01'
    group by p.category, p.product_id, p.product_name
),
ranked_products as (
    select 
        category,
        row_number() over (partition by category order by revenue desc, product_id) as rank_in_category,
        product_id,
        product_name,
        revenue,
        units_sold
    from product_sales_2025
)
select 
    category,
    rank_in_category,
    product_id,
    product_name,
    revenue,
    units_sold
from ranked_products
where rank_in_category <= 3
order by category, rank_in_category;


-- =============================================================
-- Q8. Month-over-month growth (LAG)
-- Result: 22 rows (screenshot: screenshots/q08_mom_growth.png)
-- =============================================================
with monthly_revenue as (
    select 
        date_trunc('month', o.order_date) as month_val, 
        sum(i.line_total) as revenue
    from orders o
    join order_items i on o.order_id = i.order_id
    where o.order_status = 'completed'
    group by date_trunc('month', o.order_date)
),
lagged_revenue as (
    select 
        to_char(month_val, 'yyyy-mm') as month,
        revenue,
        lag(revenue) over (order by month_val) as prev_month_revenue
    from monthly_revenue
)
select 
    month,
    revenue,
    prev_month_revenue,
    round(((revenue - prev_month_revenue) / nullif(prev_month_revenue, 0)) * 100, 2) as growth_pct
from lagged_revenue
order by month;


-- =============================================================
-- Q9. Is each order bigger than the last? (LAG with partition)
-- Result: 1332 rows (screenshot: screenshots/q09_nyeri_order_trends.png)
-- =============================================================
with nyeri_orders as (
    select 
        o.customer_id, 
        o.order_id, 
        o.order_date, 
        sum(i.line_total) as total_amount
    from orders o
    join customers c on o.customer_id = c.customer_id
    join order_items i on o.order_id = i.order_id
    where c.county = 'Nyeri'
      and o.order_status = 'completed'
      and o.order_date >= '2026-01-01' and o.order_date < '2027-01-01'
    group by o.customer_id, o.order_id, o.order_date
),
lagged_orders as (
    select 
        customer_id,
        order_id,
        order_date,
        total_amount,
        lag(total_amount) over (partition by customer_id order by order_date) as previous_order_amount
    from nyeri_orders
),
calculated_directions as (
    select 
        customer_id,
        order_id,
        order_date,
        total_amount,
        previous_order_amount,
        (total_amount - previous_order_amount) as change_amount,
        case 
            when previous_order_amount is null then 'first order'
            when total_amount > previous_order_amount then 'up'
            when total_amount < previous_order_amount then 'down'
            else 'same'
        end as direction
    from lagged_orders
)
select * from calculated_directions
order by customer_id, order_date;

-- Q9 second query: summary counts
with nyeri_orders as (
    select 
        o.customer_id, 
        o.order_date, 
        sum(i.line_total) as total_amount
    from orders o
    join customers c on o.customer_id = c.customer_id
    join order_items i on o.order_id = i.order_id
    where c.county = 'Nyeri'
      and o.order_status = 'completed'
      and o.order_date >= '2026-01-01' and o.order_date < '2027-01-01'
    group by o.customer_id, o.order_id, o.order_date
),
lagged_orders as (
    select 
        customer_id,
        total_amount,
        lag(total_amount) over (partition by customer_id order by order_date) as previous_order_amount
    from nyeri_orders
)
select 
    count(*) as total_rows,
    count(distinct customer_id) as distinct_customers,
    count(*) filter (where previous_order_amount is null) as first_orders,
    count(*) filter (where total_amount > previous_order_amount) as bigger_than_previous,
    count(*) filter (where total_amount < previous_order_amount) as smaller_than_previous
from lagged_orders;


-- =============================================================
-- Q10. Year-to-date revenue (SUM over partition with explicit frame)
-- Result: 22 rows (screenshot: screenshots/q10_ytd_revenue.png)
-- =============================================================
with monthly_totals as (
    select 
        cast(extract(year from o.order_date) as integer) as year,
        to_char(o.order_date, 'yyyy-mm') as month,
        sum(i.line_total) as monthly_revenue
    from orders o
    join order_items i on o.order_id = i.order_id
    where o.order_status = 'completed'
    group by extract(year from o.order_date), to_char(o.order_date, 'yyyy-mm')
)
select 
    year,
    month,
    monthly_revenue,
    sum(monthly_revenue) over (
        partition by year 
        order by month 
        rows between unbounded preceding and current row
    ) as running_revenue_ytd,
    sum(monthly_revenue) over (
        order by month 
        rows between unbounded preceding and current row
    ) as running_revenue_all_time
from monthly_totals
order by month;