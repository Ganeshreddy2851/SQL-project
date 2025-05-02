/* Analyse sales performace over time (trend analysis) */

select 
year(order_date) as Sales_Year, sum(sales_amount) as total_sales,
count(distinct customer_key) as customers,
sum(quantity) as Total_quantity
from gold.fact_sales
where order_date is not null
group by year(order_date)
order by 1

select 
--year(order_date) as Sales_Year, 
DATETRUNC(month, order_date),
--month(order_date) as Sales_Month, 
sum(sales_amount) as total_sales,
count(distinct customer_key) as customers,
sum(quantity) as Total_quantity
from gold.fact_sales
where order_date is not null
group by DATETRUNC(month, order_date)
--group by year(order_date), month(order_date)
order by 1

select 
--year(order_date) as Sales_Year, 
format(order_date, 'yyyy-MMM'),
--month(order_date) as Sales_Month, 
sum(sales_amount) as total_sales,
count(distinct customer_key) as customers,
sum(quantity) as Total_quantity
from gold.fact_sales
where order_date is not null
group by format(order_date, 'yyyy-MMM')
--group by year(order_date), month(order_date)
order by 1


/* cumulative analysis */
/* agreegate data progressively overtime - helps us to know whether business is growing or declining */
--calculate the total sales of month and running sales over time.
select
order_month,
total_sales,
avg(average_price) over(order by order_month) as running_avg_price, --over is mandatory for window fn.
--sum(total_sales)  over(order by order_month) as running_total
sum(total_sales) over(partition by year(order_month) order by order_month) as running_total
from 
--cummulative resets at end of every year with this partition.
(
select 
datetrunc(month, order_date) as order_month,
sum(sales_amount) as total_sales,
AVG(price) as average_price
from gold.fact_sales
where order_date is not null
group by datetrunc(month, order_date)
) t ---without this 't' there is an error.

/*Performance analysis*/
/*comparing current value to target value
anlayse the yearly perfomance of products by comparing each products sales
to both its average sales performance and it's previous years sales*/

WITH yearly_product_sales as (
-- common table expression.
select 
year(a.order_date) as Sales_year,
sum(a.sales_amount) as current_sales,
b.product_name
from 
gold.fact_sales a
--where order_date is not null --where clause doesn't work here, it has to be used after using left join.
left join gold.dim_products b
on a.product_key = b.product_key
where order_date is not null
group by year(order_date),
b.product_name --order cannot be used in common table expressions
)              --we need to excecute with below select query as well along with cte

select 
Sales_year,
product_name,
current_sales,
avg(current_sales) over(partition by product_name) as avg_sales,
(current_sales - avg(current_sales) over(partition by product_name)) as diff_avg, 
--donot use column name(avg_sales) here.
case when current_sales - avg(current_sales) over(partition by product_name) < 0 then 'below_avg' 
     when current_sales - avg(current_sales) over(partition by product_name) > 0 then 'above_avg'
	 else 'avg' --donot forget 'then' keyword and ''
end performance, --this would be column name

--year_over_year_analysis
LAG(current_sales) over(partition by product_name order by Sales_year) as prev_sales,
current_sales - LAG(current_sales) over(partition by product_name order by Sales_year) as diff_in_sales,
case when current_sales - LAG(current_sales) over(partition by product_name order by Sales_year) < 0 then 'decrease' 
     when current_sales - LAG(current_sales) over(partition by product_name order by Sales_year) > 0 then 'increase'
	 else 'no_change'
end prev_change 
from 
yearly_product_sales
order by 2,1 --sorting by product name first and then year gives better picture of sales


/*part to whole anlaysis or proportional analysis*/
--analyse how an individual part is performing compared to the overall,
--allowing us to undersatnd which part ha greatest impact on the business.
--task :- which category contributes more to the overall sales.

with category_sales as (select 
category,
sum(sales_amount) total_sales
from 
gold.fact_sales a
left join  gold.dim_products b
on a.product_key = b.product_key
group by category)
--important 
--without calculating the sum we cannot use group by, since group by doesn't add it just groups the same items.

select 
category,
total_sales,
--sum(total_sales) ;- it doesn't work here becuase there is no commanality to add.
sum(total_sales) over(),
--(total_sales/sum(total_sales) over())*100 percentage_sales ;- we get zero because it doesn't support decimal forms
concat(round((cast (total_sales as float)/sum(total_sales) over())*100, 2), '%') percentage_sales
from category_sales
order by percentage_sales desc


/*Data segmentation*/
/*group the data based on a specific range;- helps understand the correlation between two measures*/
/*task;- segment products in cost ranges and count how many products fall into each range */

with product_segments as (select 
product_key,
product_name,
cost,
case when cost < 100 then 'below 100'
     when cost between 100 and  500 then '100-500'
	 when cost between 500 and 1000 then '500-1000'
	 else 'above 1000'
end price_range
from 
gold.dim_products
)

select 
price_range,
count(product_key) as total_products
from 
product_segments
group by price_range
order by 2 desc

/*task;- group customers into 3 segments based on their spending behaviour:
   - VIP:- atleast 12 months of history and spending more than 5000.
   - Regualr:- atleast 12 months of history and spending 5000 or less.
   - New:- less than 12 months of history.
find the total number of customers by each group*/

with sales_report as (select
customer_key,
sum(sales_amount) as total_spent,
min(order_date) as first_date,
max(order_date) as last_order,
DATEDIFF(MONTH, min(order_date), max(order_date)) as duration 
from 
gold.fact_sales
group by customer_key
)

select 
cust_type,
count(customer_key) as total_customers
from(
select 
customer_key,
--total_spent,
--duration,
case when duration >= 12 and total_spent > 5000 then 'VIP'
     when duration >= 12 and total_spent <= 5000 then 'regular'
	 else 'new'
end 'cust_type'
from 
sales_report) t --we need to name the sub query
group by cust_type
order by 1 

/*-----customer_Report------*/
/* aim
      ;- this report consolidates key customer metrics and behaviours
	
key points:-
      1. Gather essential fields such as name, age and transaction details
	  2. Segment customers in catergories(new, regualar and VIP) based on spending and time spent.
	  3. Aggregates customer level metrics:-
	     -total orders
		 -total sales
		 -total quantity purchased
		 -total products
		 -lifespan(in months)
	  4. Calculates valuable KPIs
	      -recency;- months since last order
		  -average order value 
		  -average money spent */


create view gold.customer_report AS
with base_query as
(select
/* retrieves core columns from the data set */
a.order_number,
a.product_key,
a.order_date,
a.sales_amount,
a.quantity,
b.customer_key,
b.customer_number,
--b.first_name,
--b.last_name,
concat(b.first_name, ' ', b.last_name) as customer_name,
--b.birthdate
DATEDIFF(year, b.birthdate, GETDATE()) as age
from 
gold.fact_sales a
left join gold.dim_customers b
on a.customer_key = b.customer_key
where a.order_date is not null)

--aggregating customer metrics
,customer_aggregations as --you don't have to use the with key word for 2nd cte, use ',' at the start
(select
customer_key,
customer_number,
customer_name,
age,
count(distinct order_number) as total_orders,
sum(sales_amount) as total_spent,
sum(quantity) as total_quantity,
count(distinct product_key) as total_products,
max(order_date) as last_order_date,
datediff(month, min(order_date), max(order_date)) as duration
from
base_query
group by
 customer_key,
 customer_number,
 customer_name,
 age)

 select
 customer_key,
 customer_number,
 customer_name,
 age,
 case when age < 20 then 'under 20'
      when age between 20 and 29 then '20-29'
      when age between 30 and 39 then '30-39'
	  when age between 40 and 49 then '40-49'
      else '50+'
end age_groups,
 case when duration >= 12 and total_spent > 5000 then 'VIP'
      when duration >= 12 and total_spent <= 5000 then 'regular'
	  else 'new'
end 'cust_type',
last_order_date,
DATEDIFF(month, last_order_date, getdate()) as recency,
 total_orders,
 total_spent,
 total_quantity,
 total_products,
 duration,
 --computing average order value
 case when total_orders = 0 then 0 --to make sure we are not dividing by 0
     else
     (total_spent/total_orders) 
	 end as avg_order_value,
--computing average monthly spent
case when duration = 0 then total_spent
     else
    (total_spent/duration) 
	 end as monthly_avg_spent
 from
 customer_aggregations

 select * from gold.customer_report

 select * from gold.dim_products

 
 
 CREATE VIEW gold.report_products AS

WITH base_query AS (
/*---------------------------------------------------------------------------
1) Base Query: Retrieves core columns from fact_sales and dim_products
---------------------------------------------------------------------------*/
    SELECT
	    f.order_number,
        f.order_date,
		f.customer_key,
        f.sales_amount,
        f.quantity,
        p.product_key,
        p.product_name,
        p.category,
        p.subcategory,
        p.cost
    FROM gold.fact_sales f
    LEFT JOIN gold.dim_products p
        ON f.product_key = p.product_key
    WHERE order_date IS NOT NULL  -- only consider valid sales dates
),

product_aggregations AS (
/*---------------------------------------------------------------------------
2) Product Aggregations: Summarizes key metrics at the product level
---------------------------------------------------------------------------*/
SELECT
    product_key,
    product_name,
    category,
    subcategory,
    cost,
    DATEDIFF(MONTH, MIN(order_date), MAX(order_date)) AS lifespan,
    MAX(order_date) AS last_sale_date,
    COUNT(DISTINCT order_number) AS total_orders,
	COUNT(DISTINCT customer_key) AS total_customers,
    SUM(sales_amount) AS total_sales,
    SUM(quantity) AS total_quantity,
	ROUND(AVG(CAST(sales_amount AS FLOAT) / NULLIF(quantity, 0)),1) AS avg_selling_price
FROM base_query

GROUP BY
    product_key,
    product_name,
    category,
    subcategory,
    cost
)

/*---------------------------------------------------------------------------
  3) Final Query: Combines all product results into one output
---------------------------------------------------------------------------*/
SELECT 
	product_key,
	product_name,
	category,
	subcategory,
	cost,
	last_sale_date,
	DATEDIFF(MONTH, last_sale_date, GETDATE()) AS recency_in_months,
	CASE
		WHEN total_sales > 50000 THEN 'High-Performer'
		WHEN total_sales >= 10000 THEN 'Mid-Range'
		ELSE 'Low-Performer'
	END AS product_segment,
	lifespan,
	total_orders,
	total_sales,
	total_quantity,
	total_customers,
	avg_selling_price,
	-- Average Order Revenue (AOR)
	CASE 
		WHEN total_orders = 0 THEN 0
		ELSE total_sales / total_orders
	END AS avg_order_revenue,

	-- Average Monthly Revenue
	CASE
		WHEN lifespan = 0 THEN total_sales
		ELSE total_sales / lifespan
	END AS avg_monthly_revenue

FROM product_aggregations 


