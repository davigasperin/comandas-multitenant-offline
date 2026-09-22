-- CreateTable
CREATE TABLE "Supplier" (
    "id" TEXT NOT NULL PRIMARY KEY,
    "tenantId" TEXT NOT NULL,
    "name" TEXT NOT NULL,
    "trade_name" TEXT,
    "document" TEXT,
    "phone" TEXT,
    "email" TEXT,
    "notes" TEXT,
    "active" BOOLEAN NOT NULL DEFAULT true,
    "createdAt" DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" DATETIME NOT NULL,
    CONSTRAINT "Supplier_tenantId_fkey" FOREIGN KEY ("tenantId") REFERENCES "Tenant" ("id") ON DELETE CASCADE ON UPDATE CASCADE
);

-- CreateTable
CREATE TABLE "Purchase" (
    "id" TEXT NOT NULL PRIMARY KEY,
    "tenantId" TEXT NOT NULL,
    "supplierId" TEXT,
    "document_no" TEXT,
    "status" TEXT NOT NULL DEFAULT 'draft',
    "purchased_at" DATETIME NOT NULL,
    "total_cents" INTEGER NOT NULL DEFAULT 0,
    "notes" TEXT,
    "created_by" TEXT,
    "confirmed_at" DATETIME,
    "payableExpenseId" TEXT,
    "createdAt" DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" DATETIME NOT NULL,
    CONSTRAINT "Purchase_tenantId_fkey" FOREIGN KEY ("tenantId") REFERENCES "Tenant" ("id") ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT "Purchase_supplierId_fkey" FOREIGN KEY ("supplierId") REFERENCES "Supplier" ("id") ON DELETE SET NULL ON UPDATE CASCADE,
    CONSTRAINT "Purchase_payableExpenseId_fkey" FOREIGN KEY ("payableExpenseId") REFERENCES "PayableExpense" ("id") ON DELETE SET NULL ON UPDATE CASCADE
);

-- CreateTable
CREATE TABLE "PurchaseItem" (
    "id" TEXT NOT NULL PRIMARY KEY,
    "purchaseId" TEXT NOT NULL,
    "productId" TEXT NOT NULL,
    "quantity" DECIMAL NOT NULL,
    "unit_cost_cents" INTEGER NOT NULL,
    "total_cents" INTEGER NOT NULL,
    CONSTRAINT "PurchaseItem_purchaseId_fkey" FOREIGN KEY ("purchaseId") REFERENCES "Purchase" ("id") ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT "PurchaseItem_productId_fkey" FOREIGN KEY ("productId") REFERENCES "Product" ("id") ON DELETE RESTRICT ON UPDATE CASCADE
);

-- CreateTable
CREATE TABLE "StockMovement" (
    "id" TEXT NOT NULL PRIMARY KEY,
    "tenantId" TEXT NOT NULL,
    "productId" TEXT NOT NULL,
    "type" TEXT NOT NULL,
    "quantity" DECIMAL NOT NULL,
    "unit_cost_cents" INTEGER,
    "reference_type" TEXT,
    "reference_id" TEXT,
    "notes" TEXT,
    "created_by" TEXT,
    "occurred_at" DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT "StockMovement_tenantId_fkey" FOREIGN KEY ("tenantId") REFERENCES "Tenant" ("id") ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT "StockMovement_productId_fkey" FOREIGN KEY ("productId") REFERENCES "Product" ("id") ON DELETE RESTRICT ON UPDATE CASCADE
);

-- CreateTable
CREATE TABLE "ExpenseCategory" (
    "id" TEXT NOT NULL PRIMARY KEY,
    "tenantId" TEXT NOT NULL,
    "name" TEXT NOT NULL,
    "active" BOOLEAN NOT NULL DEFAULT true,
    "createdAt" DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" DATETIME NOT NULL,
    CONSTRAINT "ExpenseCategory_tenantId_fkey" FOREIGN KEY ("tenantId") REFERENCES "Tenant" ("id") ON DELETE CASCADE ON UPDATE CASCADE
);

-- CreateTable
CREATE TABLE "PayableExpense" (
    "id" TEXT NOT NULL PRIMARY KEY,
    "tenantId" TEXT NOT NULL,
    "supplierId" TEXT,
    "categoryId" TEXT NOT NULL,
    "recurringTemplateId" TEXT,
    "description" TEXT NOT NULL,
    "amount_cents" INTEGER NOT NULL,
    "due_date" DATETIME NOT NULL,
    "competence_date" DATETIME NOT NULL,
    "notes" TEXT,
    "canceled_at" DATETIME,
    "created_by" TEXT,
    "createdAt" DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" DATETIME NOT NULL,
    CONSTRAINT "PayableExpense_tenantId_fkey" FOREIGN KEY ("tenantId") REFERENCES "Tenant" ("id") ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT "PayableExpense_supplierId_fkey" FOREIGN KEY ("supplierId") REFERENCES "Supplier" ("id") ON DELETE SET NULL ON UPDATE CASCADE,
    CONSTRAINT "PayableExpense_categoryId_fkey" FOREIGN KEY ("categoryId") REFERENCES "ExpenseCategory" ("id") ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT "PayableExpense_recurringTemplateId_fkey" FOREIGN KEY ("recurringTemplateId") REFERENCES "RecurringExpenseTemplate" ("id") ON DELETE SET NULL ON UPDATE CASCADE
);

-- CreateTable
CREATE TABLE "ExpensePayment" (
    "id" TEXT NOT NULL PRIMARY KEY,
    "expenseId" TEXT NOT NULL,
    "amount_cents" INTEGER NOT NULL,
    "paid_at" DATETIME NOT NULL,
    "payment_method" TEXT,
    "notes" TEXT,
    "created_by" TEXT,
    "createdAt" DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT "ExpensePayment_expenseId_fkey" FOREIGN KEY ("expenseId") REFERENCES "PayableExpense" ("id") ON DELETE CASCADE ON UPDATE CASCADE
);

-- CreateTable
CREATE TABLE "RecurringExpenseTemplate" (
    "id" TEXT NOT NULL PRIMARY KEY,
    "tenantId" TEXT NOT NULL,
    "categoryId" TEXT NOT NULL,
    "supplierId" TEXT,
    "description" TEXT NOT NULL,
    "amount_cents" INTEGER NOT NULL,
    "due_day" INTEGER NOT NULL,
    "start_date" DATETIME NOT NULL,
    "end_date" DATETIME,
    "active" BOOLEAN NOT NULL DEFAULT true,
    "createdAt" DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" DATETIME NOT NULL,
    CONSTRAINT "RecurringExpenseTemplate_tenantId_fkey" FOREIGN KEY ("tenantId") REFERENCES "Tenant" ("id") ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT "RecurringExpenseTemplate_categoryId_fkey" FOREIGN KEY ("categoryId") REFERENCES "ExpenseCategory" ("id") ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT "RecurringExpenseTemplate_supplierId_fkey" FOREIGN KEY ("supplierId") REFERENCES "Supplier" ("id") ON DELETE SET NULL ON UPDATE CASCADE
);

-- CreateTable
CREATE TABLE "TenantSubscription" (
    "id" TEXT NOT NULL PRIMARY KEY,
    "tenantId" TEXT NOT NULL,
    "plan" TEXT NOT NULL DEFAULT 'free',
    "status" TEXT NOT NULL DEFAULT 'active',
    "starts_at" DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "ends_at" DATETIME,
    "createdAt" DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" DATETIME NOT NULL,
    CONSTRAINT "TenantSubscription_tenantId_fkey" FOREIGN KEY ("tenantId") REFERENCES "Tenant" ("id") ON DELETE CASCADE ON UPDATE CASCADE
);

-- CreateTable
CREATE TABLE "PixCharge" (
    "id" TEXT NOT NULL PRIMARY KEY,
    "tenantId" TEXT NOT NULL,
    "orderId" TEXT NOT NULL,
    "provider" TEXT NOT NULL,
    "txid" TEXT NOT NULL,
    "amount_cents" INTEGER NOT NULL,
    "discount_type" TEXT,
    "discount_value" INTEGER,
    "discount_cents" INTEGER NOT NULL DEFAULT 0,
    "service_fee_bps" INTEGER NOT NULL DEFAULT 0,
    "qr_code" TEXT,
    "copy_paste" TEXT,
    "status" TEXT NOT NULL DEFAULT 'pending',
    "provider_payload" TEXT,
    "expires_at" DATETIME,
    "paid_at" DATETIME,
    "createdAt" DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" DATETIME NOT NULL,
    CONSTRAINT "PixCharge_tenantId_fkey" FOREIGN KEY ("tenantId") REFERENCES "Tenant" ("id") ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT "PixCharge_orderId_fkey" FOREIGN KEY ("orderId") REFERENCES "Order" ("id") ON DELETE CASCADE ON UPDATE CASCADE
);

-- CreateTable
CREATE TABLE "PrinterSetting" (
    "id" TEXT NOT NULL PRIMARY KEY,
    "tenantId" TEXT NOT NULL,
    "paper_width" INTEGER NOT NULL DEFAULT 80,
    "printer_name" TEXT,
    "protocol" TEXT NOT NULL DEFAULT 'system_spooler',
    "updatedAt" DATETIME NOT NULL,
    CONSTRAINT "PrinterSetting_tenantId_fkey" FOREIGN KEY ("tenantId") REFERENCES "Tenant" ("id") ON DELETE CASCADE ON UPDATE CASCADE
);

-- CreateTable
CREATE TABLE "AuditLog" (
    "id" TEXT NOT NULL PRIMARY KEY,
    "tenantId" TEXT NOT NULL,
    "userId" TEXT,
    "action" TEXT NOT NULL,
    "entity_type" TEXT NOT NULL,
    "entity_id" TEXT,
    "metadata" TEXT,
    "createdAt" DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT "AuditLog_tenantId_fkey" FOREIGN KEY ("tenantId") REFERENCES "Tenant" ("id") ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT "AuditLog_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User" ("id") ON DELETE SET NULL ON UPDATE CASCADE
);

-- RedefineTables
PRAGMA defer_foreign_keys=ON;
PRAGMA foreign_keys=OFF;
CREATE TABLE "new_Tenant" (
    "id" TEXT NOT NULL PRIMARY KEY,
    "name" TEXT NOT NULL,
    "role" TEXT NOT NULL,
    "logo_url" TEXT,
    "cashier_discount_limit_bps" INTEGER NOT NULL DEFAULT 10000,
    "createdAt" DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
);
INSERT INTO "new_Tenant" ("createdAt", "id", "logo_url", "name", "role") SELECT "createdAt", "id", "logo_url", "name", "role" FROM "Tenant";
DROP TABLE "Tenant";
ALTER TABLE "new_Tenant" RENAME TO "Tenant";
CREATE TABLE "new_UserTenant" (
    "userId" TEXT NOT NULL,
    "tenantId" TEXT NOT NULL,
    "role" TEXT NOT NULL,
    "active" BOOLEAN NOT NULL DEFAULT true,

    PRIMARY KEY ("userId", "tenantId"),
    CONSTRAINT "UserTenant_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User" ("id") ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT "UserTenant_tenantId_fkey" FOREIGN KEY ("tenantId") REFERENCES "Tenant" ("id") ON DELETE CASCADE ON UPDATE CASCADE
);
INSERT INTO "new_UserTenant" ("role", "tenantId", "userId") SELECT "role", "tenantId", "userId" FROM "UserTenant";
DROP TABLE "UserTenant";
ALTER TABLE "new_UserTenant" RENAME TO "UserTenant";
CREATE INDEX "UserTenant_tenantId_idx" ON "UserTenant"("tenantId");
CREATE TABLE "new_Product" (
    "id" TEXT NOT NULL PRIMARY KEY,
    "tenantId" TEXT NOT NULL,
    "categoryId" TEXT,
    "name" TEXT NOT NULL,
    "price_cents" INTEGER NOT NULL,
    "cost_cents" INTEGER NOT NULL DEFAULT 0,
    "sku" TEXT,
    "unit" TEXT NOT NULL DEFAULT 'unit',
    "stock_controlled" BOOLEAN NOT NULL DEFAULT false,
    "stock_quantity" DECIMAL NOT NULL DEFAULT 0,
    "minimum_stock" DECIMAL NOT NULL DEFAULT 0,
    "active" BOOLEAN NOT NULL DEFAULT true,
    "available" BOOLEAN NOT NULL DEFAULT true,
    "sort_order" INTEGER NOT NULL DEFAULT 0,
    "createdAt" DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT "Product_tenantId_fkey" FOREIGN KEY ("tenantId") REFERENCES "Tenant" ("id") ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT "Product_categoryId_fkey" FOREIGN KEY ("categoryId") REFERENCES "Category" ("id") ON DELETE SET NULL ON UPDATE CASCADE
);
INSERT INTO "new_Product" ("active", "available", "categoryId", "createdAt", "id", "name", "price_cents", "sort_order", "tenantId") SELECT "active", "available", "categoryId", "createdAt", "id", "name", "price_cents", "sort_order", "tenantId" FROM "Product";
DROP TABLE "Product";
ALTER TABLE "new_Product" RENAME TO "Product";
CREATE INDEX "Product_tenantId_active_idx" ON "Product"("tenantId", "active");
CREATE INDEX "Product_categoryId_idx" ON "Product"("categoryId");
CREATE UNIQUE INDEX "Product_tenantId_sku_key" ON "Product"("tenantId", "sku");
CREATE TABLE "new_Order" (
    "id" TEXT NOT NULL PRIMARY KEY,
    "tenantId" TEXT NOT NULL,
    "tableId" TEXT,
    "table_label" TEXT NOT NULL,
    "order_type" TEXT NOT NULL DEFAULT 'table',
    "status" TEXT NOT NULL DEFAULT 'open',
    "version" INTEGER NOT NULL DEFAULT 1,
    "subtotal_cents" INTEGER NOT NULL DEFAULT 0,
    "discount_cents" INTEGER NOT NULL DEFAULT 0,
    "discount_type" TEXT,
    "discount_value" INTEGER,
    "discount_authorized_by" TEXT,
    "service_fee_bps" INTEGER NOT NULL DEFAULT 1000,
    "service_fee_cents" INTEGER NOT NULL DEFAULT 0,
    "total_cents" INTEGER NOT NULL DEFAULT 0,
    "settled_at" DATETIME,
    "settled_by" TEXT,
    "opened_at" DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT "Order_tenantId_fkey" FOREIGN KEY ("tenantId") REFERENCES "Tenant" ("id") ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT "Order_tableId_fkey" FOREIGN KEY ("tableId") REFERENCES "DiningTable" ("id") ON DELETE SET NULL ON UPDATE CASCADE
);
INSERT INTO "new_Order" ("discount_cents", "id", "opened_at", "service_fee_bps", "service_fee_cents", "settled_at", "settled_by", "status", "subtotal_cents", "tableId", "table_label", "tenantId", "total_cents", "updated_at", "version") SELECT "discount_cents", "id", "opened_at", "service_fee_bps", "service_fee_cents", "settled_at", "settled_by", "status", "subtotal_cents", "tableId", "table_label", "tenantId", "total_cents", "updated_at", "version" FROM "Order";
DROP TABLE "Order";
ALTER TABLE "new_Order" RENAME TO "Order";
CREATE INDEX "Order_tenantId_status_idx" ON "Order"("tenantId", "status");
CREATE INDEX "Order_tenantId_opened_at_idx" ON "Order"("tenantId", "opened_at");
CREATE INDEX "Order_tableId_idx" ON "Order"("tableId");
CREATE TABLE "new_OrderItem" (
    "id" TEXT NOT NULL PRIMARY KEY,
    "orderId" TEXT NOT NULL,
    "productId" TEXT,
    "product_name" TEXT NOT NULL,
    "quantity" INTEGER NOT NULL,
    "unit_price_cents" INTEGER NOT NULL,
    "unit_cost_cents" INTEGER NOT NULL DEFAULT 0,
    "selected_options" TEXT,
    "notes" TEXT,
    CONSTRAINT "OrderItem_orderId_fkey" FOREIGN KEY ("orderId") REFERENCES "Order" ("id") ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT "OrderItem_productId_fkey" FOREIGN KEY ("productId") REFERENCES "Product" ("id") ON DELETE SET NULL ON UPDATE CASCADE
);
INSERT INTO "new_OrderItem" ("id", "notes", "orderId", "product_name", "quantity", "unit_price_cents") SELECT "id", "notes", "orderId", "product_name", "quantity", "unit_price_cents" FROM "OrderItem";
DROP TABLE "OrderItem";
ALTER TABLE "new_OrderItem" RENAME TO "OrderItem";
CREATE INDEX "OrderItem_orderId_idx" ON "OrderItem"("orderId");
CREATE INDEX "OrderItem_productId_idx" ON "OrderItem"("productId");
CREATE TABLE "new_OrderPayment" (
    "id" TEXT NOT NULL PRIMARY KEY,
    "orderId" TEXT NOT NULL,
    "method" TEXT NOT NULL,
    "amount_cents" INTEGER NOT NULL,
    "tendered_cents" INTEGER,
    "change_cents" INTEGER NOT NULL DEFAULT 0,
    "created_at" DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "pixChargeId" TEXT,
    CONSTRAINT "OrderPayment_orderId_fkey" FOREIGN KEY ("orderId") REFERENCES "Order" ("id") ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT "OrderPayment_pixChargeId_fkey" FOREIGN KEY ("pixChargeId") REFERENCES "PixCharge" ("id") ON DELETE SET NULL ON UPDATE CASCADE
);
INSERT INTO "new_OrderPayment" ("amount_cents", "change_cents", "created_at", "id", "method", "orderId", "tendered_cents") SELECT "amount_cents", "change_cents", "created_at", "id", "method", "orderId", "tendered_cents" FROM "OrderPayment";
DROP TABLE "OrderPayment";
ALTER TABLE "new_OrderPayment" RENAME TO "OrderPayment";
CREATE UNIQUE INDEX "OrderPayment_pixChargeId_key" ON "OrderPayment"("pixChargeId");
CREATE INDEX "OrderPayment_orderId_idx" ON "OrderPayment"("orderId");
PRAGMA foreign_keys=ON;
PRAGMA defer_foreign_keys=OFF;

-- CreateIndex
CREATE INDEX "Supplier_tenantId_active_idx" ON "Supplier"("tenantId", "active");

-- CreateIndex
CREATE UNIQUE INDEX "Supplier_tenantId_document_key" ON "Supplier"("tenantId", "document");

-- CreateIndex
CREATE UNIQUE INDEX "Purchase_payableExpenseId_key" ON "Purchase"("payableExpenseId");

-- CreateIndex
CREATE INDEX "Purchase_tenantId_purchased_at_idx" ON "Purchase"("tenantId", "purchased_at");

-- CreateIndex
CREATE INDEX "Purchase_supplierId_idx" ON "Purchase"("supplierId");

-- CreateIndex
CREATE INDEX "PurchaseItem_purchaseId_idx" ON "PurchaseItem"("purchaseId");

-- CreateIndex
CREATE INDEX "PurchaseItem_productId_idx" ON "PurchaseItem"("productId");

-- CreateIndex
CREATE INDEX "StockMovement_tenantId_occurred_at_idx" ON "StockMovement"("tenantId", "occurred_at");

-- CreateIndex
CREATE INDEX "StockMovement_productId_occurred_at_idx" ON "StockMovement"("productId", "occurred_at");

-- CreateIndex
CREATE UNIQUE INDEX "StockMovement_tenantId_type_reference_type_reference_id_productId_key" ON "StockMovement"("tenantId", "type", "reference_type", "reference_id", "productId");

-- CreateIndex
CREATE INDEX "ExpenseCategory_tenantId_active_idx" ON "ExpenseCategory"("tenantId", "active");

-- CreateIndex
CREATE UNIQUE INDEX "ExpenseCategory_tenantId_name_key" ON "ExpenseCategory"("tenantId", "name");

-- CreateIndex
CREATE INDEX "PayableExpense_tenantId_due_date_idx" ON "PayableExpense"("tenantId", "due_date");

-- CreateIndex
CREATE INDEX "PayableExpense_tenantId_competence_date_idx" ON "PayableExpense"("tenantId", "competence_date");

-- CreateIndex
CREATE INDEX "PayableExpense_supplierId_idx" ON "PayableExpense"("supplierId");

-- CreateIndex
CREATE INDEX "PayableExpense_categoryId_idx" ON "PayableExpense"("categoryId");

-- CreateIndex
CREATE UNIQUE INDEX "PayableExpense_tenantId_recurringTemplateId_competence_date_key" ON "PayableExpense"("tenantId", "recurringTemplateId", "competence_date");

-- CreateIndex
CREATE INDEX "ExpensePayment_expenseId_paid_at_idx" ON "ExpensePayment"("expenseId", "paid_at");

-- CreateIndex
CREATE INDEX "RecurringExpenseTemplate_tenantId_active_idx" ON "RecurringExpenseTemplate"("tenantId", "active");

-- CreateIndex
CREATE INDEX "TenantSubscription_tenantId_status_idx" ON "TenantSubscription"("tenantId", "status");

-- CreateIndex
CREATE INDEX "PixCharge_orderId_status_idx" ON "PixCharge"("orderId", "status");

-- CreateIndex
CREATE UNIQUE INDEX "PixCharge_tenantId_txid_key" ON "PixCharge"("tenantId", "txid");

-- CreateIndex
CREATE UNIQUE INDEX "PrinterSetting_tenantId_key" ON "PrinterSetting"("tenantId");

-- CreateIndex
CREATE INDEX "AuditLog_tenantId_createdAt_idx" ON "AuditLog"("tenantId", "createdAt");

-- CreateIndex
CREATE INDEX "AuditLog_userId_idx" ON "AuditLog"("userId");
