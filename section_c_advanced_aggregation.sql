set search_path to sokomart;

show search_path;

-- =============================================================
-- q11. customer tiers (nested derived tables, scalar subquery)
-- result: 4 rows (screenshot: screenshots/q11_customer_tiers.png)
-- =============================================================
with customer_totals as (
    select o.customer_id, sum(i.line_total) as lifetime_spent
    from orders o
    join order_items i on o.order_id = i.order_id
    where o.order_status = 'completed'
    group by o.customer_id
),
customer_tiers as (
    select 
        customer_id, 
        lifetime_spent,
        case 
            when lifetime_spent >= 1000000 then 'Platinum'
            when lifetime_spent >= 500000 then 'Gold'
            when lifetime_spent >= 100000 then 'Silver'
            else 'Bronze'
        end as tier
    from customer_totals
)
select 
    tier,
    count(customer_id) as customer_count,
    min(lifetime_spent) as min_spent,
    max(lifetime_spent) as max_spent,
    round(avg(lifetime_spent), 2) as avg_spent,
    round((sum(lifetime_spent) / (select sum(lifetime_spent) from customer_totals)) * 100, 2) as revenue_share_pct
from customer_tiers
group by tier
order by 
    case tier 
        when 'Platinum' then 1 
        when 'Gold' then 2 
        when 'Silver' then 3 
        when 'Bronze' then 4 
    end;

-- =============================================================
-- q12. what did mombasa buy in october? (string_agg, exists)
-- result: 152 rows (screenshot: screenshots/q12_mombasa_october.png)
-- =============================================================
select 
    c.customer_id,
    c.first_name || ' ' || c.last_name as full_name,
    count(distinct p.product_id) as product_count,
    string_agg(distinct p.product_name, '; ' order by p.product_name) as products_ordered
from customers c
join orders o on c.customer_id = o.customer_id
join order_items i on o.order_id = i.order_id
join products p on i.product_id = p.product_id
where c.county = 'Mombasa'
  and exists (
      select 1 
      from orders o2 
      where o2.customer_id = c.customer_id 
        and o2.order_status != 'cancelled' 
        and o2.order_date >= '2026-10-01' and o2.order_date < '2026-11-01'
  )
  and o.order_status != 'cancelled'
  and o.order_date >= '2026-10-01' and o.order_date < '2026-11-01'
group by c.customer_id, c.first_name, c.last_name
order by product_count desc, c.customer_id;



-- q12 second query: count
select count(distinct c.customer_id) as qualifying_customers
from customers c
where c.county = 'Mombasa'
  and exists (
      select 1 
      from orders o 
      where o.customer_id = c.customer_id 
        and o.order_status != 'cancelled' 
        and o.order_date >= '2026-10-01' and o.order_date < '2026-11-01'
  );

-- =============================================================
-- q13. payment health by method, 2026 (filter, cte)
-- result: 4 rows (screenshot: screenshots/q13_payment_health.png)
-- =============================================================
with payments_2026 as (
    select payment_method, payment_status, amount
    from payments
    where payment_date >= '2026-01-01' and payment_date < '2027-01-01'
)
select 
    payment_method,
    count(*) as total_payments,
    count(*) filter (where payment_status = 'successful') as successful,
    count(*) filter (where payment_status = 'failed') as failed,
    count(*) filter (where payment_status = 'pending') as pending,
    round((count(*) filter (where payment_status = 'successful') * 100.0) / nullif(count(*), 0), 2) as success_rate_pct,
    coalesce(sum(amount) filter (where payment_status = 'failed'), 0) as failed_amount
from payments_2026
group by payment_method
order by total_payments desc;

-- =============================================================
-- q14. which departments carry the profit? (cte + scalar subqueries)
-- result: 2 rows (screenshot: screenshots/q14_profit_departments.png)
-- =============================================================
with category_profit_2025 as (
    select 
        p.category,
        sum(i.line_total) as revenue,
        sum(i.line_total - (i.quantity * p.cost_price)) as gross_profit
    from orders o
    join order_items i on o.order_id = i.order_id
    join products p on i.product_id = p.product_id
    where o.order_status = 'completed'
      and o.order_date >= '2025-01-01' and o.order_date < '2026-01-01'
    group by p.category
)
select 
    category,
    revenue,
    gross_profit,
    round((gross_profit / revenue) * 100, 2) as margin_pct,
    (select avg(gross_profit) from category_profit_2025) as avg_category_gross_profit,
    round(((gross_profit - (select avg(gross_profit) from category_profit_2025)) / (select avg(gross_profit) from category_profit_2025)) * 100, 2) as pct_above_avg
from category_profit_2025
where gross_profit > (select avg(gross_profit) from category_profit_2025)
order by gross_profit desc;

-- =============================================================
-- q15. one sales table with subtotals (grouping sets)
-- result: 36 rows (screenshot: screenshots/q15_sales_subtotals.png)
-- =============================================================
with target_sales_2026 as (
    select 
        o.shipping_county as county,
        p.category,
        i.line_total,
        o.order_id
    from orders o
    join order_items i on o.order_id = i.order_id
    join products p on i.product_id = p.product_id
    where o.order_status = 'completed'
      and o.order_date >= '2026-01-01' and o.order_date < '2027-01-01'
      and o.shipping_county in ('Nairobi', 'Mombasa', 'Kisumu', 'Nakuru', 'Uasin Gishu')
)
select 
    case grouping(county, category)
        when 0 then 'county x category'
        when 1 then 'county total'
        when 2 then 'category total'
        when 3 then 'grand total'
    end as grouping_level,
    coalesce(county, 'ALL COUNTIES') as county,
    coalesce(category, 'ALL CATEGORIES') as category,
    sum(line_total) as revenue,
    count(distinct order_id) as order_count
from target_sales_2026
group by grouping sets (
    (county, category),
    (county),
    (category),
    ()
)
order by grouping(county, category), county, category;


