-- Create customers table
CREATE TABLE IF NOT EXISTS customers (
    id SERIAL PRIMARY KEY,
    name TEXT NOT NULL,
    email CITEXT UNIQUE,
    phone TEXT,
    created_at TIMESTAMP DEFAULT NOW()
);

-- Create invoices table
CREATE TABLE IF NOT EXISTS invoices (
    id SERIAL PRIMARY KEY,
    customer_id INT REFERENCES customers(id),
    amount NUMERIC(12,2) NOT NULL,
    due_date DATE,
    status TEXT DEFAULT 'Draft',
    created_at TIMESTAMP DEFAULT NOW()
);

-- Create payments table
CREATE TABLE IF NOT EXISTS payments (
    id SERIAL PRIMARY KEY,
    invoice_id INT REFERENCES invoices(id),
    amount NUMERIC(12,2) NOT NULL,
    paid_at TIMESTAMP DEFAULT NOW()
);

