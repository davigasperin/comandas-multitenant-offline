import { PrismaClient } from '@prisma/client';
import { hashPassword } from '../src/auth.utils';

const prisma = new PrismaClient();

async function main() {
  const seedPassword = process.env.SEED_USER_PASSWORD || 'password123';
  const hashedPassword = await hashPassword(seedPassword);

  const user = await prisma.user.upsert({
    where: { email: 'demo@comandas.com' },
    update: { password: hashedPassword },
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
    { id: 'prod_1', tenantId: 'ten_1', name: 'Água mineral', price_cents: 500 },
    { id: 'prod_2', tenantId: 'ten_1', name: 'Refrigerante lata', price_cents: 800 },
    { id: 'prod_3', tenantId: 'ten_1', name: 'Cerveja artesanal', price_cents: 1800 },
    { id: 'prod_4', tenantId: 'ten_1', name: 'Porção de batata', price_cents: 3200 },
    { id: 'prod_5', tenantId: 'ten_1', name: 'Hambúrguer clássico', price_cents: 3800 },
  ];

  for (const p of products) {
    await prisma.product.upsert({
      where: { id: p.id },
      update: { price_cents: p.price_cents },
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
        version: 1,
        items: {
          create: [
            {
              id: 'item_1',
              product_name: 'Cerveja Artesanal 500ml',
              quantity: 2,
              unit_price_cents: 1800,
            },
            {
              id: 'item_2',
              product_name: 'Porção de Batata Frita',
              quantity: 1,
              unit_price_cents: 3200,
              notes: 'Sem sal',
            },
          ],
        },
        history: {
          create: {
            from_status: null,
            to_status: 'open',
            changed_by: user.id,
          },
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
        version: 1,
        items: {
          create: [
            {
              id: 'item_3',
              product_name: 'Hambúrguer Clássico',
              quantity: 1,
              unit_price_cents: 3800,
              notes: 'Ao ponto',
            },
          ],
        },
        history: {
          create: {
            from_status: null,
            to_status: 'sentToKitchen',
            changed_by: user.id,
          },
        },
      },
    });
  }

  console.log('Carga inicial concluída com senha protegida por hash e valores em centavos inteiros.');
}

main()
  .catch((e) => {
    console.error(e);
    process.exit(1);
  })
  .finally(async () => {
    await prisma.$disconnect();
  });
