-- CHANGES-OVER-TIME ANALYSIS "Trends"
-- Analyze how a measure evolves over time.
-- Helps track trends and identify seasonality in your data.
-- AGGREGATE_FUNCTION [Measure] BY [Date Dimension]

-- Analyze sales perforance over time
SELECT 
	order_date,
	SUM(sales_amount) AS total_sales
FROM gold.fact_sales
WHERE order_date IS NOT NULL
GROUP BY order_date
ORDER BY order_date

-- We usually don't order by days, it's better to go by months or years
SELECT 
	YEAR(order_date) AS order_year,
	SUM(sales_amount) AS total_sales,
	COUNT(DISTINCT customer_key) AS total_customers,
	SUM(quantity) AS total_quantity
FROM gold.fact_sales
WHERE order_date IS NOT NULL
GROUP BY YEAR(order_date)
ORDER BY YEAR(order_date)

-- Try by month as well
SELECT 
	MONTH(order_date) AS order_month,
	SUM(sales_amount) AS total_sales,
	COUNT(DISTINCT customer_key) AS total_customers,
	SUM(quantity) AS total_quantity
FROM gold.fact_sales
WHERE order_date IS NOT NULL
GROUP BY MONTH(order_date)
ORDER BY MONTH(order_date) -- This shows sales per month in general, not per month per year

-- Try by specific months
SELECT 
	DATETRUNC(month, order_date) AS order_date,
	SUM(sales_amount) AS total_sales,
	COUNT(DISTINCT customer_key) AS total_customers,
	SUM(quantity) AS total_quantity
FROM gold.fact_sales
WHERE order_date IS NOT NULL
GROUP BY DATETRUNC(month, order_date)
ORDER BY DATETRUNC(month, order_date)

-- Try another format
SELECT 
	FORMAT(order_date, 'yyyy-MMM') AS order_date,
	SUM(sales_amount) AS total_sales,
	COUNT(DISTINCT customer_key) AS total_customers,
	SUM(quantity) AS total_quantity
FROM gold.fact_sales
WHERE order_date IS NOT NULL
GROUP BY FORMAT(order_date, 'yyyy-MMM')
ORDER BY FORMAT(order_date, 'yyyy-MMM') -- This will be out of order because it will sort the months alphabetically instead of chronologically

-- CUMULATIVE ANALYSIS
-- Aggregate the data progressively over time
-- Helps to understand whether business is growing or declining
-- AGGREGATE_FUNCTION [Cumulative Measure] BY [Date Dimension]

-- Calculate the total sales per month
-- and the running total of sales over time
SELECT
	order_date,
	total_sales,
	-- window function
	SUM(total_sales) OVER (ORDER BY order_date) AS running_total_sales
FROM (
	SELECT
		DATETRUNC(month, order_date) AS order_date,
		SUM(sales_amount) AS total_sales
	FROM gold.fact_sales
	WHERE order_date IS NOT NULL
	GROUP BY DATETRUNC(month, order_date))t
-- Limit the running total for each year
-- Essentially, partition the data by year
SELECT
	order_date,
	total_sales,
	SUM(total_sales) OVER (ORDER BY order_date) AS running_total_sales
FROM (
	SELECT
		DATETRUNC(year, order_date) AS order_date,
		SUM(sales_amount) AS total_sales
	FROM gold.fact_sales
	WHERE order_date IS NOT NULL
	GROUP BY DATETRUNC(year, order_date))t

-- Get the moving average of the price
SELECT
	order_date,
	total_sales,
	SUM(total_sales) OVER (ORDER BY order_date) AS running_total_sales,
	AVG(avg_price) OVER (ORDER BY order_date) AS moving_average_price
FROM (
	SELECT
		DATETRUNC(year, order_date) AS order_date,
		SUM(sales_amount) AS total_sales,
		AVG(price) AS avg_price
	FROM gold.fact_sales
	WHERE order_date IS NOT NULL
	GROUP BY DATETRUNC(year, order_date))t

-- PERFORMANCE ANALYSIS
-- Comparing the current value to a target value.
-- Helps measure success and compare performance.
-- Current [Measure] - Target [Measure]

-- Analyze the yearly performance of products by comparing each product's sales to both its average sales performance and the previous year's sales
WITH yearly_product_sales AS (
SELECT 
	YEAR(f.order_date) AS order_year,
	p.product_name,
	SUM(f.sales_amount) AS current_sales
FROM gold.fact_sales f
LEFT JOIN gold.dim_products p
ON f.product_key = p.product_key
WHERE f.order_date IS NOT NULL
GROUP BY YEAR(f.order_date), p.product_name
)
SELECT
	order_year,
	product_name,
	current_sales,
	AVG(current_sales) OVER (PARTITION BY product_name) AS avg_sales,
	current_sales - AVG(current_sales) OVER (PARTITION BY product_name) AS diff_avg,
	CASE WHEN current_sales - AVG(current_sales) OVER (PARTITION BY product_name) > 0 THEN 'Above Avg'
		 WHEN current_sales - AVG(current_sales) OVER (PARTITION BY product_name) < 0 THEN 'Below Avg'
		 ELSE 'Avg'
	END AS avg_change,
	LAG(current_sales) OVER (PARTITION BY product_name ORDER BY order_year) AS py_sales,
	current_sales - LAG(current_sales) OVER (PARTITION BY product_name ORDER BY order_year) AS diff_py,
	CASE WHEN current_sales - LAG(current_sales) OVER (PARTITION BY product_name ORDER BY order_year) > 0 THEN 'Increase'
		 WHEN current_sales - LAG(current_sales) OVER (PARTITION BY product_name ORDER BY order_year) < 0 THEN 'Decrease'
		 ELSE 'No Change'
	END py_change
FROM yearly_product_sales
ORDER BY product_name, order_year

-- PART-TO-WHOLE ANALYSIS
-- Analyze how an individual part is performing compared to the overall, allowing us to understand which category has the greatest impact on the business
-- ([Measure] / Total [Measure]) * 100 By [Dimension]

-- Which categories contribute the most to overall sales?
-- To display aggregations at multiple levels in the result, use window queries
WITH category_sales AS (
SELECT
	category,
	SUM(sales_amount) total_sales
FROM gold.fact_sales f
LEFT JOIN gold.dim_products p
ON p.product_key = f.product_key
GROUP BY category
)
SELECT
	category,
	total_sales,
	SUM(total_sales) OVER () AS overall_sales,
	CONCAT(ROUND((CAST(total_sales AS FLOAT) / (SUM(total_sales) OVER ())) * 100, 2), '%') AS percentage_of_total
FROM category_sales

-- DATA SEGMENTATION
-- Group the data based on a specific range
-- Helps understand the correlation between two measures
-- [Measure] By [Measure]
-- Ex: Total Products by Sales Range or Total Customers By Age Range
-- We use CASE WHEN statements to help with this grouping of ranges

-- Segment products into cost ranges, and count how many products fall into each segment
GO
WITH product_segments AS (
SELECT 
	product_key,
	product_name,
	cost,
	CASE WHEN cost < 100 THEN 'Below $100'
		 WHEN cost BETWEEN 100 AND 500 THEN '$100-$500'
		 WHEN cost BETWEEN 500 AND 1000 THEN '$500-$1000'
		 ELSE 'Above $1000'
	END AS cost_range
FROM gold.dim_products
)
SELECT
	cost_range,
	COUNT(product_key) AS total_products
FROM product_segments
GROUP BY cost_range
ORDER BY total_products DESC

-- Group customers into three segments based on spending behavior:
-- VIP: >12 months of history, more than 5,000 dollars spent
-- Regular: >12 months, spending 5,000 or less
-- New: <12 months of history
-- And find the total number of customers by group

GO
WITH customer_spending AS (
SELECT
	c.customer_key,
	SUM(f.sales_amount) AS total_spending,
	MIN(order_date) AS first_order,
	MAX(order_date) AS last_order,
	DATEDIFF(month, MIN(order_date), MAX(order_date)) AS lifespan
FROM gold.fact_sales f
LEFT JOIN gold.dim_customers c
ON f.customer_key = c.customer_key
GROUP BY c.customer_key
)
SELECT
	customer_segment,
	COUNT(customer_key) AS total_customers
FROM (
	SELECT
		customer_key,
		CASE WHEN lifespan >= 12 AND total_spending > 5000 THEN 'VIP'
			 WHEN lifespan >= 12 AND total_spending <= 5000 THEN 'Regular'
			 ELSE 'New'
		END AS customer_segment
	FROM customer_spending
)t
GROUP BY customer_segment
ORDER BY total_customers DESC
