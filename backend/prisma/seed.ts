import 'dotenv/config';
import { PrismaClient } from '@prisma/client';
import { hashPassword } from '../src/auth.utils';

const prisma = new PrismaClient();

async function main() {
  const seedPassword = process.env.SEED_USER_PASSWORD;
  if (!seedPassword) throw new Error('SEED_USER_PASSWORD is required');
  const hashedPassword = await hashPassword(seedPassword);

  const user = await prisma.user.upsert({
    where: { email: 'demo@comandas.com' },
    update: {
      password: hashedPassword,
    },
    create: {
      id: 'usr_1',
      name: 'Garçom Demo',
      email: 'demo@comandas.com',
      password: hashedPassword,
    },
  });

  const tenant1 = await prisma.tenant.upsert({
    where: { id: 'ten_1' },
    update: {},
    create: {
      id: 'ten_1',
      name: 'Bar do Zé',
      role: 'waiter',
    },
  });

  const tenant2 = await prisma.tenant.upsert({
    where: { id: 'ten_2' },
    update: {},
    create: {
      id: 'ten_2',
      name: 'Restaurante Sabor & Arte',
      role: 'manager',
    },
  });

  await prisma.userTenant.upsert({
    where: { userId_tenantId: { userId: user.id, tenantId: tenant1.id } },
    update: {},
    create: {
      userId: user.id,
      tenantId: tenant1.id,
      role: 'waiter',
    },
  });

  await prisma.userTenant.upsert({
    where: { userId_tenantId: { userId: user.id, tenantId: tenant2.id } },
    update: {},
    create: {
      userId: user.id,
      tenantId: tenant2.id,
      role: 'manager',
    },
  });

  const products = [
    { id: 'prod_1', tenantId: 'ten_1', name: 'Água mineral', price: 5 },
    { id: 'prod_2', tenantId: 'ten_1', name: 'Refrigerante lata', price: 8 },
    { id: 'prod_3', tenantId: 'ten_1', name: 'Cerveja artesanal', price: 18 },
    { id: 'prod_4', tenantId: 'ten_1', name: 'Porção de batata', price: 32 },
    { id: 'prod_5', tenantId: 'ten_1', name: 'Hambúrguer clássico', price: 38 },
  ];

  for (const p of products) {
    await prisma.product.upsert({
      where: { id: p.id },
      update: {},
      create: p,
    });
  }

  const existingOrder = await prisma.order.findUnique({ where: { id: 'ord_1' } });
  if (!existingOrder) {
    await prisma.order.create({
      data: {
        id: 'ord_1',
        tenantId: 'ten_1',
        table_label: 'Mesa 01',
        status: 'open',
        items: {
          create: [
            {
              id: 'item_1',
              product_name: 'Cerveja Artesanal 500ml',
              quantity: 2,
              unit_price: 18.0,
            },
            {
              id: 'item_2',
              product_name: 'Porção de Batata Frita',
              quantity: 1,
              unit_price: 32.0,
              notes: 'Sem sal',
            },
          ],
        },
      },
    });
  }

  const existingOrder2 = await prisma.order.findUnique({ where: { id: 'ord_2' } });
  if (!existingOrder2) {
    await prisma.order.create({
      data: {
        id: 'ord_2',
        tenantId: 'ten_1',
        table_label: 'Mesa 04',
        status: 'sentToKitchen',
        items: {
          create: [
            {
              id: 'item_3',
              product_name: 'Hambúrguer Clássico',
              quantity: 1,
              unit_price: 38.0,
              notes: 'Ao ponto',
            },
          ],
        },
      },
    });
  }

  console.log('Seed completed successfully with hashed user password.');
}

main()
  .catch((e) => {
    console.error(e);
    process.exit(1);
  })
  .finally(async () => {
    await prisma.$disconnect();
  });
