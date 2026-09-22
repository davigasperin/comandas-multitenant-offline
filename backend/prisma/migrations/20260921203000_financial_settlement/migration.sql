-- Financial settlement is additive. Existing closed orders remain historically closed without fabricated payments.
ALTER TABLE "Order" ADD COLUMN "subtotal_cents" INTEGER NOT NULL DEFAULT 0;
ALTER TABLE "Order" ADD COLUMN "discount_cents" INTEGER NOT NULL DEFAULT 0;
ALTER TABLE "Order" ADD COLUMN "service_fee_bps" INTEGER NOT NULL DEFAULT 1000;
ALTER TABLE "Order" ADD COLUMN "service_fee_cents" INTEGER NOT NULL DEFAULT 0;
ALTER TABLE "Order" ADD COLUMN "total_cents" INTEGER NOT NULL DEFAULT 0;
ALTER TABLE "Order" ADD COLUMN "settled_at" DATETIME;
ALTER TABLE "Order" ADD COLUMN "settled_by" TEXT;

CREATE TABLE "OrderPayment" (
    "id" TEXT NOT NULL PRIMARY KEY,
    "orderId" TEXT NOT NULL,
    "method" TEXT NOT NULL CHECK ("method" IN ('cash', 'pix', 'credit', 'debit', 'voucher')),
    "amount_cents" INTEGER NOT NULL CHECK ("amount_cents" > 0),
    "tendered_cents" INTEGER,
    "change_cents" INTEGER NOT NULL DEFAULT 0 CHECK ("change_cents" >= 0),
    "created_at" DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT "OrderPayment_orderId_fkey" FOREIGN KEY ("orderId") REFERENCES "Order" ("id") ON DELETE CASCADE ON UPDATE CASCADE,
    CHECK (("method" = 'cash') OR ("tendered_cents" IS NULL AND "change_cents" = 0))
);
CREATE INDEX "OrderPayment_orderId_idx" ON "OrderPayment"("orderId");
