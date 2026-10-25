/*
  Report 5 - pre-submission smoke test
  Prerequisites: Report 1-4 schema, sample data, and R5_BusinessLogic.sql.
  The procedure test is rolled back, so it does not keep test data.
*/
USE OmnichannelFulfillmentDB;
GO

/* 1. Confirm that all Report 5 objects were created. */
SELECT o.type_desc, SCHEMA_NAME(o.schema_id) AS SchemaName, o.name AS ObjectName
FROM sys.objects o
WHERE o.name IN
(
    'fn_CalculateChargeableWeight', 'fn_GetOrderTotal', 'fn_GetAvailableStock',
    'sp_UpsertSalesOrder', 'sp_CreateFulfillmentOrder', 'sp_AllocateInventoryLot',
    'sp_SelectShippingQuote', 'sp_ProcessReturn',
    'TRG_BatchAssignment_SameWarehouse', 'TRG_ConsolidationAssignment_ValidateGroup',
    'TRG_PackedAllocation_NotExceedPicked', 'TRG_LotAllocation_ProtectPickedQuantity'
)
ORDER BY o.type_desc, o.name;
GO

/* 2. Function tests: each query must return a valid result grid. */
SELECT dbo.fn_CalculateChargeableWeight(1.20, 30, 20, 15, 5000) AS ChargeableWeight;
SELECT TOP (5) so.OrderID, dbo.fn_GetOrderTotal(so.OrderID) AS CalculatedTotal
FROM SALES_ORDER so ORDER BY so.OrderID;
SELECT TOP (5) * FROM dbo.fn_GetAvailableStock(1, 1);
GO

/*
  3. Procedure transaction test. All inserted/updated data is removed by the
  final ROLLBACK. The SELECT result grids are proof of successful execution.
*/
SET XACT_ABORT ON;
BEGIN TRY
    BEGIN TRANSACTION;

    DECLARE @ChannelID INT = (SELECT TOP (1) ChannelID FROM SALES_CHANNEL WHERE ChannelStatus = 'Active' ORDER BY ChannelID);
    DECLARE @CustomerID INT = (SELECT TOP (1) CustomerID FROM CUSTOMER ORDER BY CustomerID);
    DECLARE @LotID INT, @ProductID INT, @WarehouseID INT;
    SELECT TOP (1) @LotID = il.InventoryLotID, @ProductID = il.ProductID, @WarehouseID = il.WarehouseID
    FROM INVENTORY_LOT il JOIN WAREHOUSE w ON w.WarehouseID = il.WarehouseID
    WHERE il.InventoryStatus = 'Available' AND il.ConditionStatus = 'Intact'
      AND il.AvailableQuantity >= 2 AND w.WarehouseStatus = 'Active'
    ORDER BY il.InventoryLotID;

    DECLARE @OrderID INT, @FulfillmentOrderID INT;
    EXEC dbo.sp_UpsertSalesOrder
        @ChannelID, @CustomerID, 'R5-TEST-DO-NOT-COMMIT', 'Pending', SYSDATETIME(), 1,
        N'Test address', N'Test customer', '0900000000', 100000, @OrderID OUTPUT;
    INSERT INTO ORDER_DETAIL (OrderID, ProductID, OrderedQuantity, UnitPrice)
    VALUES (@OrderID, @ProductID, 1, 100000);
    EXEC dbo.sp_CreateFulfillmentOrder @OrderID, @WarehouseID, 1, @FulfillmentOrderID OUTPUT;
    EXEC dbo.sp_AllocateInventoryLot @FulfillmentOrderID, @LotID, 1;

    SELECT so.OrderID, so.InternalStatus, fo.FulfillmentStatus, fla.AllocatedQuantity,
           il.AvailableQuantity AS AvailableAfterAllocation
    FROM SALES_ORDER so
    JOIN FULFILLMENT_ORDER fo ON fo.OrderID = so.OrderID
    JOIN FULFILLMENT_LOT_ALLOCATION fla ON fla.FulfillmentOrderID = fo.FulfillmentOrderID
    JOIN INVENTORY_LOT il ON il.InventoryLotID = fla.InventoryLotID
    WHERE so.OrderID = @OrderID;

    ROLLBACK TRANSACTION;
    PRINT 'PASS: Procedure test completed and was rolled back.';
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
    THROW;
END CATCH;
GO

/*
  4. Trigger test. This INSERT must fail because CustomerConsent = 0.
  Seeing ExpectedTriggerError is a PASS; the rollback keeps sample data intact.
*/
BEGIN TRY
    BEGIN TRANSACTION;
    DECLARE @ExistingFulfillmentID INT =
        (SELECT TOP (1) fo.FulfillmentOrderID FROM FULFILLMENT_ORDER fo
         WHERE NOT EXISTS (SELECT 1 FROM CONSOLIDATION_ASSIGNMENT ca
                           WHERE ca.FulfillmentOrderID = fo.FulfillmentOrderID)
         ORDER BY fo.FulfillmentOrderID);
    DECLARE @TestGroupID INT;
    INSERT INTO CONSOLIDATION_GROUP (CustomerConsent, GroupStatus, CreatedAt)
    VALUES (0, 'Forming', SYSDATETIME());
    SET @TestGroupID = CONVERT(INT, SCOPE_IDENTITY());
    INSERT INTO CONSOLIDATION_ASSIGNMENT (FulfillmentOrderID, ConsolidationGroupID)
    VALUES (@ExistingFulfillmentID, @TestGroupID);
    COMMIT TRANSACTION;
    THROW 52001, 'Trigger test unexpectedly succeeded.', 1;
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
    IF ERROR_NUMBER() = 51102
        SELECT ERROR_MESSAGE() AS ExpectedTriggerError;
    ELSE
        THROW;
END CATCH;
GO
