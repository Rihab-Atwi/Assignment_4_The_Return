-- Identify customers who have never rented films but have made payments.
SELECT 
	se_customer.customer_id, 
	se_customer.first_name, 
	se_customer.last_name, 
	se_customer.email
FROM public.customer AS se_customer
LEFT OUTER JOIN public.rental AS se_rental
	ON se_customer.customer_id =  se_rental.customer_id
WHERE se_rental.rental_id IS NULL

-- Determine the average number of films rented per customer, broken down by city.
WITH CUSTOMER_RENTALS AS (
    SELECT 
		se_customer.customer_id, 
		COUNT(se_rental.rental_id) AS num_rentals
    FROM public.customer AS se_customer
    LEFT OUTER JOIN public.rental AS se_rental 
		ON  se_customer.customer_id = se_rental.customer_id
    GROUP BY 
		se_customer.customer_id
)

SELECT 
	se_city.city,
	AVG(se_customer_rentals.num_rentals) AS avg_films_rented_per_customer
FROM CUSTOMER_RENTALS AS se_customer_rentals
INNER JOIN public.customer AS se_customer  
	ON se_customer_rentals.customer_id = se_customer.customer_id
INNER JOIN public.address AS se_address 
	ON se_customer.address_id = se_address.address_id
INNER JOIN public.city AS se_city 
	ON se_address.city_id = se_city.city_id
GROUP BY 
	se_city.city
ORDER BY 
	avg_films_rented_per_customer DESC;

-- Identify films that have been rented more than the average number of times and are currently not in inventory.
WITH FILM_RENTAL_COUNTS AS (
	SELECT
		se_film.film_id,
        COUNT(se_rental.rental_id) AS rental_count
    FROM public.film AS se_film
    LEFT OUTER JOIN public.inventory AS se_inventory 
		ON se_film.film_id = se_inventory.film_id
    LEFT OUTER JOIN public.rental AS se_rental 
		ON se_inventory.inventory_id = se_rental.inventory_id
    GROUP BY
        se_film.film_id
),
AVERAGE_RENTAL_COUNT AS (
    SELECT
        AVG(rental_count) AS avg_rental_count
    FROM FILM_RENTAL_COUNTS
)
SELECT
    se_film.film_id,
    se_film.title,
    FILM_RENTAL_COUNTS.rental_count
FROM public.film AS se_film
INNER JOIN FILM_RENTAL_COUNTS 
	ON se_film.film_id = FILM_RENTAL_COUNTS.film_id
INNER JOIN AVERAGE_RENTAL_COUNT 
	ON FILM_RENTAL_COUNTS.rental_count > AVERAGE_RENTAL_COUNT.avg_rental_count
WHERE
    se_film.film_id NOT IN (
        SELECT
            DISTINCT se_inventory.film_id
        FROM
            public.inventory AS se_inventory
    );

-- Calculate the replacement cost of lost films for each store, considering the rental history.
SELECT
    se_store.store_id AS store_id,
    COUNT(DISTINCT se_rental.rental_id) AS total_rentals,
    SUM(se_film.replacement_cost) AS total_replacement_cost
FROM public.store AS se_store
INNER JOIN public.inventory AS se_inventory 
	ON se_store.store_id = se_inventory.store_id
INNER JOIN public.rental AS se_rental 
	ON se_inventory.inventory_id = se_rental.inventory_id
INNER JOIN public.film AS se_film 
	ON se_inventory.film_id = se_film.film_id
WHERE
    se_rental.return_date IS NULL 
GROUP BY
    se_store.store_id
ORDER BY
    se_store.store_id;

-- Create a report that shows the top 5 most rented films in each category, 
-- along with their corresponding rental counts and revenue.
WITH CATEGORY_RANK AS (
    SELECT
        se_film_category.category_id,
        se_film.film_id,
        se_film.title AS film_title,
        COUNT(se_rental.rental_id) AS rental_count,
        SUM(se_payment .amount) AS total_revenue,
        ROW_NUMBER() OVER (PARTITION BY se_film_category.category_id 
						   ORDER BY COUNT(se_rental.rental_id) DESC) AS category_rank
    FROM public.film_category AS se_film_category
    INNER JOIN public.film AS se_film 
		ON se_film_category.film_id = se_film.film_id
    INNER JOIN public.inventory AS se_inventory 
		ON se_film.film_id = se_inventory.film_id
    INNER JOIN public.rental AS se_rental 
		ON se_inventory.inventory_id = se_rental.inventory_id
    INNER JOIN public.payment AS se_payment 
		ON se_rental.rental_id = se_payment.rental_id
    GROUP BY
        se_film_category.category_id,
        se_film.film_id,
        se_film.title
)
SELECT
	se_category_rank.category_id,
	se_category.name AS category_name,
	se_category_rank.film_id,
	se_category_rank.film_title,
	se_category_rank.rental_count,
	se_category_rank.total_revenue
FROM CATEGORY_RANK AS se_category_rank
INNER JOIN public.category se_category 
	ON se_category_rank.category_id = se_category.category_id
WHERE
	se_category_rank.category_rank <= 5
ORDER BY
	se_category_rank.category_id,
	se_category_rank.category_rank;

-- Identify stores where the revenue from film rentals exceeds the revenue from payments for all customers.
WITH RENTAL_REVENUE AS (
    SELECT
		se_inventory.store_id,
        SUM(se_payment.amount) AS rental_revenue
    FROM public.rental AS se_rental
    INNER JOIN public.payment AS se_payment 
		ON se_rental.rental_id = se_payment.rental_id
    INNER JOIN public.inventory se_inventory 
		ON se_rental.inventory_id = se_inventory.inventory_id
    GROUP BY
        se_inventory.store_id
),
PAYMENT_REVENUE AS (
    SELECT
        se_store.store_id,
        SUM(se_payment.amount) AS payment_amount
    FROM public.payment AS se_payment
    INNER JOIN public.customer AS se_customer 
		ON se_payment.customer_id = se_customer.customer_id
    INNER JOIN public.store AS se_store 
		ON se_customer.store_id = se_store.store_id
    GROUP BY
        se_store.store_id
)
SELECT
    se_store.store_id,
    se_rental_revenue.rental_revenue AS total_rental_revenue,
    se_payment_revenue.payment_amount AS total_payment_amount
FROM public.store AS se_store
INNER JOIN RENTAL_REVENUE AS se_rental_revenue
	ON se_store.store_id = se_rental_revenue.store_id
INNER JOIN PAYMENT_REVENUE AS se_payment_revenue 
	ON se_store.store_id = se_payment_revenue.store_id
WHERE
    se_rental_revenue.rental_revenue > se_payment_revenue.payment_amount
ORDER BY
    se_store.store_id;

-- Determine the average rental duration and total revenue for each store.
SELECT
    se_store.store_id,
    AVG(se_film.rental_duration) AS average_rental_duration,
    SUM(se_payment.amount) AS total_revenue
FROM public.store AS se_store
INNER JOIN public.inventory AS se_inventory 
    ON se_store.store_id = se_inventory.store_id
INNER JOIN public.film AS se_film 
    ON se_inventory.film_id = se_film.film_id
INNER JOIN public.rental AS se_rental 
    ON se_inventory.inventory_id = se_rental.inventory_id
INNER JOIN public.payment AS se_payment 
    ON se_rental.rental_id = se_payment.rental_id
GROUP BY
    se_store.store_id
ORDER BY
    se_store.store_id;

-- Analyze the seasonal variation in rental activity and payments for each store.
WITH MonthlyData AS (
    SELECT
        se_store.store_id,
        EXTRACT(YEAR FROM se_rental.rental_date) AS rental_year,
        EXTRACT(MONTH FROM se_rental.rental_date) AS rental_month,
        COUNT(se_rental.rental_id) AS rental_count,
        SUM(se_payment.amount) AS payment_amount
    FROM public.store AS se_store
    INNER JOIN public.inventory AS se_inventory 
		ON se_store.store_id = se_inventory.store_id
    INNER JOIN rental AS se_rental 
		ON se_inventory.inventory_id = se_rental.inventory_id
    INNER JOIN payment AS se_payment 
		ON se_rental.rental_id = se_payment.rental_id
    GROUP BY
        se_store.store_id, 
		rental_year, 
		rental_month
)
SELECT
    se_store.store_id,
    se_monthly_data.rental_year,
    se_monthly_data.rental_month,
    AVG(rental_count) AS avg_rental_count,
    AVG(payment_amount) AS avg_payment_amount
FROM public.store AS se_store
INNER JOIN MonthlyData AS se_monthly_data
	ON se_store.store_id = se_monthly_data.store_id
GROUP BY
    se_store.store_id, 
	rental_year, 
	rental_month
ORDER BY
    se_store.store_id, 
	rental_year, 
	rental_month;








