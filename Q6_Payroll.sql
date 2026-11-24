DROP SCHEMA IF EXISTS q6_payroll CASCADE;
CREATE SCHEMA q6_payroll;
SET search_path TO q6_payroll, public;

CREATE TABLE employees(
 employee_id SERIAL PRIMARY KEY,full_name VARCHAR(120) NOT NULL,
 basic_salary NUMERIC(12,2) NOT NULL CHECK(basic_salary>=0),
 allowance NUMERIC(12,2) NOT NULL CHECK(allowance>=0),
 deduction NUMERIC(12,2) NOT NULL CHECK(deduction>=0),active BOOLEAN NOT NULL
);
CREATE TABLE payroll(
 payroll_id SERIAL PRIMARY KEY,employee_id INTEGER NOT NULL REFERENCES employees(employee_id),
 pay_month DATE NOT NULL CHECK(EXTRACT(DAY FROM pay_month)=1),
 gross_pay NUMERIC(12,2) NOT NULL,net_pay NUMERIC(12,2) NOT NULL,
 UNIQUE(employee_id,pay_month)
);
CREATE TABLE salary_audit(
 audit_id SERIAL PRIMARY KEY,employee_id INTEGER NOT NULL REFERENCES employees(employee_id),
 old_salary NUMERIC(12,2) NOT NULL,new_salary NUMERIC(12,2) NOT NULL,
 changed_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE OR REPLACE FUNCTION fn_net_pay(p_employee_id INTEGER)
RETURNS NUMERIC(12,2) LANGUAGE plpgsql AS $$
DECLARE v_basic NUMERIC(12,2); v_allowance NUMERIC(12,2); v_deduction NUMERIC(12,2); v_net NUMERIC(12,2);
BEGIN
 SELECT basic_salary,allowance,deduction INTO v_basic,v_allowance,v_deduction
 FROM employees WHERE employee_id=p_employee_id;
 IF NOT FOUND THEN RAISE EXCEPTION 'Unknown employee'; END IF;
 v_net:=v_basic+v_allowance-v_deduction;
 IF v_net<0 THEN RAISE EXCEPTION 'Computed net pay cannot be negative'; END IF;
 RETURN v_net;
END; $$;

CREATE OR REPLACE PROCEDURE pr_process_payroll(p_month DATE)
LANGUAGE plpgsql AS $$
DECLARE r RECORD; v_gross NUMERIC(12,2); v_net NUMERIC(12,2);
BEGIN
 IF p_month IS NULL OR EXTRACT(DAY FROM p_month)<>1 THEN RAISE EXCEPTION 'Pay month must be the first day of a month'; END IF;
 FOR r IN SELECT employee_id,basic_salary,allowance FROM employees WHERE active LOOP
  v_net:=fn_net_pay(r.employee_id);
  v_gross:=r.basic_salary+r.allowance;
  INSERT INTO payroll(employee_id,pay_month,gross_pay,net_pay)
  VALUES(r.employee_id,p_month,v_gross,v_net)
  ON CONFLICT(employee_id,pay_month) DO NOTHING;
 END LOOP;
END; $$;

CREATE OR REPLACE FUNCTION trg_fn_salary_audit()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
 IF OLD.basic_salary IS DISTINCT FROM NEW.basic_salary THEN
  INSERT INTO salary_audit(employee_id,old_salary,new_salary)
  VALUES(NEW.employee_id,OLD.basic_salary,NEW.basic_salary);
 END IF;
 RETURN NEW;
END; $$;
CREATE TRIGGER trg_salary_audit AFTER UPDATE ON employees
FOR EACH ROW EXECUTE FUNCTION trg_fn_salary_audit();

INSERT INTO employees(full_name,basic_salary,allowance,deduction,active) VALUES
('Alice Banda',5000,500,300,true),('Brian Phiri',6500,700,500,true),
('Chanda Zulu',4000,300,200,true),('David Tembo',5500,400,350,false);
CALL pr_process_payroll(DATE_TRUNC('month',CURRENT_DATE)::DATE);
CALL pr_process_payroll((DATE_TRUNC('month',CURRENT_DATE)-INTERVAL '1 month')::DATE);

CREATE OR REPLACE VIEW v_payroll_report AS
SELECT e.full_name,p.pay_month,p.gross_pay,p.net_pay
FROM payroll p JOIN employees e ON e.employee_id=p.employee_id;

CREATE INDEX idx_payroll_pay_month ON payroll(pay_month);
EXPLAIN SELECT * FROM payroll WHERE pay_month=DATE_TRUNC('month',CURRENT_DATE)::DATE;

CREATE EXTENSION IF NOT EXISTS pg_cron;
SELECT cron.schedule('q6-monthly-payroll','0 2 1 * *',
 'CALL q6_payroll.pr_process_payroll((DATE_TRUNC(''month'',CURRENT_DATE)-INTERVAL ''1 month'')::DATE)');
SELECT * FROM v_payroll_report;
SELECT * FROM salary_audit;
