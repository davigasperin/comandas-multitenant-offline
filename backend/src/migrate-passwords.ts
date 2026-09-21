import 'dotenv/config';
import { PrismaClient } from '@prisma/client';
import { hashPassword } from './auth.utils';

const prisma = new PrismaClient();

export async function migratePlaintextPasswords(client: PrismaClient = prisma): Promise<{ migrated: number; skipped: number }> {
  const users = await client.user.findMany();
  let migrated = 0;
  let skipped = 0;

  for (const user of users) {
    if (!user.password.startsWith('scrypt:')) {
      const hashed = await hashPassword(user.password);
      await client.user.update({
        where: { id: user.id },
        data: { password: hashed },
      });
      migrated++;
    } else {
      skipped++;
    }
  }

  return { migrated, skipped };
}

async function run() {
  console.log('Iniciando migração segura de senhas legadas...');
  const result = await migratePlaintextPasswords();
  console.log(`Migração concluída: ${result.migrated} senhas migradas, ${result.skipped} já no formato seguro.`);
  await prisma.$disconnect();
}

if (require.main === module) {
  run().catch((e) => {
    console.error('Falha na migração de senhas:', e);
    process.exit(1);
  });
}
