-- الجزء 1: إغلاق جميع الاتصالات وحذف قاعدة البيانات إذا كانت موجودة
USE master;
GO

IF DB_ID('Sales') IS NOT NULL
BEGIN
    -- إجبار جميع الجلسات على الخروج
    DECLARE @kill varchar(8000) = '';
    SELECT @kill = @kill + 'kill ' + CONVERT(varchar(5), session_id) + ';'
    FROM sys.dm_exec_sessions
    WHERE database_id = DB_ID('Sales');
    
    EXEC(@kill);
    
    -- حذف قاعدة البيانات بعد التأكد من عدم وجود اتصالات
    ALTER DATABASE Sales SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE Sales;
END
GO

-- إنشاء قاعدة البيانات جديدة
CREATE DATABASE Sales
ON PRIMARY 
(
    NAME = 'Sales_Data',
    FILENAME = 'C:\Data\Sales.mdf',
    SIZE = 100MB,
    MAXSIZE = UNLIMITED,
    FILEGROWTH = 10%
)
LOG ON
(
    NAME = 'Sales_Log',
    FILENAME = 'C:\Data\Sales.ldf',
    SIZE = 50MB,
    MAXSIZE = 1GB,
    FILEGROWTH = 5%
);
GO

USE Sales;
GO

-- الجزء 2: إنشاء الجداول مع التحقق من وجودها أولاً
-- جدول العملاء
IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'customers')
BEGIN
    CREATE TABLE customers (
        customer_id INT PRIMARY KEY IDENTITY(1,1),
        first_name NVARCHAR(50) NOT NULL,
        last_name NVARCHAR(50) NOT NULL,
        phone NVARCHAR(25) CHECK (phone LIKE '+[0-9]%'),
        email NVARCHAR(255) NOT NULL UNIQUE CHECK (email LIKE '%_@__%.__%'),
        street NVARCHAR(255),
        city NVARCHAR(50),
        state NVARCHAR(25),
        zip_code NVARCHAR(5),
        registration_date DATETIME DEFAULT GETDATE(),
        CONSTRAINT UQ_Customer_Phone UNIQUE (phone)
    );
    PRINT 'تم إنشاء جدول customers بنجاح';
END
ELSE
    PRINT 'جدول customers موجود بالفعل';
GO

-- جدول المتاجر
IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'stores')
BEGIN
    CREATE TABLE stores (
        store_id INT PRIMARY KEY IDENTITY(1,1),
        store_name NVARCHAR(255) NOT NULL,
        phone NVARCHAR(25) CHECK (phone LIKE '+[0-9]%'),
        email NVARCHAR(255) CHECK (email LIKE '%_@__%.__%'),
        street NVARCHAR(255),
        city NVARCHAR(50),
        state NVARCHAR(25),
        zip_code NVARCHAR(5),
        opening_date DATE,
        CONSTRAINT UQ_Store_Phone UNIQUE (phone),
        CONSTRAINT UQ_Store_Email UNIQUE (email)
    );
    PRINT 'تم إنشاء جدول stores بنجاح';
END
ELSE
    PRINT 'جدول stores موجود بالفعل';
GO

-- التحقق من وجود عمود opening_date قبل إضافة القيد
IF EXISTS (SELECT * FROM sys.tables WHERE name = 'stores')
AND EXISTS (SELECT * FROM sys.columns WHERE name = 'opening_date' AND object_id = OBJECT_ID('stores'))
BEGIN
    ALTER TABLE stores
    ADD CONSTRAINT CHK_OpeningDate CHECK (opening_date <= GETDATE());
    PRINT 'تم إضافة قيد CHK_OpeningDate بنجاح';
END
ELSE
    PRINT 'تعذر إضافة القيد: إما أن الجدول غير موجود أو العمود opening_date غير موجود';
GO

-- جدول الموظفين
IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'staffs')
BEGIN
    CREATE TABLE staffs (
        staff_id INT PRIMARY KEY IDENTITY(1,1),
        first_name NVARCHAR(50) NOT NULL,
        last_name NVARCHAR(50) NOT NULL,
        email NVARCHAR(255) NOT NULL UNIQUE CHECK (email LIKE '%_@__%.__%'),
        phone NVARCHAR(25) CHECK (phone LIKE '+[0-9]%'),
        hire_date DATE NOT NULL,
        salary DECIMAL(10,2) CHECK (salary > 0),
        store_id INT NOT NULL,
        manager_id INT,
        is_active BIT DEFAULT 1,
        CONSTRAINT FK_staff_store FOREIGN KEY (store_id) REFERENCES stores(store_id),
        CONSTRAINT FK_staff_manager FOREIGN KEY (manager_id) REFERENCES staffs(staff_id)
    );
    PRINT 'تم إنشاء جدول staffs بنجاح';
END
ELSE
    PRINT 'جدول staffs موجود بالفعل';
GO

-- جدول الطلبات
IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'orders')
BEGIN
    CREATE TABLE orders (
        order_id INT PRIMARY KEY IDENTITY(1,1),
        customer_id INT NOT NULL,
        order_status TINYINT NOT NULL DEFAULT 1,
        order_date DATETIME NOT NULL DEFAULT GETDATE(),
        required_date DATETIME NOT NULL,
        shipped_date DATETIME,
        store_id INT NOT NULL,
        staff_id INT NOT NULL,
        CONSTRAINT FK_order_customer FOREIGN KEY (customer_id) REFERENCES customers(customer_id),
        CONSTRAINT FK_order_store FOREIGN KEY (store_id) REFERENCES stores(store_id),
        CONSTRAINT FK_order_staff FOREIGN KEY (staff_id) REFERENCES staffs(staff_id),
        CONSTRAINT CHK_order_dates CHECK (required_date > order_date AND 
                                       (shipped_date IS NULL OR shipped_date >= order_date))
    );
    PRINT 'تم إنشاء جدول orders بنجاح';
    
    -- إنشاء الفهارس
    IF NOT EXISTS (SELECT * FROM sys.indexes WHERE name = 'IX_orders_customer_id')
        CREATE INDEX IX_orders_customer_id ON orders(customer_id);
    
    IF NOT EXISTS (SELECT * FROM sys.indexes WHERE name = 'IX_orders_order_date')
        CREATE INDEX IX_orders_order_date ON orders(order_date);
END
ELSE
    PRINT 'جدول orders موجود بالفعل';
GO

-- عرض بنية الجداول
EXEC sp_help 'customers';
EXEC sp_help 'stores';
EXEC sp_help 'staffs';
EXEC sp_help 'orders';
GO
/*
  ملف استعلامات JOIN لقاعدة بيانات Sales
  تم الإنشاء في: 2023-11-20
*/

-------------------------------------------
-- 1. العملاء الأساسيون
-------------------------------------------
SELECT 
    customer_id,
    first_name + ' ' + last_name AS customer_name,
    email,
    phone
FROM 
    customers
WHERE 
    registration_date >= '2023-01-01'; -- العملاء المسجلون منذ بداية 2023

-------------------------------------------
-- 2. العملاء مع طلباتهم
-------------------------------------------
SELECT 
    c.customer_id,
    c.first_name + ' ' + c.last_name AS customer_name,
    o.order_id,
    o.order_date,
    o.order_status
FROM 
    customers c
INNER JOIN 
    orders o ON c.customer_id = o.customer_id
WHERE 
    o.order_status = 1 -- الطلبات النشطة فقط
ORDER BY 
    o.order_date DESC;

-------------------------------------------
-- 3. الطلبات مع معلومات المتجر والموظف
-------------------------------------------
SELECT 
    o.order_id,
    FORMAT(o.order_date, 'yyyy-MM-dd') AS order_date,
    s.store_name,
    st.first_name + ' ' + st.last_name AS staff_name,
    c.first_name + ' ' + c.last_name AS customer_name
FROM 
    orders o
INNER JOIN 
    stores s ON o.store_id = s.store_id
INNER JOIN 
    staffs st ON o.staff_id = st.staff_id
INNER JOIN 
    customers c ON o.customer_id = c.customer_id
WHERE 
    o.shipped_date IS NULL -- الطلبات التي لم يتم شحنها بعد
ORDER BY 
    o.order_date;

-------------------------------------------
-- 4. تحليل المبيعات حسب المتجر
-------------------------------------------
SELECT 
    s.store_id,
    s.store_name,
    COUNT(o.order_id) AS total_orders,
    SUM(CASE WHEN o.order_status = 1 THEN 1 ELSE 0 END) AS active_orders,
    SUM(CASE WHEN o.shipped_date IS NULL THEN 1 ELSE 0 END) AS unshipped_orders
FROM 
    stores s
LEFT JOIN 
    orders o ON s.store_id = o.store_id
GROUP BY 
    s.store_id, s.store_name
ORDER BY 
    total_orders DESC;

-------------------------------------------
-- 5. أداء الموظفين
-------------------------------------------
SELECT 
    st.staff_id,
    st.first_name + ' ' + st.last_name AS staff_name,
    s.store_name,
    COUNT(o.order_id) AS orders_handled,
    AVG(DATEDIFF(day, o.order_date, ISNULL(o.shipped_date, GETDATE()))) AS avg_shipping_time
FROM 
    staffs st
INNER JOIN 
    stores s ON st.store_id = s.store_id
LEFT JOIN 
    orders o ON st.staff_id = o.staff_id
WHERE 
    st.is_active = 1 -- الموظفون النشطون فقط
GROUP BY 
    st.staff_id, st.first_name, st.last_name, s.store_name
ORDER BY 
    orders_handled DESC;
