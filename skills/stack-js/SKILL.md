---
name: stack-js
description: Use antes de escrever, revisar ou testar código num projeto JavaScript/TypeScript (package.json) — gerenciador de pacotes, versão do Node, validação (eslint/biome, prettier, tsc), testes pela fila (vitest/jest), worktree e armadilhas.
---

# Stack JavaScript / TypeScript

## Descobrir o projeto (antes de qualquer comando)
| Lockfile | Gerenciador | Instalar | Rodar script |
|---|---|---|---|
| `pnpm-lock.yaml` | pnpm | `pnpm install --frozen-lockfile` | `pnpm <script>` |
| `yarn.lock` | Yarn | `yarn install --immutable` (Berry) / `--frozen-lockfile` (v1) | `yarn <script>` |
| `bun.lock` / `bun.lockb` | Bun | `bun install --frozen-lockfile` | `bun run <script>` |
| `package-lock.json` | npm | `npm ci` | `npm run <script>` |

- Nunca misturar gerenciadores nem gerar outro lockfile. `packageManager` no `package.json` → `corepack enable`.
- Versão do Node: `.nvmrc`, `.node-version`, `engines` ou `volta` → nvm/nvm-windows, fnm ou volta.
- Monorepo (`pnpm-workspace.yaml`, `turbo.json`, `nx.json`, `workspaces`): rodar no pacote certo (`pnpm --filter <pkg>`, `turbo run <task> --filter`).
- Scripts do `package.json` são a fonte da verdade (`lint`, `typecheck`, `test`, `build`) — usar os do projeto, não inventar flags.

## Validar (após cada etapa)
1. Formatar e lintar os arquivos tocados com o configurado: `eslint --fix <arquivos>` + `prettier --write <arquivos>`, ou `biome check --write <arquivos>`.
2. Tipos: o script `typecheck` ou `tsc --noEmit` (com `tsconfig.json`).
3. Teste de regressão pela fila: `bash ~/.cache/fila-teste.sh <arquivo ou filtro>` (detecta o gerenciador e roda o script `test`); comando explícito: `bash ~/.cache/fila-teste.sh -- pnpm vitest run <arquivo>`.
4. Listar sem rodar: `vitest list` ou `jest --listTests`.
5. Front com tela: validar no navegador (skill `orca-cli`), com perfil real.

## Testes
- Vitest/Jest rodam em watch por padrão em alguns setups: usar `vitest run` / `CI=1` na fila.
- Testes E2E (Playwright/Cypress) só quando a tarefa pede; precisam do servidor do worktree no ar.
- Banco por worktree: a variável do ORM (`DATABASE_URL` para Prisma/Drizzle/Knex/TypeORM).

## Worktree
- Pelo Orca: `wt-setup.sh` (skill `worktree-orca`) copia o `.env`, troca banco e host, cria o banco, instala pelo gerenciador detectado e roda `WT_MIGRAR`/`WT_SEED` do `.orca/worktree.conf` (ex.: `WT_MIGRAR="pnpm prisma migrate deploy"`).
- Porta do dev server por worktree (`PORT`, `--port`) para dois rodarem juntos.

## Armadilhas
- `node_modules` não se copia entre worktrees: instalar em cada um (pnpm reaproveita a store, é rápido).
- Windows: scripts com `rm -rf`/`export` quebram fora do Git Bash — o projeto deve usar `rimraf`/`cross-env`; não "consertar" trocando o shell.
- Prisma: `prisma generate` após instalar; o cliente gerado vai para `node_modules`, não para o git.
