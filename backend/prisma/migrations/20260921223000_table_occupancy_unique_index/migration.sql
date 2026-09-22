-- Create partial unique index on Order(tenantId, tableId) for active (non-closed/canceled) orders
CREATE UNIQUE INDEX IF NOT EXISTS "Order_tenantId_tableId_active_unique"
ON "Order"("tenantId", "tableId")
WHERE "tableId" IS NOT NULL AND "status" NOT IN ('closed', 'canceled');
