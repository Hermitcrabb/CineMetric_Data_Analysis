-- Creating dimentiontables
CREATE TABLE movies (
    movie_id          NUMBER(10) CONSTRAINT pk_movies PRIMARY KEY,
    title             VARCHAR2(500),
    original_title    VARCHAR2(500),
    original_language VARCHAR2(20),
    status            VARCHAR2(50),

    budget            NUMBER(15,2),
    revenue           NUMBER(15,2),
    runtime           NUMBER(6,2),
    popularity        NUMBER(12,4),
    vote_average      NUMBER(4,2),
    vote_count        NUMBER(12),

    release_date      TIMESTAMP
);

-- unique genres
CREATE TABLE genres (
    genre_id    NUMBER(10) CONSTRAINT pk_genres PRIMARY KEY,
    genre_name  VARCHAR2(100) NOT NULL,
    CONSTRAINT uq_genres_name UNIQUE (genre_name)
);


CREATE TABLE movie_genres (
    movie_id  NUMBER(10),
    genre_id  NUMBER(10),

    CONSTRAINT pk_movie_genres
        PRIMARY KEY (movie_id, genre_id),

    CONSTRAINT fk_movie_genres_movie
        FOREIGN KEY (movie_id)
        REFERENCES movies(movie_id),

    CONSTRAINT fk_movie_genres_genre
        FOREIGN KEY (genre_id)
        REFERENCES genres(genre_id)
);


-- Load movies into the table

MERGE INTO movies m
USING (
    SELECT
        id,
        title,
        original_title,
        original_language,
        status,
        budget,
        revenue,
        runtime,
        popularity,
        vote_average,
        vote_count,
        release_date
    FROM tmdb_5000_movies
) r
ON (m.movie_id = r.id)

WHEN MATCHED THEN
    UPDATE SET
        m.title = r.title,
        m.original_title = r.original_title,
        m.original_language = r.original_language,
        m.status = r.status,
        m.budget = r.budget,
        m.revenue = r.revenue,
        m.runtime = r.runtime,
        m.popularity = r.popularity,
        m.vote_average = r.vote_average,
        m.vote_count = r.vote_count,
        m.release_date = r.release_date

WHEN NOT MATCHED THEN
    INSERT (
        movie_id,
        title,
        original_title,
        original_language,
        status,
        budget,
        revenue,
        runtime,
        popularity,
        vote_average,
        vote_count,
        release_date
    )
    VALUES (
        r.id,
        r.title,
        r.original_title,
        r.original_language,
        r.status,
        r.budget,
        r.revenue,
        r.runtime,
        r.popularity,
        r.vote_average,
        r.vote_count,
        r.release_date
    );

-- extracting json and storing the unique json.
INSERT INTO genres (genre_id, genre_name)
SELECT DISTINCT
    j.genre_id,
    j.genre_name
FROM tmdb_5000_movies t,
     JSON_TABLE(
         t.genres,
         '$[*]'
         COLUMNS (
             genre_id   NUMBER(10)  PATH '$.id',
             genre_name VARCHAR2(100) PATH '$.name'
         )
     ) j
WHERE j.genre_id IS NOT NULL
  AND j.genre_name IS NOT NULL;

-- load into movie_genres 
INSERT INTO movie_genres (movie_id, genre_id)
SELECT DISTINCT
    t.id AS movie_id,
    j.genre_id
FROM tmdb_5000_movies t,
     JSON_TABLE(
         t.genres,
         '$[*]'
         COLUMNS (
             genre_id NUMBER(10) PATH '$.id'
         )
     ) j
WHERE j.genre_id IS NOT NULL;

COMMIT;


-- Analysis begins
-- Movie Profitilbity of top 10 movies
SELECT
    title,
    budget,
    revenue,
    revenue - budget AS profit
FROM movies
WHERE budget > 0
ORDER BY profit DESC
FETCH FIRST 10 ROWS ONLY;

-- Return On Investment of top 10 movies

SELECT
    title,
    budget,
    revenue,
    ROUND((revenue - budget) / NULLIF(budget, 0) * 100, 2) AS roi_percentage
FROM movies
WHERE budget > 0
ORDER BY roi_percentage DESC
FETCH FIRST 10 ROWS ONLY;

-- Genre performance
SELECT
    g.genre_name,
    COUNT(*) AS movie_count,
    ROUND(AVG(m.vote_average), 2) AS avg_rating,
    ROUND(AVG(m.popularity), 2) AS avg_popularity,
    ROUND(AVG(m.revenue), 2) AS avg_revenue
FROM movies m
JOIN movie_genres mg
    ON m.movie_id = mg.movie_id
JOIN genres g
    ON mg.genre_id = g.genre_id
GROUP BY g.genre_name
ORDER BY avg_popularity DESC;

-- Top 10 Highest-rated movies
SELECT
    title,
    vote_average,
    vote_count
FROM movies
WHERE vote_count > 2000
ORDER BY vote_average DESC
FETCH FIRST 10 ROWS ONLY;

-- Dataset average budget,rating,popularity and first movie to last added
SELECT
    COUNT(*) AS total_movies,
    MIN(release_date) AS earliest_release,
    MAX(release_date) AS latest_release,
    ROUND(AVG(budget), 2) AS avg_budget,
    ROUND(AVG(revenue), 2) AS avg_revenue,
    ROUND(AVG(vote_average), 2) AS avg_rating,
    ROUND(AVG(popularity), 2) AS avg_popularity
FROM movies;

-- Finding total movies with revenue and financial data
SELECT
    COUNT(*) AS movies_with_budget,
    COUNT(CASE WHEN revenue > 0 THEN 1 END) AS movies_with_revenue,
    COUNT(CASE WHEN budget > 0 AND revenue > 0 THEN 1 END) AS movies_with_financial_data
FROM movies;

-- View for movie financials
CREATE OR REPLACE VIEW vw_movie_financials AS
SELECT
    movie_id,
    title,
    release_date,
    budget,
    revenue,
    revenue - budget AS profit,
    ROUND(
        (revenue - budget) / NULLIF(budget, 0) * 100,
        2
    ) AS roi_percentage
FROM movies
WHERE budget > 0
  AND revenue > 0;


-- view table with financials
SELECT *
FROM vw_movie_financials
ORDER BY profit DESC
FETCH FIRST 10 ROWS ONLY;

-- view table based on roi percentage.
SELECT *
FROM vw_movie_financials
ORDER BY roi_percentage DESC
FETCH FIRST 10 ROWS ONLY;


-- Median distributin
SELECT
    ROUND(MIN(budget), 2) AS min_budget,
    ROUND(PERCENTILE_CONT(0.25)
        WITHIN GROUP (ORDER BY budget), 2) AS p25_budget,
    ROUND(PERCENTILE_CONT(0.50)
        WITHIN GROUP (ORDER BY budget), 2) AS median_budget,
    ROUND(PERCENTILE_CONT(0.75)
        WITHIN GROUP (ORDER BY budget), 2) AS p75_budget,
    ROUND(MAX(budget), 2) AS max_budget
FROM movies
WHERE budget > 0;


-- Distinguish movies on the basis of their budget

SELECT
    CASE
        WHEN budget <= 8000000 THEN 'Low'
        WHEN budget <= 23000000 THEN 'Mid-Low'
        WHEN budget <= 50000000 THEN 'Mid-High'
        ELSE 'High'
    END AS budget_category,

    COUNT(*) AS movie_count,

    ROUND(AVG(budget), 2) AS avg_budget,
    ROUND(AVG(revenue), 2) AS avg_revenue,
    ROUND(AVG(revenue - budget), 2) AS avg_profit,

    ROUND(
        AVG(
            (revenue - budget) /
            NULLIF(budget, 0) * 100
        ),
        2
    ) AS avg_roi,

    ROUND(AVG(vote_average), 2) AS avg_rating,
    ROUND(AVG(popularity), 2) AS avg_popularity

FROM movies
WHERE budget > 0
  AND revenue > 0

GROUP BY
    CASE
        WHEN budget <= 8000000 THEN 'Low'
        WHEN budget <= 23000000 THEN 'Mid-Low'
        WHEN budget <= 50000000 THEN 'Mid-High'
        ELSE 'High'
    END

ORDER BY MIN(budget);


-- Genre based performance data

SELECT
    g.genre_name,
    COUNT(*) AS movie_count,
    ROUND(AVG(m.revenue), 2) AS avg_revenue,
    ROUND(AVG(m.revenue - m.budget), 2) AS avg_profit,
    ROUND(AVG(m.vote_average), 2) AS avg_rating,
    ROUND(AVG(m.popularity), 2) AS avg_popularity
FROM movies m
JOIN movie_genres mg
    ON m.movie_id = mg.movie_id
JOIN genres g
    ON mg.genre_id = g.genre_id
WHERE m.revenue > 0
GROUP BY g.genre_name
ORDER BY avg_revenue DESC;



SELECT
    EXTRACT(YEAR FROM m.release_date) AS release_year,
    g.genre_name,
    COUNT(*) AS movie_count,
    ROUND(AVG(m.revenue), 2) AS avg_revenue,
    ROUND(AVG(m.revenue - m.budget), 2) AS avg_profit,
    ROUND(AVG(m.vote_average), 2) AS avg_rating,
    ROUND(AVG(m.popularity), 2) AS avg_popularity
FROM movies m
JOIN movie_genres mg
    ON m.movie_id = mg.movie_id
JOIN genres g
    ON mg.genre_id = g.genre_id
WHERE m.budget > 0
  AND m.revenue > 0
  AND m.release_date IS NOT NULL
GROUP BY
    EXTRACT(YEAR FROM m.release_date),
    g.genre_name
ORDER BY
    release_year,
    avg_revenue DESC;


-- Decade based anaylsis
SELECT
    decade,
    genre_name,
    movie_count,
    avg_revenue,
    avg_profit,
    avg_rating,
    avg_popularity
FROM (
    SELECT
        FLOOR(EXTRACT(YEAR FROM m.release_date) / 10) * 10 AS decade,
        g.genre_name,
        COUNT(*) AS movie_count,
        ROUND(AVG(m.revenue), 2) AS avg_revenue,
        ROUND(AVG(m.revenue - m.budget), 2) AS avg_profit,
        ROUND(AVG(m.vote_average), 2) AS avg_rating,
        ROUND(AVG(m.popularity), 2) AS avg_popularity,
        ROW_NUMBER() OVER (
            PARTITION BY FLOOR(EXTRACT(YEAR FROM m.release_date) / 10) * 10
            ORDER BY AVG(m.revenue) DESC
        ) AS rn
    FROM movies m
    JOIN movie_genres mg
        ON m.movie_id = mg.movie_id
    JOIN genres g
        ON mg.genre_id = g.genre_id
    WHERE m.budget > 0
      AND m.revenue > 0
      AND m.release_date IS NOT NULL
    GROUP BY
        FLOOR(EXTRACT(YEAR FROM m.release_date) / 10) * 10,
        g.genre_name
    HAVING COUNT(*) >= 20
)
WHERE rn <= 3
ORDER BY decade, avg_revenue DESC;



SELECT
    g.genre_name,
    COUNT(*) AS movie_count,
    ROUND(AVG(m.budget), 2) AS avg_budget,
    ROUND(AVG(m.revenue), 2) AS avg_revenue,
    ROUND(AVG(m.revenue - m.budget), 2) AS avg_profit,
    ROUND(
        AVG(
            (m.revenue - m.budget) /
            NULLIF(m.budget, 0) * 100
        ),
        2
    ) AS avg_roi,
    ROUND(AVG(m.popularity), 2) AS avg_popularity,
    ROUND(AVG(m.vote_average), 2) AS avg_rating
FROM movies m
JOIN movie_genres mg
    ON m.movie_id = mg.movie_id
JOIN genres g
    ON mg.genre_id = g.genre_id
WHERE m.budget > 0
  AND m.revenue > 0
GROUP BY g.genre_name
HAVING COUNT(*) >= 20
ORDER BY avg_profit DESC;


-- Popularity based analysis
SELECT
    CASE
        WHEN popularity < 10 THEN 'Low'
        WHEN popularity < 25 THEN 'Medium'
        WHEN popularity < 50 THEN 'High'
        ELSE 'Very High'
    END AS popularity_category,
    COUNT(*) AS movie_count,
    ROUND(AVG(budget), 2) AS avg_budget,
    ROUND(AVG(revenue), 2) AS avg_revenue,
    ROUND(AVG(revenue - budget), 2) AS avg_profit,
    ROUND(AVG(vote_average), 2) AS avg_rating
FROM movies
WHERE budget > 0
  AND revenue > 0
GROUP BY
    CASE
        WHEN popularity < 10 THEN 'Low'
        WHEN popularity < 25 THEN 'Medium'
        WHEN popularity < 50 THEN 'High'
        ELSE 'Very High'
    END
ORDER BY MIN(popularity);



-- Financially profitable movies
SELECT
    g.genre_name,
    COUNT(*) AS movie_count,

    COUNT(
        CASE
            WHEN m.revenue > m.budget THEN 1
        END
    ) AS profitable_movies,

    ROUND(
        COUNT(
            CASE
                WHEN m.revenue > m.budget THEN 1
            END
        ) * 100 / COUNT(*),
        2
    ) AS profitability_rate,

    ROUND(AVG(m.revenue), 2) AS avg_revenue,
    ROUND(AVG(m.revenue - m.budget), 2) AS avg_profit

FROM movies m
JOIN movie_genres mg
    ON m.movie_id = mg.movie_id
JOIN genres g
    ON mg.genre_id = g.genre_id

WHERE m.budget > 0
  AND m.revenue > 0

GROUP BY g.genre_name

HAVING COUNT(*) >= 20

ORDER BY profitability_rate DESC;



-- Release month analysis
SELECT
    EXTRACT(MONTH FROM release_date) AS release_month,
    COUNT(*) AS movie_count,
    ROUND(AVG(budget), 2) AS avg_budget,
    ROUND(AVG(revenue), 2) AS avg_revenue,
    ROUND(AVG(revenue - budget), 2) AS avg_profit,
    ROUND(AVG(popularity), 2) AS avg_popularity,
    ROUND(AVG(vote_average), 2) AS avg_rating,

    ROUND(
        COUNT(
            CASE
                WHEN revenue > budget THEN 1
            END
        ) * 100 / COUNT(*),
        2
    ) AS profitability_rate

FROM movies

WHERE budget > 0
  AND revenue > 0
  AND release_date IS NOT NULL
GROUP BY EXTRACT(MONTH FROM release_date)
ORDER BY release_month;



CREATE OR REPLACE FUNCTION get_movie_profit (
    p_movie_id IN NUMBER
)
RETURN NUMBER
IS
    v_profit NUMBER;
BEGIN
    SELECT revenue - budget
    INTO v_profit
    FROM movies
    WHERE movie_id = p_movie_id;

    RETURN v_profit;

EXCEPTION
    WHEN NO_DATA_FOUND THEN
        RETURN NULL;
END;
/

SELECT
    movie_id,
    title,
    get_movie_profit(movie_id) AS profit
FROM movies
WHERE title = 'Avatar';



CREATE OR REPLACE FUNCTION get_movie_roi (
    p_movie_id IN NUMBER
)
RETURN NUMBER
IS
    v_roi NUMBER;
BEGIN
    SELECT
        ROUND(
            (revenue - budget) / NULLIF(budget, 0) * 100,
            2
        )
    INTO v_roi
    FROM movies
    WHERE movie_id = p_movie_id;

    RETURN v_roi;

EXCEPTION
    WHEN NO_DATA_FOUND THEN
        RETURN NULL;
END;
/

SELECT
    movie_id,
    title,
    get_movie_roi(movie_id) AS roi_percentage
FROM movies
WHERE title = 'Avatar';

-- ------------------------------------------------
-- -----------------------------------------------
-- Movie performance based on revenue, popularity and rating-----
CREATE OR REPLACE FUNCTION get_movie_performance (
    p_movie_id IN NUMBER
)
RETURN VARCHAR2
IS
    v_revenue   NUMBER;
    v_budget    NUMBER;
    v_popularity NUMBER;
    v_rating    NUMBER;
BEGIN
    SELECT
        revenue,
        budget,
        popularity,
        vote_average
    INTO
        v_revenue,
        v_budget,
        v_popularity,
        v_rating
    FROM movies
    WHERE movie_id = p_movie_id;

    IF v_revenue > v_budget
       AND v_popularity >= 50
       AND v_rating >= 8
    THEN
        RETURN 'High Performing';

    ELSIF v_revenue > v_budget
          AND v_popularity >= 25
          AND v_rating >= 6
    THEN
        RETURN 'Good Performing';

    ELSIF v_revenue > v_budget
    THEN
        RETURN 'Profitable';

    ELSE
        RETURN 'Low Performing';
    END IF;

EXCEPTION
    WHEN NO_DATA_FOUND THEN
        RETURN 'Movie Not Found';
END;
/



-- Monthly based analysis
CREATE OR REPLACE PROCEDURE generate_monthly_analysis (
    p_year  IN NUMBER,
    p_month IN NUMBER
)
IS
    v_movie_count    NUMBER;
    v_avg_budget     movies.budget%TYPE;
    v_avg_revenue    movies.revenue%TYPE;
    v_avg_profit     NUMBER;
    v_avg_popularity movies.popularity%TYPE;
    v_avg_rating     movies.vote_average%TYPE;
    v_profitability  NUMBER;
BEGIN

    SELECT
        COUNT(*),
        ROUND(AVG(budget), 2),
        ROUND(AVG(revenue), 2),
        ROUND(AVG(revenue - budget), 2),
        ROUND(AVG(popularity), 2),
        ROUND(AVG(vote_average), 2),
        ROUND(
            COUNT(
                CASE
                    WHEN revenue > budget THEN 1
                END
            ) * 100 / COUNT(*),2
        )
    INTO
        v_movie_count,
        v_avg_budget,
        v_avg_revenue,
        v_avg_profit,
        v_avg_popularity,
        v_avg_rating,
        v_profitability
    FROM movies
    WHERE budget > 0
      AND revenue > 0
      AND release_date IS NOT NULL
      AND EXTRACT(YEAR FROM release_date) = p_year
      AND EXTRACT(MONTH FROM release_date) = p_month;

    DBMS_OUTPUT.PUT_LINE('Monthly Movie Analysis');
    DBMS_OUTPUT.PUT_LINE('----------------------');
    DBMS_OUTPUT.PUT_LINE('Year: ' || p_year);
    DBMS_OUTPUT.PUT_LINE('Month: ' || p_month);
    DBMS_OUTPUT.PUT_LINE('Movie Count: ' || v_movie_count);
    DBMS_OUTPUT.PUT_LINE('Average Budget: ' || v_avg_budget);
    DBMS_OUTPUT.PUT_LINE('Average Revenue: ' || v_avg_revenue);
    DBMS_OUTPUT.PUT_LINE('Average Profit: ' || v_avg_profit);
    DBMS_OUTPUT.PUT_LINE('Average Popularity: ' || v_avg_popularity);
    DBMS_OUTPUT.PUT_LINE('Average Rating: ' || v_avg_rating);
    DBMS_OUTPUT.PUT_LINE('Profitability Rate: ' || v_profitability || '%');

END;
/




-- Bulk movie process to update status
CREATE OR REPLACE PROCEDURE bulk_movie_processing
IS
    TYPE movie_id_table IS TABLE OF movies.movie_id%TYPE;

    v_movie_ids movie_id_table;

    CURSOR movie_cursor IS
        SELECT movie_id
        FROM movies
        WHERE budget > 0
          AND revenue > 0;

    v_total_fetched NUMBER := 0;
    v_total_processed NUMBER := 0;

BEGIN

    OPEN movie_cursor;

    LOOP
        FETCH movie_cursor
        BULK COLLECT INTO v_movie_ids
        LIMIT 500;

        EXIT WHEN v_movie_ids.COUNT = 0;

        v_total_fetched := v_total_fetched + v_movie_ids.COUNT;

        FORALL i IN 1 .. v_movie_ids.COUNT
            UPDATE movies
            SET status = status
            WHERE movie_id = v_movie_ids(i);

        v_total_processed := v_total_processed + SQL%ROWCOUNT;

        DBMS_OUTPUT.PUT_LINE(
            'Batch processed: ' ||
            v_movie_ids.COUNT ||
            ' movies'
        );

    END LOOP;

    CLOSE movie_cursor;

    DBMS_OUTPUT.PUT_LINE('-----------------------------');
    DBMS_OUTPUT.PUT_LINE(
        'Total movies fetched: ' ||
        v_total_fetched
    );
    DBMS_OUTPUT.PUT_LINE(
        'Total rows processed: ' ||
        v_total_processed
    );

END;
/


BEGIN
    bulk_movie_processing;
END;
/


-- View for Genre based performance
CREATE OR REPLACE VIEW vw_genre_performance AS
SELECT
    g.genre_id,
    g.genre_name,
    COUNT(m.movie_id) AS movie_count,
    ROUND(AVG(m.budget), 2) AS avg_budget,
    ROUND(AVG(m.revenue), 2) AS avg_revenue,
    ROUND(AVG(m.revenue - m.budget), 2) AS avg_profit,
    ROUND(AVG(m.vote_average), 2) AS avg_rating,
    ROUND(AVG(m.popularity), 2) AS avg_popularity,
    ROUND(
        COUNT(
            CASE
                WHEN m.revenue > m.budget THEN 1
            END
        ) * 100 / COUNT(*),2
    ) AS profitability_rate
FROM genres g
JOIN movie_genres mg
    ON g.genre_id = mg.genre_id
JOIN movies m
    ON mg.movie_id = m.movie_id
WHERE m.budget > 0
  AND m.revenue > 0
GROUP BY
    g.genre_id,S
    g.genre_name;


SELECT *
FROM vw_genre_performance
ORDER BY avg_profit DESC;


SELECT
    movie_id,
    COUNT(*) AS duplicate_count
FROM movies
GROUP BY movie_id
HAVING COUNT(*) > 1;


SELECT
    COUNT(*) AS total_movies,
    COUNT(title) AS movies_with_title,
    COUNT(release_date) AS movies_with_release_date,
    COUNT(*) - COUNT(title) AS missing_titles,
    COUNT(*) - COUNT(release_date) AS missing_release_dates
FROM movies;


SELECT
    movie_id,
    title,
    original_title,
    status,
    budget,
    revenue
FROM movies
WHERE release_date IS NULL;


SELECT
    movie_id,
    title,
    vote_average,
    vote_count,
    budget,
    revenue
FROM movies
WHERE vote_count <= 1
  AND budget = 0
  AND revenue = 0
FETCH FIRST 20 ROWS ONLY;


DELETE FROM movie_genres
WHERE movie_id IN (
    SELECT movie_id
    FROM movies
    WHERE vote_count <= 1
      AND budget = 0
      AND revenue = 0
);

COMMIT;

DELETE FROM movies
WHERE vote_count <= 1
  AND budget = 0
  AND revenue = 0;

COMMIT;


SELECT
    COUNT(*) AS total_movies,
    COUNT(CASE WHEN budget = 0 THEN 1 END) AS zero_budget,
    COUNT(CASE WHEN revenue = 0 THEN 1 END) AS zero_revenue,
    COUNT(CASE WHEN budget > 0 AND revenue > 0 THEN 1 END) AS complete_financial_data
FROM movies;



SELECT
    MIN(vote_average) AS min_rating,
    MAX(vote_average) AS max_rating,
    MIN(vote_count) AS min_vote_count,
    MAX(vote_count) AS max_vote_count,
    COUNT(CASE WHEN vote_count = 0 THEN 1 END) AS zero_vote_movies
FROM movies;


SELECT
    movie_id,
    title,
    vote_average,
    vote_count,
    budget,
    revenue
FROM movies
WHERE vote_count = 0
ORDER BY budget DESC;

DELETE FROM movie_genres
WHERE movie_id IN (
    SELECT movie_id
    FROM movies
    WHERE vote_count = 0
);

commit;

DELETE FROM movies
WHERE vote_count = 0;

COMMIT;

SELECT
    id,
    COUNT(*) AS record_count
FROM tmdb_5000_movies
GROUP BY id
HAVING COUNT(*) > 1;


SELECT
    movie_id,
    title,
    original_title,
    status,
    release_date
FROM movies
WHERE release_date IS NULL;


-- procedure total movies analysis in the provided year

CREATE OR REPLACE PROCEDURE analyze_movie_year (
    p_year IN NUMBER
)
IS
    v_movie_count    NUMBER;
    v_avg_budget     movies.budget%TYPE;
    v_avg_revenue    movies.revenue%TYPE;
    v_avg_profit     NUMBER;
    v_avg_popularity movies.popularity%TYPE;
    v_avg_rating     movies.vote_average%TYPE;
    v_profitability  NUMBER;
BEGIN

    SELECT
        COUNT(*),
        ROUND(AVG(budget), 2),
        ROUND(AVG(revenue), 2),
        ROUND(AVG(revenue - budget), 2),
        ROUND(AVG(popularity), 2),
        ROUND(AVG(vote_average), 2),
        ROUND(
            COUNT(
                CASE
                    WHEN revenue > budget THEN 1
                END
            ) * 100 / COUNT(*),2
        )
    INTO
        v_movie_count,
        v_avg_budget,
        v_avg_revenue,
        v_avg_profit,
        v_avg_popularity,
        v_avg_rating,
        v_profitability
    FROM movies
    WHERE release_date IS NOT NULL
      AND budget > 0
      AND revenue > 0
      AND EXTRACT(YEAR FROM release_date) = p_year;

    DBMS_OUTPUT.PUT_LINE('Movie Year Analysis');
    DBMS_OUTPUT.PUT_LINE('-------------------');
    DBMS_OUTPUT.PUT_LINE('Year: ' || p_year);
    DBMS_OUTPUT.PUT_LINE('Movie Count: ' || v_movie_count);
    DBMS_OUTPUT.PUT_LINE('Average Budget: ' || v_avg_budget);
    DBMS_OUTPUT.PUT_LINE('Average Revenue: ' || v_avg_revenue);
    DBMS_OUTPUT.PUT_LINE('Average Profit: ' || v_avg_profit);
    DBMS_OUTPUT.PUT_LINE('Average Popularity: ' || v_avg_popularity);
    DBMS_OUTPUT.PUT_LINE('Average Rating: ' || v_avg_rating);
    DBMS_OUTPUT.PUT_LINE('Profitability Rate: ' || v_profitability || '%');

END;
/

-- Procedure for best genre in the year

CREATE OR REPLACE PROCEDURE p_best_genre_year (
    p_year IN NUMBER
)
IS
    v_genre_name       genres.genre_name%TYPE;
    v_movie_count      NUMBER;
    v_avg_budget       movies.budget%TYPE;
    v_avg_revenue      movies.revenue%TYPE;
    v_avg_profit       NUMBER;
    v_avg_popularity   movies.popularity%TYPE;
    v_avg_rating       movies.vote_average%TYPE;
    v_profitability    NUMBER;
BEGIN

    SELECT
        genre_name,
        movie_count,
        avg_budget,
        avg_revenue,
        avg_profit,
        avg_popularity,
        avg_rating,
        profitability_rate
    INTO
        v_genre_name,
        v_movie_count,
        v_avg_budget,
        v_avg_revenue,
        v_avg_profit,
        v_avg_popularity,
        v_avg_rating,
        v_profitability
    FROM (
        SELECT
            g.genre_name,
            COUNT(m.movie_id) AS movie_count,
            ROUND(AVG(m.budget), 2) AS avg_budget,
            ROUND(AVG(m.revenue), 2) AS avg_revenue,
            ROUND(AVG(m.revenue - m.budget), 2) AS avg_profit,
            ROUND(AVG(m.popularity), 2) AS avg_popularity,
            ROUND(AVG(m.vote_average), 2) AS avg_rating,
            ROUND(
                COUNT(
                    CASE
                        WHEN m.revenue > m.budget THEN 1
                    END
                ) * 100 / COUNT(*),
                2
            ) AS profitability_rate
        FROM genres g
        JOIN movie_genres mg
            ON g.genre_id = mg.genre_id
        JOIN movies m
            ON mg.movie_id = m.movie_id
        WHERE m.release_date IS NOT NULL
          AND m.budget > 0
          AND m.revenue > 0
          AND EXTRACT(YEAR FROM m.release_date) = p_year
        GROUP BY g.genre_name
        ORDER BY AVG(m.revenue - m.budget) DESC
    )
    WHERE ROWNUM = 1;

    DBMS_OUTPUT.PUT_LINE('Best Performing Genre');
    DBMS_OUTPUT.PUT_LINE('---------------------');
    DBMS_OUTPUT.PUT_LINE('Year: ' || p_year);
    DBMS_OUTPUT.PUT_LINE('Genre: ' || v_genre_name);
    DBMS_OUTPUT.PUT_LINE('Movie Count: ' || v_movie_count);
    DBMS_OUTPUT.PUT_LINE('Average Budget: ' || v_avg_budget);
    DBMS_OUTPUT.PUT_LINE('Average Revenue: ' || v_avg_revenue);
    DBMS_OUTPUT.PUT_LINE('Average Profit: ' || v_avg_profit);
    DBMS_OUTPUT.PUT_LINE('Average Popularity: ' || v_avg_popularity);
    DBMS_OUTPUT.PUT_LINE('Average Rating: ' || v_avg_rating);
    DBMS_OUTPUT.PUT_LINE('Profitability Rate: ' || v_profitability || '%');

EXCEPTION
    WHEN NO_DATA_FOUND THEN
        DBMS_OUTPUT.PUT_LINE(
            'No financially complete movies found for ' || p_year || '.'
        );
END;
/


-- procedure for budget performance

CREATE OR REPLACE PROCEDURE analyze_budget_performance (
    p_year IN NUMBER
)
IS
    v_movie_count       NUMBER;
    v_avg_budget        movies.budget%TYPE;
    v_avg_revenue       movies.revenue%TYPE;
    v_avg_profit        NUMBER;
    v_avg_roi           NUMBER;
    v_profitability     NUMBER;

    CURSOR budget_cursor IS
        SELECT
            CASE
                WHEN budget <= p25 THEN 'Low Budget'
                WHEN budget <= median_budget THEN 'Mid-Low Budget'
                WHEN budget <= p75 THEN 'Mid-High Budget'
                ELSE 'High Budget'
            END AS budget_group,
            COUNT(*) AS movie_count,
            ROUND(AVG(budget), 2) AS avg_budget,
            ROUND(AVG(revenue), 2) AS avg_revenue,
            ROUND(AVG(revenue - budget), 2) AS avg_profit,
            ROUND(
                AVG(
                    (revenue - budget) /
                    NULLIF(budget, 0) * 100
                ),
                2
            ) AS avg_roi,
            ROUND(
                COUNT(
                    CASE
                        WHEN revenue > budget THEN 1
                    END
                ) * 100 / COUNT(*),
                2
            ) AS profitability_rate
        FROM (
            SELECT
                m.*,
                PERCENTILE_CONT(0.25)
                    WITHIN GROUP (ORDER BY budget)
                    OVER () AS p25,
                PERCENTILE_CONT(0.50)
                    WITHIN GROUP (ORDER BY budget)
                    OVER () AS median_budget,
                PERCENTILE_CONT(0.75)
                    WITHIN GROUP (ORDER BY budget)
                    OVER () AS p75
            FROM movies m
            WHERE m.release_date IS NOT NULL
              AND m.budget > 0
              AND m.revenue > 0
              AND EXTRACT(YEAR FROM m.release_date) = p_year
        )
        GROUP BY
            CASE
                WHEN budget <= p25 THEN 'Low Budget'
                WHEN budget <= median_budget THEN 'Mid-Low Budget'
                WHEN budget <= p75 THEN 'Mid-High Budget'
                ELSE 'High Budget'
            END
        ORDER BY MIN(budget);

    v_budget_group VARCHAR2(30);
BEGIN

    DBMS_OUTPUT.PUT_LINE('Budget Performance Analysis');
    DBMS_OUTPUT.PUT_LINE('---------------------------');
    DBMS_OUTPUT.PUT_LINE('Year: ' || p_year);
    DBMS_OUTPUT.PUT_LINE('');

    OPEN budget_cursor;

    LOOP
        FETCH budget_cursor INTO
            v_budget_group,
            v_movie_count,
            v_avg_budget,
            v_avg_revenue,
            v_avg_profit,
            v_avg_roi,
            v_profitability;

        EXIT WHEN budget_cursor%NOTFOUND;

        DBMS_OUTPUT.PUT_LINE('Budget Group: ' || v_budget_group);
        DBMS_OUTPUT.PUT_LINE('Movie Count: ' || v_movie_count);
        DBMS_OUTPUT.PUT_LINE('Average Budget: ' || v_avg_budget);
        DBMS_OUTPUT.PUT_LINE('Average Revenue: ' || v_avg_revenue);
        DBMS_OUTPUT.PUT_LINE('Average Profit: ' || v_avg_profit);
        DBMS_OUTPUT.PUT_LINE('Average ROI: ' || v_avg_roi || '%');
        DBMS_OUTPUT.PUT_LINE('Profitability Rate: ' || v_profitability || '%');
        DBMS_OUTPUT.PUT_LINE('');
    END LOOP;

    CLOSE budget_cursor;

EXCEPTION
    WHEN OTHERS THEN
        IF budget_cursor%ISOPEN THEN
            CLOSE budget_cursor;
        END IF;

        RAISE;
END;
/


-- Procedure for popularity 
CREATE OR REPLACE PROCEDURE analyze_popularity_performance (
    p_year IN NUMBER)
IS
    v_popularity_group  VARCHAR2(30);
    v_movie_count       NUMBER;
    v_avg_popularity    movies.popularity%TYPE;
    v_avg_budget        movies.budget%TYPE;
    v_avg_revenue       movies.revenue%TYPE;
    v_avg_profit        NUMBER;
    v_avg_rating        movies.vote_average%TYPE;
    v_profitability     NUMBER;

    CURSOR popularity_cursor IS
        SELECT
            CASE
                WHEN popularity <= p25 THEN 'Low Popularity'
                WHEN popularity <= median_popularity THEN 'Mid-Low Popularity'
                WHEN popularity <= p75 THEN 'Mid-High Popularity'
                ELSE 'High Popularity'
            END AS popularity_group,
            COUNT(*) AS movie_count,
            ROUND(AVG(popularity), 2) AS avg_popularity,
            ROUND(AVG(budget), 2) AS avg_budget,
            ROUND(AVG(revenue), 2) AS avg_revenue,
            ROUND(AVG(revenue - budget), 2) AS avg_profit,
            ROUND(AVG(vote_average), 2) AS avg_rating,
            ROUND(
                COUNT(
                    CASE
                        WHEN revenue > budget THEN 1
                    END
                ) * 100 / COUNT(*),
                2
            ) AS profitability_rate
        FROM (
            SELECT
                m.*,
                PERCENTILE_CONT(0.25)
                    WITHIN GROUP (ORDER BY popularity)
                    OVER () AS p25,
                PERCENTILE_CONT(0.50)
                    WITHIN GROUP (ORDER BY popularity)
                    OVER () AS median_popularity,
                PERCENTILE_CONT(0.75)
                    WITHIN GROUP (ORDER BY popularity)
                    OVER () AS p75
            FROM movies m
            WHERE m.release_date IS NOT NULL
              AND m.vote_count > 0
              AND m.budget > 0
              AND m.revenue > 0
              AND EXTRACT(YEAR FROM m.release_date) = p_year
        )
        GROUP BY
            CASE
                WHEN popularity <= p25 THEN 'Low Popularity'
                WHEN popularity <= median_popularity THEN 'Mid-Low Popularity'
                WHEN popularity <= p75 THEN 'Mid-High Popularity'
                ELSE 'High Popularity'
            END
        ORDER BY MIN(popularity);

BEGIN

    DBMS_OUTPUT.PUT_LINE('Popularity Performance Analysis');
    DBMS_OUTPUT.PUT_LINE('-------------------------------');
    DBMS_OUTPUT.PUT_LINE('Year: ' || p_year);
    DBMS_OUTPUT.PUT_LINE('');

    OPEN popularity_cursor;

    LOOP
        FETCH popularity_cursor INTO
            v_popularity_group,
            v_movie_count,
            v_avg_popularity,
            v_avg_budget,
            v_avg_revenue,
            v_avg_profit,
            v_avg_rating,
            v_profitability;

        EXIT WHEN popularity_cursor%NOTFOUND;

        DBMS_OUTPUT.PUT_LINE('Popularity Group: ' || v_popularity_group);
        DBMS_OUTPUT.PUT_LINE('Movie Count: ' || v_movie_count);
        DBMS_OUTPUT.PUT_LINE('Average Popularity: ' || v_avg_popularity);
        DBMS_OUTPUT.PUT_LINE('Average Budget: ' || v_avg_budget);
        DBMS_OUTPUT.PUT_LINE('Average Revenue: ' || v_avg_revenue);
        DBMS_OUTPUT.PUT_LINE('Average Profit: ' || v_avg_profit);
        DBMS_OUTPUT.PUT_LINE('Average Rating: ' || v_avg_rating);
        DBMS_OUTPUT.PUT_LINE('Profitability Rate: ' || v_profitability || '%');

        DBMS_OUTPUT.PUT_LINE('');
    END LOOP;

    CLOSE popularity_cursor;

EXCEPTION
    WHEN OTHERS THEN
        IF popularity_cursor%ISOPEN THEN
            CLOSE popularity_cursor;
        END IF;

        RAISE;
END;
/



-- Procedure for rating of movies 

CREATE OR REPLACE PROCEDURE analyze_rating_performance (
    p_year IN NUMBER )
IS
    v_rating_group      VARCHAR2(30);
    v_movie_count       NUMBER;
    v_avg_rating        movies.vote_average%TYPE;
    v_avg_popularity    movies.popularity%TYPE;
    v_avg_budget        movies.budget%TYPE;
    v_avg_revenue       movies.revenue%TYPE;
    v_avg_profit        NUMBER;
    v_profitability     NUMBER;

    CURSOR rating_cursor IS
        SELECT
            CASE
                WHEN vote_average < 5 THEN 'Low Rating'
                WHEN vote_average < 7 THEN 'Moderate Rating'
                WHEN vote_average < 8 THEN 'High Rating'
                ELSE 'Very High Rating'
            END AS rating_group,

            COUNT(*) AS movie_count,
            ROUND(AVG(vote_average), 2) AS avg_rating,
            ROUND(AVG(popularity), 2) AS avg_popularity,
            ROUND(AVG(budget), 2) AS avg_budget,
            ROUND(AVG(revenue), 2) AS avg_revenue,
            ROUND(AVG(revenue - budget), 2) AS avg_profit,
            ROUND(COUNT(CASE
                        WHEN revenue > budget THEN 1
                    END) * 100 / COUNT(*),2
            ) AS profitability_rate

        FROM movies
        WHERE release_date IS NOT NULL
          AND vote_count > 0
          AND budget > 0
          AND revenue > 0
          AND EXTRACT(YEAR FROM release_date) = p_year

        GROUP BY
            CASE
                WHEN vote_average < 5 THEN 'Low Rating'
                WHEN vote_average < 7 THEN 'Moderate Rating'
                WHEN vote_average < 8 THEN 'High Rating'
                ELSE 'Very High Rating'
            END

        ORDER BY MIN(vote_average);

BEGIN

    DBMS_OUTPUT.PUT_LINE('Rating Performance Analysis');
    DBMS_OUTPUT.PUT_LINE('---------------------------');
    DBMS_OUTPUT.PUT_LINE('Year: ' || p_year);
    DBMS_OUTPUT.PUT_LINE('');

    OPEN rating_cursor;

    LOOP
        FETCH rating_cursor INTO
            v_rating_group,
            v_movie_count,
            v_avg_rating,
            v_avg_popularity,
            v_avg_budget,
            v_avg_revenue,
            v_avg_profit,
            v_profitability;

        EXIT WHEN rating_cursor%NOTFOUND;

        DBMS_OUTPUT.PUT_LINE('Rating Group: ' || v_rating_group);
        DBMS_OUTPUT.PUT_LINE('Movie Count: ' || v_movie_count);
        DBMS_OUTPUT.PUT_LINE('Average Rating: ' || v_avg_rating);
        DBMS_OUTPUT.PUT_LINE('Average Popularity: ' || v_avg_popularity);
        DBMS_OUTPUT.PUT_LINE('Average Budget: ' || v_avg_budget);
        DBMS_OUTPUT.PUT_LINE('Average Revenue: ' || v_avg_revenue);
        DBMS_OUTPUT.PUT_LINE('Average Profit: ' || v_avg_profit);
        DBMS_OUTPUT.PUT_LINE('Profitability Rate: ' || v_profitability || '%');
        DBMS_OUTPUT.PUT_LINE('');
    END LOOP;

    CLOSE rating_cursor;

EXCEPTION
    WHEN OTHERS THEN
        IF rating_cursor%ISOPEN THEN
            CLOSE rating_cursor;
        END IF;

        RAISE_APPLICATION_ERROR(-20001,'Error in rating analysis: ' || SQLERRM);
END;
/



-- Procedure for genre trends

CREATE OR REPLACE PROCEDURE analyze_genre_trends (
    p_start_year IN NUMBER,
    p_end_year   IN NUMBER
)
IS
    CURSOR genre_trend_cursor IS
        SELECT
            g.genre_name,

            COUNT(CASE
                WHEN EXTRACT(YEAR FROM m.release_date) = p_start_year
                THEN m.movie_id
            END) AS start_movie_count,

            COUNT(CASE
                WHEN EXTRACT(YEAR FROM m.release_date) = p_end_year
                THEN m.movie_id
            END) AS end_movie_count,

            AVG(CASE
                WHEN EXTRACT(YEAR FROM m.release_date) = p_start_year
                THEN m.revenue
            END) AS start_avg_revenue,

            AVG(CASE
                WHEN EXTRACT(YEAR FROM m.release_date) = p_end_year
                THEN m.revenue
            END) AS end_avg_revenue,

            AVG(CASE
                WHEN EXTRACT(YEAR FROM m.release_date) = p_start_year
                THEN m.revenue - m.budget
            END) AS start_avg_profit,

            AVG(CASE
                WHEN EXTRACT(YEAR FROM m.release_date) = p_end_year
                THEN m.revenue - m.budget
            END) AS end_avg_profit,

            AVG(CASE
                WHEN EXTRACT(YEAR FROM m.release_date) = p_start_year
                THEN m.popularity
            END) AS start_avg_popularity,

            AVG(CASE
                WHEN EXTRACT(YEAR FROM m.release_date) = p_end_year
                THEN m.popularity
            END) AS end_avg_popularity,

            AVG(CASE
                WHEN EXTRACT(YEAR FROM m.release_date) = p_start_year
                THEN m.vote_average
            END) AS start_avg_rating,

            AVG(CASE
                WHEN EXTRACT(YEAR FROM m.release_date) = p_end_year
                THEN m.vote_average
            END) AS end_avg_rating,

            COUNT(CASE
                WHEN EXTRACT(YEAR FROM m.release_date) = p_start_year
                     AND m.revenue > m.budget
                THEN 1
            END) AS start_profitable_movies,

            COUNT(CASE
                WHEN EXTRACT(YEAR FROM m.release_date) = p_end_year
                     AND m.revenue > m.budget
                THEN 1
            END) AS end_profitable_movies

        FROM genres g
        JOIN movie_genres mg
            ON g.genre_id = mg.genre_id
        JOIN movies m
            ON mg.movie_id = m.movie_id

        WHERE m.release_date IS NOT NULL
          AND m.budget > 0
          AND m.revenue > 0
          AND EXTRACT(YEAR FROM m.release_date)
              IN (p_start_year, p_end_year)

        GROUP BY g.genre_name
        ORDER BY g.genre_name;

    v_genre_name           genres.genre_name%TYPE;

    v_start_movie_count    NUMBER;
    v_end_movie_count      NUMBER;

    v_start_avg_revenue    movies.revenue%TYPE;
    v_end_avg_revenue      movies.revenue%TYPE;

    v_start_avg_profit     NUMBER;
    v_end_avg_profit       NUMBER;

    v_start_avg_popularity movies.popularity%TYPE;
    v_end_avg_popularity   movies.popularity%TYPE;

    v_start_avg_rating     movies.vote_average%TYPE;
    v_end_avg_rating       movies.vote_average%TYPE;

    v_start_profitable     NUMBER;
    v_end_profitable       NUMBER;

    v_revenue_change       NUMBER;
    v_profit_change        NUMBER;
    v_popularity_change    NUMBER;
    v_rating_change        NUMBER;
    v_movie_count_change   NUMBER;

    v_start_profitability  NUMBER;
    v_end_profitability    NUMBER;

BEGIN

    IF p_start_year >= p_end_year THEN
        DBMS_OUTPUT.PUT_LINE(
            'Start year must be earlier than end year.'
        );
        RETURN;
    END IF;

    DBMS_OUTPUT.PUT_LINE('Genre Trend Analysis');
    DBMS_OUTPUT.PUT_LINE('====================');
    DBMS_OUTPUT.PUT_LINE(
        'Period: ' || p_start_year || ' to ' || p_end_year
    );
    DBMS_OUTPUT.PUT_LINE('');

    OPEN genre_trend_cursor;

    LOOP
        FETCH genre_trend_cursor INTO
            v_genre_name,
            v_start_movie_count,
            v_end_movie_count,
            v_start_avg_revenue,
            v_end_avg_revenue,
            v_start_avg_profit,
            v_end_avg_profit,
            v_start_avg_popularity,
            v_end_avg_popularity,
            v_start_avg_rating,
            v_end_avg_rating,
            v_start_profitable,
            v_end_profitable;

        EXIT WHEN genre_trend_cursor%NOTFOUND;

        v_revenue_change :=
            CASE
                WHEN v_start_avg_revenue IS NOT NULL
                     AND v_start_avg_revenue <> 0
                THEN
                    ROUND(
                        (v_end_avg_revenue - v_start_avg_revenue)
                        / v_start_avg_revenue * 100,
                        2
                    )
            END;

        v_profit_change :=
            CASE
                WHEN v_start_avg_profit IS NOT NULL
                     AND v_start_avg_profit <> 0
                THEN
                    ROUND(
                        (v_end_avg_profit - v_start_avg_profit)
                        / ABS(v_start_avg_profit) * 100,
                        2
                    )
            END;

        v_popularity_change :=
            CASE
                WHEN v_start_avg_popularity IS NOT NULL
                     AND v_start_avg_popularity <> 0
                THEN
                    ROUND(
                        (v_end_avg_popularity - v_start_avg_popularity)
                        / v_start_avg_popularity * 100,
                        2
                    )
            END;

        v_rating_change :=
            CASE
                WHEN v_start_avg_rating IS NOT NULL
                THEN
                    ROUND(
                        v_end_avg_rating - v_start_avg_rating,
                        2
                    )
            END;

        v_movie_count_change :=
            v_end_movie_count - v_start_movie_count;

        v_start_profitability :=
            CASE
                WHEN v_start_movie_count > 0
                THEN ROUND(
                    v_start_profitable * 100
                    / v_start_movie_count,
                    2
                )
            END;

        v_end_profitability :=
            CASE
                WHEN v_end_movie_count > 0
                THEN ROUND(
                    v_end_profitable * 100
                    / v_end_movie_count,
                    2
                )
            END;

        DBMS_OUTPUT.PUT_LINE('Genre: ' || v_genre_name);
        DBMS_OUTPUT.PUT_LINE('  Movies: ' ||v_start_movie_count || ' -> ' ||v_end_movie_count || ' (Change: ' || v_movie_count_change || ')');
        DBMS_OUTPUT.PUT_LINE('  Avg Revenue: ' || ROUND(v_start_avg_revenue, 2) || ' -> ' || ROUND(v_end_avg_revenue, 2) || ' (' || v_revenue_change || '%)');
        DBMS_OUTPUT.PUT_LINE('  Avg Profit: ' || ROUND(v_start_avg_profit, 2) || ' -> ' || ROUND(v_end_avg_profit, 2) || ' (' || v_profit_change || '%)');
        DBMS_OUTPUT.PUT_LINE('  Avg Popularity: ' || ROUND(v_start_avg_popularity, 2) || ' -> ' || ROUND(v_end_avg_popularity, 2) || ' (' || v_popularity_change || '%)');
        DBMS_OUTPUT.PUT_LINE('  Avg Rating: ' || ROUND(v_start_avg_rating, 2) || ' -> ' || ROUND(v_end_avg_rating, 2) || ' (Change: ' || v_rating_change || ')');
        DBMS_OUTPUT.PUT_LINE('  Profitability: ' || v_start_profitability || '% -> ' || v_end_profitability || '%');
        DBMS_OUTPUT.PUT_LINE('--------------------------------------------------');

    END LOOP;

    CLOSE genre_trend_cursor;

EXCEPTION
    WHEN OTHERS THEN
        IF genre_trend_cursor%ISOPEN THEN
            CLOSE genre_trend_cursor;
        END IF;
        DBMS_OUTPUT.PUT_LINE('Error: ' || SQLERRM);
END;
/




CREATE OR REPLACE PROCEDURE analyze_genre_yearly_trend (
    p_genre_name IN genres.genre_name%TYPE,
    p_start_year IN NUMBER,
    p_end_year   IN NUMBER
)
IS
    CURSOR yearly_trend_cursor IS
        SELECT
            EXTRACT(YEAR FROM m.release_date) AS release_year,
            COUNT(m.movie_id) AS movie_count,
            ROUND(AVG(m.revenue), 2) AS avg_revenue,
            ROUND(AVG(m.revenue - m.budget), 2) AS avg_profit,
            ROUND(AVG(m.popularity), 2) AS avg_popularity,
            ROUND(AVG(m.vote_average), 2) AS avg_rating,
            ROUND(
                COUNT(
                    CASE
                        WHEN m.revenue > m.budget THEN 1
                    END
                ) * 100 / COUNT(*),
                2
            ) AS profitability_rate
        FROM movies m
        JOIN movie_genres mg
            ON m.movie_id = mg.movie_id
        JOIN genres g
            ON mg.genre_id = g.genre_id
        WHERE g.genre_name = p_genre_name
          AND m.release_date IS NOT NULL
          AND m.budget > 0
          AND m.revenue > 0
          AND EXTRACT(YEAR FROM m.release_date)
              BETWEEN p_start_year AND p_end_year
        GROUP BY EXTRACT(YEAR FROM m.release_date)
        ORDER BY release_year;

    v_release_year       NUMBER;
    v_movie_count        NUMBER;

    v_avg_revenue        movies.revenue%TYPE;
    v_avg_profit         NUMBER;
    v_avg_popularity     movies.popularity%TYPE;
    v_avg_rating         movies.vote_average%TYPE;
    v_profitability      NUMBER;

BEGIN

    IF p_start_year >= p_end_year THEN
        DBMS_OUTPUT.PUT_LINE('Start year must be earlier than end year.');
        RETURN;
    END IF;

    DBMS_OUTPUT.PUT_LINE('Genre Yearly Trend Analysis');
    DBMS_OUTPUT.PUT_LINE('===========================');
    DBMS_OUTPUT.PUT_LINE('Genre: ' || p_genre_name);
    DBMS_OUTPUT.PUT_LINE('Period: ' || p_start_year || ' to ' || p_end_year);
    DBMS_OUTPUT.PUT_LINE('');

    DBMS_OUTPUT.PUT_LINE('Year | Movies | Avg Revenue | Avg Profit | Avg Popularity | Avg Rating | Profitability');

    DBMS_OUTPUT.PUT_LINE('-----------------------------------------------------------------------------------------');

    OPEN yearly_trend_cursor;

    LOOP

        FETCH yearly_trend_cursor INTO
            v_release_year,
            v_movie_count,
            v_avg_revenue,
            v_avg_profit,
            v_avg_popularity,
            v_avg_rating,
            v_profitability;

        EXIT WHEN yearly_trend_cursor%NOTFOUND;

        DBMS_OUTPUT.PUT_LINE(
            v_release_year || ' | ' ||
            v_movie_count || ' | ' ||
            v_avg_revenue || ' | ' ||
            v_avg_profit || ' | ' ||
            v_avg_popularity || ' | ' ||
            v_avg_rating || ' | ' ||
            v_profitability || '%'
        );

    END LOOP;

    CLOSE yearly_trend_cursor;

EXCEPTION
    WHEN OTHERS THEN

        IF yearly_trend_cursor%ISOPEN THEN
            CLOSE yearly_trend_cursor;
        END IF;

        DBMS_OUTPUT.PUT_LINE(
            'Error: ' || SQLERRM
        );

END;
/

BEGIN
    analyze_genre_yearly_trend('Science Fiction',2000,2015);
END;
/

-- Procedure for genre growth

CREATE OR REPLACE PROCEDURE analyze_genre_growth (
    p_start_year IN NUMBER,
    p_end_year   IN NUMBER
)
IS
    CURSOR genre_growth_cursor IS
        SELECT
            g.genre_name,

            COUNT(DISTINCT CASE
                WHEN EXTRACT(YEAR FROM m.release_date) = p_start_year
                THEN m.movie_id
            END) AS start_movie_count,

            COUNT(DISTINCT CASE
                WHEN EXTRACT(YEAR FROM m.release_date) = p_end_year
                THEN m.movie_id
            END) AS end_movie_count,

            COUNT(DISTINCT EXTRACT(YEAR FROM m.release_date))
                AS years_available,

            AVG(CASE
                WHEN EXTRACT(YEAR FROM m.release_date) = p_start_year
                THEN m.revenue
            END) AS start_avg_revenue,

            AVG(CASE
                WHEN EXTRACT(YEAR FROM m.release_date) = p_end_year
                THEN m.revenue
            END) AS end_avg_revenue,

            AVG(CASE
                WHEN EXTRACT(YEAR FROM m.release_date) = p_start_year
                THEN m.revenue - m.budget
            END) AS start_avg_profit,

            AVG(CASE
                WHEN EXTRACT(YEAR FROM m.release_date) = p_end_year
                THEN m.revenue - m.budget
            END) AS end_avg_profit,

            AVG(CASE
                WHEN EXTRACT(YEAR FROM m.release_date) = p_start_year
                THEN m.popularity
            END) AS start_avg_popularity,

            AVG(CASE
                WHEN EXTRACT(YEAR FROM m.release_date) = p_end_year
                THEN m.popularity
            END) AS end_avg_popularity,

            AVG(CASE
                WHEN EXTRACT(YEAR FROM m.release_date) = p_start_year
                THEN m.vote_average
            END) AS start_avg_rating,

            AVG(CASE
                WHEN EXTRACT(YEAR FROM m.release_date) = p_end_year
                THEN m.vote_average
            END) AS end_avg_rating,

            COUNT(CASE
                WHEN EXTRACT(YEAR FROM m.release_date) = p_start_year
                     AND m.revenue > m.budget
                THEN 1
            END) AS start_profitable_movies,

            COUNT(CASE
                WHEN EXTRACT(YEAR FROM m.release_date) = p_end_year
                     AND m.revenue > m.budget
                THEN 1
            END) AS end_profitable_movies

        FROM genres g
        JOIN movie_genres mg
            ON g.genre_id = mg.genre_id
        JOIN movies m
            ON mg.movie_id = m.movie_id

        WHERE m.release_date IS NOT NULL
          AND m.budget > 0
          AND m.revenue > 0
          AND EXTRACT(YEAR FROM m.release_date)
              BETWEEN p_start_year AND p_end_year

        GROUP BY g.genre_name
        ORDER BY g.genre_name;

    v_genre_name           genres.genre_name%TYPE;

    v_start_movie_count    NUMBER;
    v_end_movie_count      NUMBER;
    v_years_available     NUMBER;

    v_start_avg_revenue    movies.revenue%TYPE;
    v_end_avg_revenue      movies.revenue%TYPE;

    v_start_avg_profit     NUMBER;
    v_end_avg_profit       NUMBER;

    v_start_avg_popularity movies.popularity%TYPE;
    v_end_avg_popularity   movies.popularity%TYPE;

    v_start_avg_rating     movies.vote_average%TYPE;
    v_end_avg_rating       movies.vote_average%TYPE;

    v_start_profitable     NUMBER;
    v_end_profitable       NUMBER;

    v_revenue_change       NUMBER;
    v_profit_change        NUMBER;
    v_popularity_change    NUMBER;
    v_rating_change        NUMBER;
    v_movie_count_change   NUMBER;

    v_start_profitability  NUMBER;
    v_end_profitability    NUMBER;

BEGIN

    IF p_start_year >= p_end_year THEN
        DBMS_OUTPUT.PUT_LINE(
            'Start year must be earlier than end year.'
        );
        RETURN;
    END IF;

    DBMS_OUTPUT.PUT_LINE('Genre Growth Analysis');
    DBMS_OUTPUT.PUT_LINE('=====================');
    DBMS_OUTPUT.PUT_LINE(
        'Period: ' || p_start_year || ' to ' || p_end_year
    );
    DBMS_OUTPUT.PUT_LINE('');

    OPEN genre_growth_cursor;

    LOOP

        FETCH genre_growth_cursor INTO
            v_genre_name,
            v_start_movie_count,
            v_end_movie_count,
            v_years_available,
            v_start_avg_revenue,
            v_end_avg_revenue,
            v_start_avg_profit,
            v_end_avg_profit,
            v_start_avg_popularity,
            v_end_avg_popularity,
            v_start_avg_rating,
            v_end_avg_rating,
            v_start_profitable,
            v_end_profitable;

        EXIT WHEN genre_growth_cursor%NOTFOUND;

        v_revenue_change :=
            CASE
                WHEN v_start_avg_revenue IS NOT NULL
                     AND v_start_avg_revenue <> 0
                     AND v_end_avg_revenue IS NOT NULL
                THEN
                    ROUND(
                        (v_end_avg_revenue - v_start_avg_revenue)
                        / v_start_avg_revenue * 100,
                        2
                    )
            END;

        v_profit_change :=
            CASE
                WHEN v_start_avg_profit IS NOT NULL
                     AND v_start_avg_profit <> 0
                     AND v_end_avg_profit IS NOT NULL
                THEN
                    ROUND(
                        (v_end_avg_profit - v_start_avg_profit)
                        / ABS(v_start_avg_profit) * 100,
                        2
                    )
            END;

        v_popularity_change :=
            CASE
                WHEN v_start_avg_popularity IS NOT NULL
                     AND v_start_avg_popularity <> 0
                     AND v_end_avg_popularity IS NOT NULL
                THEN
                    ROUND(
                        (v_end_avg_popularity - v_start_avg_popularity)
                        / v_start_avg_popularity * 100,
                        2
                    )
            END;

        v_rating_change :=
            CASE
                WHEN v_start_avg_rating IS NOT NULL
                     AND v_end_avg_rating IS NOT NULL
                THEN
                    ROUND(
                        v_end_avg_rating - v_start_avg_rating,
                        2
                    )
            END;

        v_movie_count_change :=
            v_end_movie_count - v_start_movie_count;

        v_start_profitability :=
            CASE
                WHEN v_start_movie_count > 0
                THEN
                    ROUND(
                        v_start_profitable * 100
                        / v_start_movie_count,
                        2
                    )
            END;

        v_end_profitability :=
            CASE
                WHEN v_end_movie_count > 0
                THEN
                    ROUND(
                        v_end_profitable * 100
                        / v_end_movie_count,
                        2
                    )
            END;

        DBMS_OUTPUT.PUT_LINE('Genre: ' || v_genre_name);
        DBMS_OUTPUT.PUT_LINE('  Years Available: ' || v_years_available);
        DBMS_OUTPUT.PUT_LINE('  Movies: ' || v_start_movie_count || ' -> ' || v_end_movie_count || ' (Change: ' || v_movie_count_change || ')' );
        DBMS_OUTPUT.PUT_LINE('  Avg Revenue: ' || ROUND(v_start_avg_revenue, 2) || ' -> ' || ROUND(v_end_avg_revenue, 2) || ' (' || v_revenue_change || '%)');
        DBMS_OUTPUT.PUT_LINE('  Avg Profit: ' || ROUND(v_start_avg_profit, 2) || ' -> ' || ROUND(v_end_avg_profit, 2) || ' (' || v_profit_change || '%)');
        DBMS_OUTPUT.PUT_LINE('  Avg Popularity: ' || ROUND(v_start_avg_popularity, 2) || ' -> ' || ROUND(v_end_avg_popularity, 2) || ' (' || v_popularity_change || '%)' );
        DBMS_OUTPUT.PUT_LINE('  Avg Rating: ' || ROUND(v_start_avg_rating, 2) || ' -> ' || ROUND(v_end_avg_rating, 2) || ' (Change: ' || v_rating_change || ')');
        DBMS_OUTPUT.PUT_LINE('  Profitability: ' || v_start_profitability || '% -> ' || v_end_profitability || '%');
        DBMS_OUTPUT.PUT_LINE('--------------------------------------------------');

    END LOOP;

    CLOSE genre_growth_cursor;

EXCEPTION
    WHEN OTHERS THEN

        IF genre_growth_cursor%ISOPEN THEN
            CLOSE genre_growth_cursor;
        END IF;

        DBMS_OUTPUT.PUT_LINE(
            'Error: ' || SQLERRM
        );

END;
/



-- Genre momentum procedure
CREATE OR REPLACE PROCEDURE analyze_genre_momentum (
    p_start_year IN NUMBER,
    p_end_year   IN NUMBER
)
IS
    CURSOR genre_momentum_cursor IS
        SELECT
            genre_name,
            years_available,
            revenue_slope,
            profit_slope,
            popularity_slope,
            rating_slope,
            profitability_slope
        FROM (
            SELECT
                genre_name,

                COUNT(*) AS years_available,

                REGR_SLOPE(
                    avg_revenue,
                    release_year
                ) AS revenue_slope,

                REGR_SLOPE(
                    avg_profit,
                    release_year
                ) AS profit_slope,

                REGR_SLOPE(
                    avg_popularity,
                    release_year
                ) AS popularity_slope,

                REGR_SLOPE(
                    avg_rating,
                    release_year
                ) AS rating_slope,

                REGR_SLOPE(
                    profitability_rate,
                    release_year
                ) AS profitability_slope

            FROM (
                SELECT
                    g.genre_name,

                    EXTRACT(YEAR FROM m.release_date)
                        AS release_year,

                    AVG(m.revenue)
                        AS avg_revenue,

                    AVG(m.revenue - m.budget)
                        AS avg_profit,

                    AVG(m.popularity)
                        AS avg_popularity,

                    AVG(m.vote_average)
                        AS avg_rating,

                    COUNT(
                        CASE
                            WHEN m.revenue > m.budget
                            THEN 1
                        END
                    ) * 100 / COUNT(*)
                        AS profitability_rate

                FROM genres g
                JOIN movie_genres mg
                    ON g.genre_id = mg.genre_id
                JOIN movies m
                    ON mg.movie_id = m.movie_id

                WHERE m.release_date IS NOT NULL
                  AND m.budget > 0
                  AND m.revenue > 0
                  AND EXTRACT(YEAR FROM m.release_date)
                      BETWEEN p_start_year AND p_end_year

                GROUP BY
                    g.genre_name,
                    EXTRACT(YEAR FROM m.release_date)
            )

            GROUP BY genre_name
        )
        WHERE years_available >= 5
        ORDER BY popularity_slope DESC;

    v_genre_name            genres.genre_name%TYPE;
    v_years_available       NUMBER;

    v_revenue_slope         NUMBER;
    v_profit_slope          NUMBER;
    v_popularity_slope      NUMBER;
    v_rating_slope          NUMBER;
    v_profitability_slope   NUMBER;

BEGIN

    IF p_start_year >= p_end_year THEN
        DBMS_OUTPUT.PUT_LINE(
            'Start year must be earlier than end year.'
        );
        RETURN;
    END IF;

    DBMS_OUTPUT.PUT_LINE('Genre Momentum Analysis');
    DBMS_OUTPUT.PUT_LINE('=======================');
    DBMS_OUTPUT.PUT_LINE('Period: ' || p_start_year || ' to ' || p_end_year);
    DBMS_OUTPUT.PUT_LINE('Minimum years of data: 5');
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('Genre | Years | Revenue Slope | Profit Slope | Popularity Slope | Rating Slope | Profitability Slope');
    DBMS_OUTPUT.PUT_LINE('---------------------------------------------------------------------------------------------------------');

    OPEN genre_momentum_cursor;

    LOOP

        FETCH genre_momentum_cursor INTO
            v_genre_name,
            v_years_available,
            v_revenue_slope,
            v_profit_slope,
            v_popularity_slope,
            v_rating_slope,
            v_profitability_slope;

        EXIT WHEN genre_momentum_cursor%NOTFOUND;

        DBMS_OUTPUT.PUT_LINE(
            v_genre_name || ' | ' ||
            v_years_available || ' | ' ||
            ROUND(v_revenue_slope, 2) || ' | ' ||
            ROUND(v_profit_slope, 2) || ' | ' ||
            ROUND(v_popularity_slope, 2) || ' | ' ||
            ROUND(v_rating_slope, 4) || ' | ' ||
            ROUND(v_profitability_slope, 2) || '%'
        );

    END LOOP;

    CLOSE genre_momentum_cursor;

EXCEPTION
    WHEN OTHERS THEN

        IF genre_momentum_cursor%ISOPEN THEN
            CLOSE genre_momentum_cursor;
        END IF;

        DBMS_OUTPUT.PUT_LINE('Error: ' || SQLERRM);
END;
/


-- Procedure for recent genre trends
CREATE OR REPLACE PROCEDURE analyze_recent_genre_trends (
    p_hist_start   IN NUMBER,
    p_hist_end     IN NUMBER,
    p_recent_start IN NUMBER,
    p_recent_end   IN NUMBER
)
IS
    CURSOR genre_trend_cursor IS
        SELECT
            genre_name,
            historical_movie_count,
            recent_movie_count,
            ROUND((recent_avg_revenue - historical_avg_revenue)/ NULLIF(historical_avg_revenue, 0) * 100,2) AS revenue_change_pct,
            ROUND((recent_avg_profit - historical_avg_profit)/ NULLIF(ABS(historical_avg_profit), 0) * 100,2) AS profit_change_pct,
            ROUND((recent_avg_popularity - historical_avg_popularity)/ NULLIF(historical_avg_popularity, 0) * 100,2) AS popularity_change_pct,
            ROUND(recent_avg_rating - historical_avg_rating,2) AS rating_change,
            ROUND(recent_profitability - historical_profitability,2) AS profitability_change

        FROM (
            SELECT
                g.genre_name,
                COUNT(
                    CASE
                        WHEN EXTRACT(YEAR FROM m.release_date)
                             BETWEEN p_hist_start AND p_hist_end
                        THEN m.movie_id
                    END
                ) AS historical_movie_count,

                COUNT(
                    CASE
                        WHEN EXTRACT(YEAR FROM m.release_date)
                             BETWEEN p_recent_start AND p_recent_end
                        THEN m.movie_id
                    END
                ) AS recent_movie_count,

                AVG(
                    CASE
                        WHEN EXTRACT(YEAR FROM m.release_date)
                             BETWEEN p_hist_start AND p_hist_end
                        THEN m.revenue
                    END
                ) AS historical_avg_revenue,

                AVG(
                    CASE
                        WHEN EXTRACT(YEAR FROM m.release_date)
                             BETWEEN p_recent_start AND p_recent_end
                        THEN m.revenue
                    END
                ) AS recent_avg_revenue,

                AVG(
                    CASE
                        WHEN EXTRACT(YEAR FROM m.release_date)
                             BETWEEN p_hist_start AND p_hist_end
                        THEN m.revenue - m.budget
                    END
                ) AS historical_avg_profit,

                AVG(
                    CASE
                        WHEN EXTRACT(YEAR FROM m.release_date)
                             BETWEEN p_recent_start AND p_recent_end
                        THEN m.revenue - m.budget
                    END
                ) AS recent_avg_profit,

                AVG(
                    CASE
                        WHEN EXTRACT(YEAR FROM m.release_date)
                             BETWEEN p_hist_start AND p_hist_end
                        THEN m.popularity
                    END
                ) AS historical_avg_popularity,

                AVG(
                    CASE
                        WHEN EXTRACT(YEAR FROM m.release_date)
                             BETWEEN p_recent_start AND p_recent_end
                        THEN m.popularity
                    END
                ) AS recent_avg_popularity,

                AVG(
                    CASE
                        WHEN EXTRACT(YEAR FROM m.release_date)
                             BETWEEN p_hist_start AND p_hist_end
                        THEN m.vote_average
                    END
                ) AS historical_avg_rating,

                AVG(
                    CASE
                        WHEN EXTRACT(YEAR FROM m.release_date)
                             BETWEEN p_recent_start AND p_recent_end
                        THEN m.vote_average
                    END
                ) AS recent_avg_rating,

                COUNT(
                    CASE
                        WHEN EXTRACT(YEAR FROM m.release_date)
                             BETWEEN p_hist_start AND p_hist_end
                             AND m.revenue > m.budget
                        THEN 1
                    END
                ) * 100 /
                NULLIF(
                    COUNT(
                        CASE
                            WHEN EXTRACT(YEAR FROM m.release_date)
                                 BETWEEN p_hist_start AND p_hist_end
                            THEN 1
                        END
                    ),
                    0
                ) AS historical_profitability,

                COUNT(
                    CASE
                        WHEN EXTRACT(YEAR FROM m.release_date)
                             BETWEEN p_recent_start AND p_recent_end
                             AND m.revenue > m.budget
                        THEN 1
                    END
                ) * 100 /
                NULLIF(
                    COUNT(
                        CASE
                            WHEN EXTRACT(YEAR FROM m.release_date)
                                 BETWEEN p_recent_start AND p_recent_end
                            THEN 1
                        END
                    ),
                    0
                ) AS recent_profitability

            FROM genres g
            JOIN movie_genres mg
                ON g.genre_id = mg.genre_id
            JOIN movies m
                ON mg.movie_id = m.movie_id

            WHERE m.release_date IS NOT NULL
              AND m.budget > 0
              AND m.revenue > 0
              AND EXTRACT(YEAR FROM m.release_date)
                  BETWEEN p_hist_start AND p_recent_end

            GROUP BY g.genre_name
        )
        WHERE historical_movie_count > 0
          AND recent_movie_count > 0
        ORDER BY popularity_change_pct DESC;


    v_genre_name              genres.genre_name%TYPE;
    v_historical_count        NUMBER;
    v_recent_count            NUMBER;
    v_revenue_change          NUMBER;
    v_profit_change           NUMBER;
    v_popularity_change       NUMBER;
    v_rating_change           NUMBER;
    v_profitability_change    NUMBER;

BEGIN
    IF p_hist_start >= p_hist_end OR p_recent_start >= p_recent_end
       OR p_hist_end >= p_recent_start THEN
        DBMS_OUTPUT.PUT_LINE(
            'Periods must be valid and non-overlapping (historical before recent).'
        );
        RETURN;
    END IF;

    DBMS_OUTPUT.PUT_LINE('Recent vs Historical Genre Trend Analysis');
    DBMS_OUTPUT.PUT_LINE('==========================================');
    DBMS_OUTPUT.PUT_LINE('Historical Period: ' || p_hist_start || ' to ' || p_hist_end);
    DBMS_OUTPUT.PUT_LINE('Recent Period: ' || p_recent_start || ' to ' || p_recent_end);
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('Genre | Historical Movies | Recent Movies | Revenue Change | Profit Change | Popularity Change | Rating Change | Profitability Change');
    DBMS_OUTPUT.PUT_LINE('---------------------------------------------------------------------------------------------------------------------------------------');

    OPEN genre_trend_cursor;

    LOOP
        FETCH genre_trend_cursor INTO
            v_genre_name,
            v_historical_count,
            v_recent_count,
            v_revenue_change,
            v_profit_change,
            v_popularity_change,
            v_rating_change,
            v_profitability_change;

        EXIT WHEN genre_trend_cursor%NOTFOUND;

        DBMS_OUTPUT.PUT_LINE(
            v_genre_name || ' | ' ||
            v_historical_count || ' | ' ||
            v_recent_count || ' | ' ||
            v_revenue_change || '% | ' ||
            v_profit_change || '% | ' ||
            v_popularity_change || '% | ' ||
            v_rating_change || ' | ' ||
            v_profitability_change || '%'
        );
    END LOOP;
    CLOSE genre_trend_cursor;

EXCEPTION
    WHEN OTHERS THEN
        IF genre_trend_cursor%ISOPEN THEN
            CLOSE genre_trend_cursor;
        END IF;
        DBMS_OUTPUT.PUT_LINE('Error: ' || SQLERRM);
END;
/





-- Finding of release timing from the parameter.

CREATE OR REPLACE PROCEDURE analyze_release_timing (
    p_start_year IN NUMBER,
    p_end_year   IN NUMBER
)
IS
    CURSOR release_timing_cursor IS
        SELECT
            EXTRACT(MONTH FROM m.release_date) AS release_month,
            COUNT(*) AS movie_count,
            ROUND(AVG(m.revenue), 2) AS avg_revenue,
            ROUND(AVG(m.revenue - m.budget), 2) AS avg_profit,
            ROUND(AVG(m.popularity), 2) AS avg_popularity,
            ROUND(AVG(m.vote_average), 2) AS avg_rating,
            ROUND(
                COUNT(
                    CASE
                        WHEN m.revenue > m.budget THEN 1
                    END
                ) * 100 / COUNT(*),
                2
            ) AS profitability_rate
        FROM movies m
        WHERE m.release_date IS NOT NULL
          AND m.budget > 0
          AND m.revenue > 0
          AND EXTRACT(YEAR FROM m.release_date)
              BETWEEN p_start_year AND p_end_year
        GROUP BY EXTRACT(MONTH FROM m.release_date)
        ORDER BY release_month;

    v_release_month       NUMBER;
    v_movie_count         NUMBER;
    v_avg_revenue         movies.revenue%TYPE;
    v_avg_profit          NUMBER;
    v_avg_popularity      movies.popularity%TYPE;
    v_avg_rating          movies.vote_average%TYPE;
    v_profitability_rate  NUMBER;

BEGIN
    IF p_start_year >= p_end_year THEN
        DBMS_OUTPUT.PUT_LINE(
            'Start year must be earlier than end year.'
        );
        RETURN;
    END IF;

    DBMS_OUTPUT.PUT_LINE('Release Timing Analysis');
    DBMS_OUTPUT.PUT_LINE('=======================');
    DBMS_OUTPUT.PUT_LINE(
        'Period: ' || p_start_year || ' to ' || p_end_year
    );
    DBMS_OUTPUT.PUT_LINE('');

    DBMS_OUTPUT.PUT_LINE(
        'Month | Movies | Avg Revenue | Avg Profit | Avg Popularity | Avg Rating | Profitability'
    );

    DBMS_OUTPUT.PUT_LINE(
        '------------------------------------------------------------------------------------------'
    );

    OPEN release_timing_cursor;

    LOOP
        FETCH release_timing_cursor INTO
            v_release_month,
            v_movie_count,
            v_avg_revenue,
            v_avg_profit,
            v_avg_popularity,
            v_avg_rating,
            v_profitability_rate;

        EXIT WHEN release_timing_cursor%NOTFOUND;

        DBMS_OUTPUT.PUT_LINE(
            v_release_month || ' | ' ||
            v_movie_count || ' | ' ||
            v_avg_revenue || ' | ' ||
            v_avg_profit || ' | ' ||
            v_avg_popularity || ' | ' ||
            v_avg_rating || ' | ' ||
            v_profitability_rate || '%'
        );
    END LOOP;

    CLOSE release_timing_cursor;

EXCEPTION
    WHEN OTHERS THEN
        IF release_timing_cursor%ISOPEN THEN
            CLOSE release_timing_cursor;
        END IF;

        DBMS_OUTPUT.PUT_LINE(
            'Error: ' || SQLERRM
        );
END;
/

