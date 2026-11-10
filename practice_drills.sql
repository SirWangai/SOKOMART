set search_path to sokomart;
show search_path;

-- d1: products above overall average unit price
select 
    product_id, 
    product_name, 
    category, 
    unit_price, 
    (select avg(unit_price) from products) as overall_avg_price
from products
where unit_price > (select avg(unit_price) from products)
order by unit_price desc
limit 10;

-- row count
select count(*) as products_above_avg
from products
where unit_price > (select avg(unit_price) from products);

-- d2: mombasa customers with orders in december 2025
select customer_id, first_name, last_name, email
from customers
where county = 'Mombasa'
  and customer_id in (
      select customer_id 
      from orders 
      where order_date >= '2025-12-01' and order_date < '2026-01-01'
  );

-- row count
select count(*) as mombasa_dec_2025_customers
from customers
where county = 'Mombasa'
  and customer_id in (
      select customer_id 
      from orders 
      where order_date >= '2025-12-01' and order_date < '2026-01-01'
  );

-- d3: kisumu customers with failed payments
select count(*) as kisumu_customers_with_failed_payment
from customers c
where county = 'Kisumu'
  and exists (
      select 1 
      from orders o
      join payments p on o.order_id = p.order_id
      where o.customer_id = c.customer_id
        and p.payment_status = 'failed'
  );

-- d4: order status breakdown using a subquery in from
select 
    o.order_status, 
    count(o.order_id) as orders, 
    round(avg(sub.lines_per_order), 2) as avg_lines_per_order, 
    round(avg(sub.units_per_order), 2) as avg_units_per_order
from orders o
join (
    select 
        order_id, 
        count(product_id) as lines_per_order, 
        sum(quantity) as units_per_order
    from order_items
    group by order_id
) sub on o.order_id = sub.order_id
group by o.order_status;

-- d5: top 5 shipping counties by completed 2026 orders
with completed_2026 as (
    select shipping_county, order_id
    from orders
    where order_status = 'completed'
      and order_date >= '2026-01-01' and order_date < '2027-01-01'
)
select 
    shipping_county, 
    count(order_id) as completed_orders
from completed_2026
group by shipping_county
order by completed_orders desc
limit 5;

-- d6: monthly order performance against the 2025 average
with monthly_counts as (
    select 
        date_trunc('month', order_date) as month, 
        count(order_id) as completed_orders
    from orders
    where order_status = 'completed'
      and order_date >= '2025-01-01' and order_date < '2026-01-01'
    group by date_trunc('month', order_date)
),
average_calc as (
    select avg(completed_orders) as avg_per_month 
    from monthly_counts
)
select 
    m.month, 
    m.completed_orders, 
    round(a.avg_per_month, 2) as avg_per_month,
    case 
        when m.completed_orders > a.avg_per_month then 'above average'
        else 'at/below average'
    end as vs_average
from monthly_counts m
cross join average_calc a
order by m.month;

-- d7: custom order count function
create or replace function fn_order_count(p_customer_id integer) 
returns integer 
language plpgsql as $$
declare
    v_count integer;
begin
    select count(order_id) into v_count
    from orders
    where customer_id = p_customer_id;
    
    return v_count;
end;
$$;

-- function calls
select fn_order_count(177);
select fn_order_count(-1);

-- d8: update customer status with exception handling
create or replace procedure sp_set_customer_status(p_customer_id integer, p_status varchar)
language plpgsql as $$
begin
    if p_status not in ('active', 'inactive', 'suspended') then
        raise exception 'invalid status. must be active, inactive, or suspended.';
    end if;

    if not exists (select 1 from customers where customer_id = p_customer_id) then
        raise exception 'customer % does not exist.', p_customer_id;
    end if;

    update customers
    set customer_status = p_status
    where customer_id = p_customer_id;
end;
$$;

-- test rollback
begin;
call sp_set_customer_status(177, 'suspended');
select customer_id, customer_status from customers where customer_id = 177;
rollback;
select customer_id, customer_status from customers where customer_id = 177;

-- test exception
call sp_set_customer_status(177, 'vip');

-- d9: CTE + scalar subquery
with beauty_products as (
    select product_id, product_name, stock_quantity
    from products
    where category = 'Beauty'
)
select 
    product_id, 
    product_name, 
    stock_quantity,
    (select avg(stock_quantity) from beauty_products) as beauty_avg_stock
from beauty_products
where stock_quantity < (select avg(stock_quantity) from beauty_products)
order by stock_quantity;

-- d10: procedure with out parameters
create or replace procedure sp_county_summary(
    in p_county varchar, 
    out p_customers integer, 
    out p_revenue numeric
)
language plpgsql as $$
begin
    select count(distinct c.customer_id) into p_customers
    from customers c
    where c.county = p_county;

    select coalesce(sum(i.line_total), 0) into p_revenue
    from orders o
    join order_items i on o.order_id = i.order_id
    join customers c on o.customer_id = c.customer_id
    where c.county = p_county
      and o.order_status = 'completed';
end;
$$;

-- call the procedure
call sp_county_summary('Nakuru', null, null);