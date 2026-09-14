# Comandas — Sistema Operacional de Pedidos Multi-Tenant & Offline First

App mobile (Flutter) com backend acoplado (NestJS) voltado para operação rápida de comandas e mesas em bares e restaurantes. Construído com arquitetura de isolamento multi-tenant real, resiliência a falhas de rede com mutações idempotentes e testes automatizados.

---

## Destaques de Arquitetura & Decisões Técnicas

### 1. Isolamento Multi-Tenant em Camadas
O desafio em restaurantes de múltiplos estabelecimentos é garantir que o operador nunca envie itens ou visualize faturamento de outra empresa.

- **Cliente (`AuthTenantInterceptor`):** Cada chamada HTTP carrega automaticamente o token JWT e o header `X-Tenant-Id` resolvido a partir do `FlutterSecureStorage`.
- **Backend Guard (`TenantGuard`):** Nenhuma decisão de autorização ocorre no app. O NestJS valida se o `sub` do JWT autenticado possui autorização estrita sobre a empresa especificada no header `X-Tenant-Id`.
- **Prevenção de Leaks:** Trocas de empresa invalidam imediatamente as árvores de estado em memória do Riverpod (`ref.invalidate()`).

### 2. Sincronização e Resiliência Offline (Wi-Fi de Bar Instável)
Em horários de pico, a conexão de rede cai com frequência. A arquitetura trata a instabilidade através de:

- **Cache Escopado de Leitura:** Respostas dos endpoints `GET /orders`, `/orders/:id` e `/orders/products` são serializadas localmente, escopadas por `tenantId` e ID de usuário autenticado. Em caso de perda de conexão (`connectionError`), o app renderiza os dados salvos marcando visualmente o selo de `Offline (Cache)`.
- **Fila Segura de Mutações:** Operações de adição de itens e fechamento com falha são salvas em fila local. 
- **Chave de Idempotência (`X-Idempotency-Key`):** Todas as mutações geram uma chave única persistida. Ao restabelecer a conexão e disparar a sincronização, o backend rejeita duplicações acidentais caso a requisição anterior tenha sido processada mas o ACK tenha se perdido por timeout do socket.

### 3. Gerenciamento de Estado & Injeção de Dependências
- **Flutter Riverpod:** Utilizado com abordagem limpa baseada em `Provider` (para singletons de infraestrutura como `Dio` e repositórios) e `FutureProvider.autoDispose` / `FutureProvider.family` para lidar com ciclos de vida de telas, evitando acúmulo de memória e boilerplates desnecessários.
- **Design System Operacional:** Paleta em alto contraste (Teal & Amber), fontes tabulares (`Fira Code`) para valores monetários e áreas de toque mínimas de 48dp aderentes às diretrizes de ergonomia para telas sob luz forte.

---

## Estrutura do Projeto

```text
lib/
├── core/
│   ├── constants/            # Constantes de rede e chaves de storage
│   ├── errors/               # Exceções de domínio tipadas (ApiException)
│   ├── network/              # ApiClient, Interceptors (Auth, Tenant, Offline) e SyncService
│   └── theme/                # Tokens de design system e temas globais
├── features/
│   ├── auth/                 # Fluxo de login e sessão
│   ├── tenant/               # Gestão e troca dinâmica de empresa
│   ├── dashboard/            # Shell principal com tabs e ações operacionais
│   └── orders/               # Domínio de comandas: criação, catálogo, fechamento
└── main.dart

backend/
├── src/
│   ├── app.controller.ts     # Auth & perfil
│   ├── orders.controller.ts  # CRUD de pedidos com Idempotência
│   ├── db.ts                 # Store e seeds em memória
│   └── *.guard.ts            # Guards de Auth e Tenant
```

---

## Endpoints do Backend

| Método | Rota                 | Descrição                                         |
|:------:|:--------------------:|:--------------------------------------------------|
| `POST` | `/v1/auth/login`     | Autenticação (retorna JWT e empresas acessíveis)  |
| `GET`  | `/v1/me/tenants`     | Lista empresas do usuário logado                  |
| `GET`  | `/v1/orders`         | Lista pedidos do tenant (filtro por status)       |
| `POST` | `/v1/orders`         | Abre uma nova comanda/mesa                        |
| `GET`  | `/v1/orders/products`| Catálogo de itens e preços da empresa             |
| `GET`  | `/v1/orders/:id`     | Detalhe e listagem de itens da comanda            |
| `POST` | `/v1/orders/:id/items` | Lança item com validação e chave idempotente    |
| `POST` | `/v1/orders/:id/close` | Fecha comanda bloqueando alterações futuras       |

---

## Como Executar Localmente

### 1. Iniciar o Backend
```bash
cd backend
npm install
npm run start:dev
```
*Disponível em `http://localhost:3000` (Credenciais demo: `demo@comandas.com` / `password123`).*

### 2. Iniciar o App Flutter
```bash
flutter pub get
flutter run -d chrome
```

---

## Qualidade de Código e CI/CD

O projeto conta com esteira de integração contínua via **GitHub Actions** (`.github/workflows/ci.yml`), validando em tempo real:
- Formatação e Análise Estática (`flutter analyze` com zero warnings).
- Bateria de testes de Widget e Unidade (`flutter test`).
- Compilação estrita em TypeScript e testes de concorrência/idempotência do backend.
