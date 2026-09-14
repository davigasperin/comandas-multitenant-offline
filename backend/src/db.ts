export interface User {
  id: string;
  name: string;
  email: string;
  password: string;
}

export interface Tenant {
  id: string;
  name: string;
  role: string;
  logo_url?: string;
}

export interface UserTenant {
  userId: string;
  tenantId: string;
  role: string;
}

export interface OrderItem {
  id: string;
  product_name: string;
  quantity: number;
  unit_price: number;
  notes?: string;
}

export interface Product {
  id: string;
  tenantId: string;
  name: string;
  price: number;
}

export const PRODUCTS: Product[] = [
  { id: 'prod_1', tenantId: 'ten_1', name: 'Água mineral', price: 5 },
  { id: 'prod_2', tenantId: 'ten_1', name: 'Refrigerante lata', price: 8 },
  { id: 'prod_3', tenantId: 'ten_1', name: 'Cerveja artesanal', price: 18 },
  { id: 'prod_4', tenantId: 'ten_1', name: 'Porção de batata', price: 32 },
  { id: 'prod_5', tenantId: 'ten_1', name: 'Hambúrguer clássico', price: 38 },
];

export interface Order {
  id: string;
  tenantId: string;
  table_label: string;
  status: 'open' | 'sentToKitchen' | 'delivered' | 'closed' | 'canceled';
  opened_at: string;
  items: OrderItem[];
}

export const USERS: User[] = [
  {
    id: 'usr_1',
    name: 'Garçom Demo',
    email: 'demo@comandas.com',
    password: 'password123',
  },
];

export const TENANTS: Tenant[] = [
  { id: 'ten_1', name: 'Bar do Zé', role: 'waiter' },
  { id: 'ten_2', name: 'Restaurante Sabor & Arte', role: 'manager' },
];

export const USER_TENANTS: UserTenant[] = [
  { userId: 'usr_1', tenantId: 'ten_1', role: 'waiter' },
  { userId: 'usr_1', tenantId: 'ten_2', role: 'manager' },
];

export const ORDERS: Order[] = [
  {
    id: 'ord_1',
    tenantId: 'ten_1',
    table_label: 'Mesa 01',
    status: 'open',
    opened_at: new Date().toISOString(),
    items: [
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
  {
    id: 'ord_2',
    tenantId: 'ten_1',
    table_label: 'Mesa 04',
    status: 'sentToKitchen',
    opened_at: new Date().toISOString(),
    items: [
      {
        id: 'item_3',
        product_name: 'Hambúrguer Clássico',
        quantity: 1,
        unit_price: 38.0,
        notes: 'Ao ponto',
      },
    ],
  },
];
