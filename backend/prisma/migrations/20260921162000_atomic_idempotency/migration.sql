-- RedefineTables
PRAGMA defer_foreign_keys=ON;
PRAGMA foreign_keys=OFF;
CREATE TABLE "new_IdempotencyKey" (
    "key" TEXT NOT NULL,
    "tenantId" TEXT NOT NULL,
    "status" TEXT NOT NULL DEFAULT 'completed',
    "response" TEXT,
    "requestHash" TEXT,
    "createdAt" DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "completed_at" DATETIME,

    PRIMARY KEY ("tenantId", "key"),
    CONSTRAINT "IdempotencyKey_tenantId_fkey" FOREIGN KEY ("tenantId") REFERENCES "Tenant" ("id") ON DELETE CASCADE ON UPDATE CASCADE
);
INSERT INTO "new_IdempotencyKey" ("createdAt", "key", "requestHash", "response", "tenantId") SELECT "createdAt", "key", "requestHash", "response", "tenantId" FROM "IdempotencyKey";
DROP TABLE "IdempotencyKey";
ALTER TABLE "new_IdempotencyKey" RENAME TO "IdempotencyKey";
PRAGMA foreign_keys=ON;
PRAGMA defer_foreign_keys=OFF;
