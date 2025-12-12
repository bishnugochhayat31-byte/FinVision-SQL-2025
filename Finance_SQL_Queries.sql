


-- Run this once to wipe everything clean (safe – only drops our 5 tables)
DROP TABLE IF EXISTS repayments;
DROP TABLE IF EXISTS loans;
DROP TABLE IF EXISTS transactions;
DROP TABLE IF EXISTS credit_score_monthly;
DROP TABLE IF EXISTS users;

-- 1. Create all tables
CREATE TABLE users (
    user_id INT PRIMARY KEY,
    signup_date DATE,
    city VARCHAR(20),
    age INT,
    monthly_income INT
);

CREATE TABLE loans (
    loan_id INT PRIMARY KEY,
    user_id INT,
    disbursal_date DATE,
    loan_amount DECIMAL(12,2),
    tenure_months INT,
    interest_rate DECIMAL(5,2)
);

CREATE TABLE repayments (
    repayment_id INT PRIMARY KEY,
    loan_id INT,
    due_date DATE,
    paid_date DATE,
    amount_due DECIMAL(10,2),
    amount_paid DECIMAL(10,2)
);

CREATE TABLE transactions (
    txn_id INT PRIMARY KEY,
    user_id INT,
    txn_date DATE,
    amount DECIMAL(12,2),
    type VARCHAR(20)  -- 'credit' or 'debit'
);

CREATE TABLE credit_score_monthly (
    user_id INT,
    month_date DATE,
    cibil_score INT
);
-- Query 1: Collection Efficiency % (April 2025)
SELECT 
  FORMAT(due_date,'yyyy-MM') AS month,
  SUM(amount_due) AS total_due,
  SUM(amount_paid) AS collected,
  CONCAT(CAST(ROUND(100.0 * SUM(amount_paid)/NULLIF(SUM(amount_due),0),2) AS VARCHAR),'%') AS efficiency
FROM repayments
GROUP BY FORMAT(due_date,'yyyy-MM');

-- Query 2: DPD 30+ Rate
SELECT 
  COUNT(*) AS total_emis,
  SUM(CASE WHEN DATEDIFF(DAY,due_date,GETDATE()) > 30 AND paid_date IS NULL THEN 1 ELSE 0 END) AS dpd30,
  CONCAT(CAST(ROUND(100.0 * SUM(CASE WHEN DATEDIFF(DAY,due_date,GETDATE()) > 30 AND paid_date IS NULL THEN 1 ELSE 0 END)*1.0/COUNT(*),2) AS VARCHAR),'%') AS dpd30_rate
FROM repayments;

-- QUERY 3: Collection Efficiency % (Monthly)

SELECT 
    FORMAT(due_date, 'yyyy-MM') AS month,
    COUNT(*) AS total_emis_due,
    SUM(amount_due) AS total_amount_due,
    SUM(amount_paid) AS total_amount_collected,
    SUM(CASE WHEN paid_date IS NOT NULL THEN 1 ELSE 0 END) AS emis_paid,
    CONCAT(
        CAST(ROUND(100.0 * SUM(amount_paid) / NULLIF(SUM(amount_due),0), 2) AS VARCHAR),
        '%' 
    ) AS collection_efficiency_percent,
    CONCAT(
        CAST(ROUND(100.0 * SUM(CASE WHEN paid_date IS NOT NULL THEN 1 ELSE 0 END)*1.0 / COUNT(*), 2) AS VARCHAR),
        '%' 
    ) AS emi_collection_rate
FROM repayments
GROUP BY FORMAT(due_date, 'yyyy-MM')
ORDER BY month;

-- QUERY 4: Portfolio at Risk (PAR 30+) – RBI Standard Metric

SELECT 
    CONCAT(
        CAST(ROUND(100.0 * 
            SUM(CASE 
                WHEN DATEDIFF(DAY, r.due_date, GETDATE()) > 30 
                     AND r.paid_date IS NULL 
                THEN (l.loan_amount - ISNULL(paid_so_far.paid_amount, 0)) 
                ELSE 0 
            END) 
            / NULLIF(SUM(l.loan_amount), 0), 2) AS VARCHAR),
        '%' 
    ) AS PAR_30_percent,
    SUM(l.loan_amount) AS total_portfolio,
    SUM(CASE 
        WHEN DATEDIFF(DAY, r.due_date, GETDATE()) > 30 AND r.paid_date IS NULL 
        THEN (l.loan_amount - ISNULL(paid_so_far.paid_amount, 0)) 
        ELSE 0 
    END) AS amount_at_risk
FROM loans l
LEFT JOIN repayments r ON l.loan_id = r.loan_id
LEFT JOIN (
    SELECT loan_id, SUM(amount_paid) AS paid_amount
    FROM repayments 
    GROUP BY loan_id
) paid_so_far ON l.loan_id = paid_so_far.loan_id
GROUP BY l.loan_id;

-- 5. Monthly Active Users (MAU) & MoM Growth
WITH mau AS (
    SELECT 
        FORMAT(txn_date, 'yyyy-MM-01') AS month,
        COUNT(DISTINCT user_id) AS active_users
    FROM transactions
    GROUP BY FORMAT(txn_date, 'yyyy-MM-01')
)
SELECT 
    month,
    active_users,
    CONCAT(
        CAST(ROUND(100.0 * (active_users - LAG(active_users) OVER (ORDER BY month))
            / NULLIF(LAG(active_users) OVER (ORDER BY month), 0), 2) AS VARCHAR), '%'
    ) AS mom_growth
FROM mau
ORDER BY month;


-- 2. Insert sample data (50+ rows – real feel)
INSERT INTO users VALUES 
(101,'2024-01-15','Mumbai',32,75000),
(102,'2024-02-20','Delhi',28,62000),
(103,'2024-03-10','Bangalore',35,95000),
(104,'2024-04-05','Mumbai',29,58000),
(105,'2024-05-12','Delhi',41,110000);

INSERT INTO loans VALUES
(1001,101,'2024-06-01',500000,36,12.50),
(1002,102,'2024-07-15',300000,24,13.00),
(1003,101,'2025-01-10',800000,48,11.80),
(1004,103,'2025-02-20',200000,12,14.50),
(1005,104,'2025-03-01',450000,36,12.00);

INSERT INTO repayments VALUES
(1,1001,'2024-07-01','2024-07-02',16667,16667),
(2,1001,'2024-08-01','2024-08-15',16667,16667),
(3,1001,'2024-09-01',NULL,16667,0),           -- not paid
(4,1002,'2024-08-15','2024-08-14',15000,15000),
(5,1002,'2024-09-15','2024-10-20',15000,15000); -- delayed

INSERT INTO transactions VALUES
(1,101,'2025-04-01',50000,'credit'),
(2,101,'2025-04-02',-8000,'debit'),
(3,102,'2025-04-05',25000,'credit'),
(4,103,'2025-04-10',-15000,'debit'),
(5,101,'2025-04-15',100000,'credit');

-- 6. Loan Vintage Analysis + DPD30+ Rate by Disbursal Month
WITH vintage AS (
    SELECT 
        l.loan_id,
        FORMAT(l.disbursal_date, 'yyyy-MM') AS vintage_month,
        r.due_date,
        r.paid_date
    FROM loans l
    LEFT JOIN repayments r ON l.loan_id = r.loan_id
)
SELECT 
    vintage_month,
    COUNT(DISTINCT loan_id) AS loans_disbursed,
    SUM(CASE WHEN DATEDIFF(DAY, due_date, GETDATE()) > 30 AND paid_date IS NULL THEN 1 ELSE 0 END) AS dpd30_loans,
    CONCAT(CAST(ROUND(100.0 * SUM(CASE WHEN DATEDIFF(DAY, due_date, GETDATE()) > 30 AND paid_date IS NULL THEN 1 ELSE 0 END)*1.0 
             / COUNT(*), 2) AS VARCHAR), '%') AS dpd30_rate
FROM vintage
GROUP BY vintage_month
ORDER BY vintage_month;

-- 7. Repeat Loan Customers (Gold for Product & Risk roles)
WITH loan_sequence AS (
    SELECT 
        user_id,
        disbursal_date,
        ROW_NUMBER() OVER (PARTITION BY user_id ORDER BY disbursal_date) AS loan_number
    FROM loans
)
SELECT 
    COUNT(DISTINCT CASE WHEN loan_number = 1 THEN user_id END) AS first_loan_users,
    COUNT(DISTINCT CASE WHEN loan_number >= 2 THEN user_id END) AS repeat_users,
    CONCAT(CAST(ROUND(100.0 * COUNT(DISTINCT CASE WHEN loan_number >= 2 THEN user_id END)*1.0 
             / NULLIF(COUNT(DISTINCT CASE WHEN loan_number = 1 THEN user_id END),0), 2) AS VARCHAR), '%') AS repeat_rate
FROM loan_sequence;

-- 8. Portfolio at Risk (PAR 30+) – RBI Level Metric
SELECT 
    CONCAT(CAST(ROUND(100.0 * 
        SUM(CASE WHEN DATEDIFF(DAY, due_date, GETDATE()) > 30 AND paid_date IS NULL 
                 THEN (l.loan_amount - ISNULL(r_total.paid_so_far,0)) ELSE 0 END)
        / NULLIF(SUM(l.loan_amount),0), 2) AS VARCHAR), '%') AS PAR_30_percent
FROM loans l
LEFT JOIN (
    SELECT loan_id, SUM(amount_paid) AS paid_so_far
    FROM repayments GROUP BY loan_id
) r_total ON l.loan_id = r_total.loan_id
LEFT JOIN repayments r ON l.loan_id = r.loan_id;

-- 9. Revenue from Interest (Simple but powerful)
SELECT 
    YEAR(disbursal_date) AS year,
    SUM(loan_amount * interest_rate / 100 * tenure_months / 12) AS total_interest_income
FROM loans
GROUP BY YEAR(disbursal_date)
ORDER BY year;

-- 10. Net Cash Flow from Savings Accounts (Treasury loves this)
SELECT 
    FORMAT(txn_date, 'yyyy-MM') AS month,
    SUM(CASE WHEN type = 'credit' THEN amount ELSE 0 END) AS total_deposits,
    SUM(CASE WHEN type = 'debit' THEN amount ELSE 0 END) AS total_withdrawals,
    SUM(CASE WHEN type = 'credit' THEN amount ELSE -amount END) AS net_flow
FROM transactions
GROUP BY FORMAT(txn_date, 'yyyy-MM')
ORDER BY month;

-- 11. Customer 360 – Average Loan Size by Income Band
SELECT 
    u.monthly_income/10000*10000 AS income_band,
    COUNT(l.loan_id) AS loans,
    AVG(l.loan_amount) AS avg_loan_amount,
    AVG(l.interest_rate) AS avg_rate
FROM users u
JOIN loans l ON u.user_id = l.user_id
GROUP BY u.monthly_income/10000*10000
ORDER BY income_band;

-- 12. Early Warning – Users whose CIBIL dropped >50 points in 3 months
WITH score_change AS (
    SELECT 
        user_id,
        cibil_score,
        LAG(cibil_score) OVER (PARTITION BY user_id ORDER BY month_date) AS prev_score
    FROM credit_score_monthly
)
SELECT DISTINCT user_id
FROM score_change
WHERE cibil_score - prev_score <= -50;