## Business Logic

### Overview

The Business Logic layer implements the core business rules and data operations of the database system. It is implemented using **User-Defined Functions (UDFs), Stored Procedures, and Triggers** in Microsoft SQL Server.

These database objects help ensure data consistency, validate business rules, manage inventory operations, and maintain the integrity of transactions.

### 1. User-Defined Functions (UDFs)

The project includes the following user-defined functions:

| Function | Description |
|---|---|
| `fn_CalculateChargeableWeight` | Calculates the chargeable weight by comparing the actual weight with the volumetric weight. |
| `fn_GetOrderTotal` | Calculates the total value of an order based on the ordered quantities and unit prices in `ORDER_DETAIL`. |
| `fn_GetAvailableStock` | Retrieves inventory lots that are available, intact, and have a positive available quantity for a specified product and warehouse. |

### 2. Stored Procedures

Stored procedures handle business operations and enforce validation rules.

| Stored Procedure | Description |
|---|---|
| `sp_UpsertSalesOrder` | Creates a new sales order or updates an existing order based on the sales channel and external order ID. |
| `sp_CreateFulfillmentOrder` | Creates a fulfillment order for an unallocated sales order and an active warehouse. |
| `sp_AllocateInventoryLot` | Allocates inventory from an eligible lot, validates the requested quantity, and updates the available stock. |
| `sp_SelectShippingQuote` | Selects a shipping quote belonging to the specified package. |
| `sp_ProcessReturn` | Processes returned products, records their disposition, and updates inventory quantities when products are restocked. |

Transactions are used in the procedures that perform multiple related data modifications to help maintain data consistency when errors occur.

### 3. Database Triggers

Triggers automatically enforce business rules when relevant data is inserted or updated.

| Trigger | Description |
|---|---|
| `TRG_BatchAssignment_SameWarehouse` | Ensures fulfillment orders assigned to the same picking batch belong to the same warehouse. |
| `TRG_ConsolidationAssignment_ValidateGroup` | Validates customer consent and ensures that orders in a consolidation group have consistent warehouse, customer, and delivery address information. |
| `TRG_PackedAllocation_NotExceedPicked` | Prevents the packed quantity from exceeding the picked quantity for an inventory allocation. |
| `TRG_LotAllocation_ProtectPickedQuantity` | Prevents an inventory allocation's picked quantity from being reduced below the quantity already packed. |

When a business rule is violated, the corresponding trigger raises an error and rolls back the invalid operation.

### 4. Business Logic Testing

Business logic can be tested using SQL scripts in SQL Server Management Studio (SSMS).

The tests should cover:

- **Valid scenarios:** Confirm that functions return the expected results and stored procedures execute successfully.
- **Invalid scenarios:** Verify that invalid quantities, unavailable inventory, inactive warehouses, and inconsistent assignments are rejected.
- **Data integrity:** Check that inventory quantities and related records remain consistent after database operations.
- **Transaction handling:** Verify that failed operations do not leave partial changes behind.

Example test cases:

| Test Case | Expected Result |
|---|---|
| Calculate chargeable weight using valid inputs | Returns the greater of actual and volumetric weight. |
| Calculate an order's total value | Returns the sum of ordered quantity multiplied by unit price. |
| Retrieve available inventory | Returns only eligible inventory lots. |
| Allocate more inventory than is available | Rejects the allocation. |
| Assign orders from different warehouses to the same picking batch | Rejects the invalid assignment. |
| Pack more units than have been picked | Rejects the invalid packing quantity. |

### 5. Continuous Integration (CI)

GitHub Actions can be configured to execute SQL business logic tests automatically whenever changes are pushed to the repository or a pull request is created.

A CI workflow should:

1. Set up a SQL Server test environment.
2. Create the database schema and insert test data.
3. Deploy the functions, stored procedures, and triggers.
4. Execute the business logic test scripts.
5. Report the workflow as successful or failed based on the test results.

**Note:** Automated SQL testing requires a configured SQL Server environment and test scripts that explicitly validate expected results. A successful SQL script execution alone does not guarantee that all business rules are correct.
