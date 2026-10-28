/*
    Report 5 - SQL Server CI Smoke Tests
    Database: OmnichannelFulfillmentDB

    Prerequisites:
      1. Report 1-4 schema and sample data have been deployed.
      2. R5_BusinessLogic.sql has been executed.
      3. The required sample data exists for the procedure/trigger tests.

    CI usage:
      sqlcmd -S ... -d OmnichannelFulfillmentDB -b -i "DBI202_SE2005_Group5_R5_Test.sql"

    Notes:
      - THROW statements make failed assertions return SQL errors.
      - The procedure smoke test runs in a transaction and rolls back its data changes.
      - The trigger test expects error 51102 when CustomerConsent = 0.
*/

USE OmnichannelFulfillmentDB;
GO

SET NOCOUNT ON;
GO

/* ============================================================
   0. Verify required tables exist
   ============================================================ */
IF OBJECT_ID(N'dbo.CUSTOMER', N'U') IS NULL
   OR OBJECT_ID(N'dbo.SALES_CHANNEL', N'U') IS NULL
   OR OBJECT_ID(N'dbo.SALES_ORDER', N'U') IS NULL
   OR OBJECT_ID(N'dbo.ORDER_DETAIL', N'U') IS NULL
   OR OBJECT_ID(N'dbo.INVENTORY_LOT', N'U') IS NULL
   OR OBJECT_ID(N'dbo.WAREHOUSE', N'U') IS NULL
   OR OBJECT_ID(N'dbo.FULFILLMENT_ORDER', N'U') IS NULL
   OR OBJECT_ID(N'dbo.FULFILLMENT_LOT_ALLOCATION', N'U') IS NULL
   OR OBJECT_ID(N'dbo.CONSOLIDATION_GROUP', N'U') IS NULL
   OR OBJECT_ID(N'dbo.CONSOLIDATION_ASSIGNMENT', N'U') IS NULL
BEGIN
    THROW 52000, 'FAIL: One or more required tables are missing. Run the Academic Database script first.', 1;
END;
PRINT 'PASS: Required tables exist.';
GO

/* ============================================================
   1. Verify all required Report 5 objects exist
   ============================================================ */
DECLARE @RequiredObjects TABLE
(
    ObjectName SYSNAME NOT NULL PRIMARY KEY
);

INSERT INTO @RequiredObjects (ObjectName)
VALUES
    (N'fn_CalculateChargeableWeight'),
    (N'fn_GetOrderTotal'),
    (N'fn_GetAvailableStock'),
    (N'sp_UpsertSalesOrder'),
    (N'sp_CreateFulfillmentOrder'),
    (N'sp_AllocateInventoryLot'),
    (N'sp_SelectShippingQuote'),
    (N'sp_ProcessReturn'),
    (N'TRG_BatchAssignment_SameWarehouse'),
    (N'TRG_ConsolidationAssignment_ValidateGroup'),
    (N'TRG_PackedAllocation_NotExceedPicked'),
    (N'TRG_LotAllocation_ProtectPickedQuantity');

IF EXISTS
(
    SELECT 1
    FROM @RequiredObjects AS r
    WHERE NOT EXISTS
    (
        SELECT 1
        FROM sys.objects AS o
        WHERE o.name = r.ObjectName
          AND SCHEMA_NAME(o.schema_id) = N'dbo'
    )
)
BEGIN
    SELECT r.ObjectName AS MissingObject
    FROM @RequiredObjects AS r
    WHERE NOT EXISTS
    (
        SELECT 1
        FROM sys.objects AS o
        WHERE o.name = r.ObjectName
          AND SCHEMA_NAME(o.schema_id) = N'dbo'
    );

    THROW 52001, 'FAIL: One or more required Report 5 objects are missing.', 1;
END;

PRINT 'PASS: All 12 required Report 5 objects exist.';
GO

/* ============================================================
   2. Function tests
   ============================================================ */

-- 2.1 Known calculation:
-- Actual weight = 1.20; volumetric weight = (30 * 20 * 15) / 5000 = 1.80.
DECLARE @ActualChargeableWeight DECIMAL(10,2);
SET @ActualChargeableWeight =
    dbo.fn_CalculateChargeableWeight(1.20, 30, 20, 15, 5000);

IF @ActualChargeableWeight IS NULL
   OR ABS(@ActualChargeableWeight - 1.80) > 0.01
BEGIN
    SELECT @ActualChargeableWeight AS ActualChargeableWeight,
           CAST(1.80 AS DECIMAL(10,2)) AS ExpectedChargeableWeight;
    THROW 52002, 'FAIL: fn_CalculateChargeableWeight returned an unexpected value.', 1;
END;

SELECT @ActualChargeableWeight AS ChargeableWeight;
PRINT 'PASS: fn_CalculateChargeableWeight.';
GO

-- 2.2 Compare fn_GetOrderTotal with the total calculated from ORDER_DETAIL.
IF EXISTS
(
    SELECT 1
    FROM dbo.SALES_ORDER AS so
    CROSS APPLY
    (
        SELECT CAST(COALESCE(SUM(od.OrderedQuantity * od.UnitPrice), 0) AS DECIMAL(12,2)) AS ExpectedTotal
        FROM dbo.ORDER_DETAIL AS od
        WHERE od.OrderID = so.OrderID
    ) AS totals
    WHERE dbo.fn_GetOrderTotal(so.OrderID) IS NULL
       OR ABS(dbo.fn_GetOrderTotal(so.OrderID) - totals.ExpectedTotal) > 0.01
)
BEGIN
    SELECT so.OrderID,
           dbo.fn_GetOrderTotal(so.OrderID) AS ActualTotal,
           totals.ExpectedTotal
    FROM dbo.SALES_ORDER AS so
    CROSS APPLY
    (
        SELECT CAST(COALESCE(SUM(od.OrderedQuantity * od.UnitPrice), 0) AS DECIMAL(12,2)) AS ExpectedTotal
        FROM dbo.ORDER_DETAIL AS od
        WHERE od.OrderID = so.OrderID
    ) AS totals
    WHERE dbo.fn_GetOrderTotal(so.OrderID) IS NULL
       OR ABS(dbo.fn_GetOrderTotal(so.OrderID) - totals.ExpectedTotal) > 0.01;

    THROW 52003, 'FAIL: fn_GetOrderTotal did not match ORDER_DETAIL totals.', 1;
END;

SELECT TOP (5)
       so.OrderID,
       dbo.fn_GetOrderTotal(so.OrderID) AS CalculatedTotal
FROM dbo.SALES_ORDER AS so
ORDER BY so.OrderID;

PRINT 'PASS: fn_GetOrderTotal matches ORDER_DETAIL.';
GO

-- 2.3 Validate fn_GetAvailableStock can be queried and returns only available stock.
DECLARE @StockProductID INT;
DECLARE @StockWarehouseID INT;

SELECT TOP (1)
       @StockProductID = il.ProductID,
       @StockWarehouseID = il.WarehouseID
FROM dbo.INVENTORY_LOT AS il
WHERE il.InventoryStatus = 'Available'
  AND il.ConditionStatus = 'Intact'
  AND il.AvailableQuantity > 0
ORDER BY il.InventoryLotID;

IF @StockProductID IS NULL OR @StockWarehouseID IS NULL
BEGIN
    THROW 52004, 'FAIL: No available intact inventory lot exists to test fn_GetAvailableStock.', 1;
END;

IF EXISTS
(
    SELECT 1
    FROM dbo.fn_GetAvailableStock(@StockProductID, @StockWarehouseID) AS s
    WHERE s.AvailableQuantity <= 0
)
BEGIN
    THROW 52005, 'FAIL: fn_GetAvailableStock returned a row with no available quantity.', 1;
END;

SELECT TOP (5) *
FROM dbo.fn_GetAvailableStock(@StockProductID, @StockWarehouseID);

PRINT 'PASS: fn_GetAvailableStock returned valid available-stock rows.';
GO

/* ============================================================
   3. Stored procedure smoke test
   Changes are rolled back after successful execution.
   ============================================================ */
SET XACT_ABORT ON;

BEGIN TRY
    BEGIN TRANSACTION;

    DECLARE @ChannelID INT =
    (
        SELECT TOP (1) ChannelID
        FROM dbo.SALES_CHANNEL
        WHERE ChannelStatus = 'Active'
        ORDER BY ChannelID
    );

    DECLARE @CustomerID INT =
    (
        SELECT TOP (1) CustomerID
        FROM dbo.CUSTOMER
        ORDER BY CustomerID
    );

    DECLARE @LotID INT;
    DECLARE @ProductID INT;
    DECLARE @WarehouseID INT;

    SELECT TOP (1)
           @LotID = il.InventoryLotID,
           @ProductID = il.ProductID,
           @WarehouseID = il.WarehouseID
    FROM dbo.INVENTORY_LOT AS il
    INNER JOIN dbo.WAREHOUSE AS w
        ON w.WarehouseID = il.WarehouseID
    WHERE il.InventoryStatus = 'Available'
      AND il.ConditionStatus = 'Intact'
      AND il.AvailableQuantity >= 2
      AND w.WarehouseStatus = 'Active'
    ORDER BY il.InventoryLotID;

    IF @ChannelID IS NULL
       OR @CustomerID IS NULL
       OR @LotID IS NULL
       OR @ProductID IS NULL
       OR @WarehouseID IS NULL
    BEGIN
        THROW 52011, 'FAIL: Required sample data for procedure test is missing.', 1;
    END;

    DECLARE @OrderID INT;
    DECLARE @FulfillmentOrderID INT;

    EXEC dbo.sp_UpsertSalesOrder
        @ChannelID,
        @CustomerID,
        'R5-TEST-DO-NOT-COMMIT',
        'Pending',
        SYSDATETIME(),
        1,
        N'Test address',
        N'Test customer',
        '0900000000',
        100000,
        @OrderID OUTPUT;

    IF @OrderID IS NULL
        THROW 52012, 'FAIL: sp_UpsertSalesOrder did not return an OrderID.', 1;

    INSERT INTO dbo.ORDER_DETAIL
        (OrderID, ProductID, OrderedQuantity, UnitPrice)
    VALUES
        (@OrderID, @ProductID, 1, 100000);

    EXEC dbo.sp_CreateFulfillmentOrder
        @OrderID, @WarehouseID, 1, @FulfillmentOrderID OUTPUT;

    IF @FulfillmentOrderID IS NULL
        THROW 52013, 'FAIL: sp_CreateFulfillmentOrder did not return a FulfillmentOrderID.', 1;

    EXEC dbo.sp_AllocateInventoryLot
        @FulfillmentOrderID, @LotID, 1;

    IF NOT EXISTS
    (
        SELECT 1
        FROM dbo.FULFILLMENT_LOT_ALLOCATION AS fla
        WHERE fla.FulfillmentOrderID = @FulfillmentOrderID
          AND fla.InventoryLotID = @LotID
          AND fla.AllocatedQuantity >= 1
    )
    BEGIN
        THROW 52014, 'FAIL: sp_AllocateInventoryLot did not create the expected allocation.', 1;
    END;

    SELECT so.OrderID,
           so.InternalStatus,
           fo.FulfillmentStatus,
           fla.AllocatedQuantity,
           il.AvailableQuantity AS AvailableAfterAllocation
    FROM dbo.SALES_ORDER AS so
    INNER JOIN dbo.FULFILLMENT_ORDER AS fo
        ON fo.OrderID = so.OrderID
    INNER JOIN dbo.FULFILLMENT_LOT_ALLOCATION AS fla
        ON fla.FulfillmentOrderID = fo.FulfillmentOrderID
    INNER JOIN dbo.INVENTORY_LOT AS il
        ON il.InventoryLotID = fla.InventoryLotID
    WHERE so.OrderID = @OrderID;

    ROLLBACK TRANSACTION;
    PRINT 'PASS: Procedure test completed and was rolled back.';
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0
        ROLLBACK TRANSACTION;
    THROW;
END CATCH;
GO

/* ============================================================
   4. Trigger test
   An assignment with CustomerConsent = 0 is expected to raise 51102.
   ============================================================ */
SET XACT_ABORT OFF;

DECLARE @ExistingFulfillmentID INT =
(
    SELECT TOP (1) fo.FulfillmentOrderID
    FROM dbo.FULFILLMENT_ORDER AS fo
    WHERE NOT EXISTS
    (
        SELECT 1
        FROM dbo.CONSOLIDATION_ASSIGNMENT AS ca
        WHERE ca.FulfillmentOrderID = fo.FulfillmentOrderID
    )
    ORDER BY fo.FulfillmentOrderID
);

IF @ExistingFulfillmentID IS NULL
BEGIN
    THROW 52020, 'FAIL: No unassigned fulfillment order is available for the trigger test.', 1;
END;

DECLARE @TriggerErrorCaught BIT = 0;

BEGIN TRY
    BEGIN TRANSACTION;

    DECLARE @TestGroupID INT;

    INSERT INTO dbo.CONSOLIDATION_GROUP
        (CustomerConsent, GroupStatus, CreatedAt)
    VALUES
        (0, 'Forming', SYSDATETIME());

    SET @TestGroupID = CONVERT(INT, SCOPE_IDENTITY());

    INSERT INTO dbo.CONSOLIDATION_ASSIGNMENT
        (FulfillmentOrderID, ConsolidationGroupID)
    VALUES
        (@ExistingFulfillmentID, @TestGroupID);

    -- If the trigger did not reject the assignment, this is a test failure.
    ROLLBACK TRANSACTION;
    THROW 52021, 'FAIL: Trigger test unexpectedly succeeded; expected error 51102.', 1;
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0
        ROLLBACK TRANSACTION;

    IF ERROR_NUMBER() = 51102
    BEGIN
        SET @TriggerErrorCaught = 1;
        SELECT ERROR_MESSAGE() AS ExpectedTriggerError;
    END
    ELSE
    BEGIN
        THROW;
    END;
END CATCH;

IF @TriggerErrorCaught = 0
BEGIN
    THROW 52022, 'FAIL: Expected trigger error 51102 was not caught.', 1;
END;

PRINT 'PASS: Trigger correctly rejected consolidation without customer consent.';
GO

PRINT 'PASS: All SQL smoke tests completed successfully.';
GO
