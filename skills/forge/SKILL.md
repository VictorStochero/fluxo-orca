---
name: forge
description: Use ao tocar servidores ou sites hospedados no Laravel Forge (deploy, logs, SSH, atualização, auditoria de segurança, "qual servidor roda X") — contas e inventário da máquina em ~/.claude/forge.md, Forge CLI v2 com várias contas, API nova (nginx, firewall, processos, chaves SSH) e armadilhas de servidor (fuso, certificados, Reverb/workers, Redis, MariaDB).
---

# Laravel Forge

## Inventário da máquina
As contas, o CLI de cada uma, os servidores (IP, id), os sites (usuário isolado, repo@branch, ids de worker/Reverb/agendador) e onde ficam as senhas estão em `~/.claude/forge.md`. Esse arquivo fica fora do plugin e do git. Ler antes de consultar a API. Se faltar o arquivo, ou se um servidor/site citado não estiver nele, levantar pela API (§ Reatualizar), gravar e seguir.

O `forge.md` guarda só dados. Uma armadilha que vale para qualquer servidor vai para esta skill.

## Regras
- Alteração remota (deploy, nginx, firewall, processo, `.env`, SQL) segue a regra de aprovação por comando do CLAUDE.md global: mostrar o comando, o alvo e o efeito antes, e esperar a aprovação de cada um.
- Nunca exibir nem gravar segredo: token do CLI, senha de sudo ou de banco, URL de deploy (ela leva token). O recurso Server da API traz a senha de sudo/banco e o Site traz a URL de deploy, então nada disso vai para o `forge.md`.
- A senha de sudo do `forge` só sai da API no provisionamento. Depois disso, ela fica onde o `forge.md` indica. Para validar, usar `sudo -k -v`.

## CLI e várias contas
- O Forge CLI v2 guarda o login em `$HOME/.laravel-forge/config.json` (campo `token`). Para uma segunda conta, usar um wrapper que troca o `HOME` (ex.: `forge-<conta>.bat` com `HOME=~/.forge-<conta>`). As chaves do `ssh:configure` dessa conta ficam no `HOME` dela.
- No Windows, o `forge` do Herd é `.bat` + phar e só roda no PowerShell/cmd, não no Git Bash.
- O CLI v2 não edita nginx nem firewall: para isso, usar a API (abaixo). O `background-process:restart` do v2.0.0 responde "not installed or running".
- Ligar Reverb ou worker antes do primeiro deploy falha, porque o release `000000` ainda não tem `vendor`. Fazer o deploy primeiro.

## SSH e caminhos
- Cada site "Custom" isolado tem um usuário Linux próprio. Para entrar: `ssh <usuario>@<ip>`. O `sudo` é sempre pelo `forge`.
- Código: `/home/<usuario>/<domínio>/current` (zero-downtime) ou `/home/<usuario>/<domínio>`.
- Para pôr uma chave num usuário isolado: `POST /servers/<id>/ssh-keys` com `{name,key,user}`.
- Logs: `sudo journalctl -u mariadb`, `sudo journalctl -k | grep -i oom`, `/var/log/mysql/error.log` (só com sudo) e `forge site:logs`/`deploy:log`.

## API nova
Base `https://forge.laravel.com/api/orgs/<org>`, com `Authorization: Bearer <token do CLI>` (nunca exibir o token).
- Fica atrás da Cloudflare: cliente sem `User-Agent` de navegador/curl leva 403 (erro 1010).
- No Git Bash, usar `MSYS_NO_PATHCONV=1` para o caminho `/orgs/...` não virar caminho do Windows.
- `DELETE` responde 202 (assíncrono). O `PUT` de nginx também responde 202.
- Recursos por servidor (`/servers/<id>/...`): `sites`, `database/schemas`, `database/users`, `background-processes`, `scheduled-jobs`, `firewall-rules`, `ssh-keys`.
- Site: `GET /orgs/<org>/sites/<id>`. Sob o servidor, `/servers/<id>/sites/<site>` só aceita PUT e DELETE, não tem GET. `PUT` com `{"push_to_deploy": true|false}` liga ou desliga o deploy por push.
- Nginx: `GET|PUT /servers/<id>/sites/<site>/nginx`. O GET devolve `content` e o PUT recebe `{"config": "..."}`. A API só edita o `site.conf` de dentro do `server`. Um bloco `server` a mais (ex.: expor só um webhook) vai como root em `/etc/nginx/forge-conf/<site>/after/<nome>.conf`.
- Firewall: `GET|POST /servers/<id>/firewall-rules` com `{"name","port","type":"allow","ip_address"}`, e `DELETE .../firewall-rules/<rule>`.
- Processos: `PUT /background-processes/<id>` exige `name` e devolveu 500 sem aplicar. Para mudar o comando, criar um processo novo com `POST` (com `name`) e apagar o antigo com `DELETE`.

## Armadilhas de servidor
- **Fuso e TIMESTAMP**: o MariaDB usa o fuso `SYSTEM` e os apps Laravel não fixam o `time_zone` da sessão, então as colunas `TIMESTAMP` dependem do fuso do SO. Ao levar um banco entre servidores de fuso diferente, fazer o dump com `--skip-tz-utc`. O padrão `--tz-utc` desloca as datas pela diferença dos fusos.
- **Certificados**: pedir um de cada vez. Pedidos simultâneos já deixaram um certificado sem arquivo e derrubaram o nginx. No Let's Encrypt por DNS-01, os CNAMEs `_acme-challenge.<host>` → `*.ssl.on-forge.com` precisam ficar no DNS para a renovação. Vhost fora do `sites-enabled` faz o renew falhar.
- **Trocar o store do cache** não reinicia o Reverb nem os workers. O `reverb:restart` e o `queue:restart` gravam o sinal no store NOVO, e o processo em execução lê o antigo. Para reiniciar, gravar `laravel:reverb:restart` no store antigo (`Cache::store("<antigo>")->forever(...)`) ou recriar o processo.
- **Redis com vários sites**: o Redis não limita o `SELECT`, então um `FLUSHDB` (`cache:clear`/`optimize:clear`) de um site apaga a sessão e a fila dos outros. Dar a cada site um usuário ACL restrito ao próprio prefixo, com `-@dangerous`, e `+flushdb` só onde for preciso. Desligar o usuário `default` e fazer o bind só em loopback.
- **MariaDB e OOM**: um DELETE em tabela-pai com muitas filhas em CASCADE/SET NULL e triggers de auditoria abre milhares de instâncias de tabela. Com `table_open_cache` alto, o cache retém essas instâncias, e o OOM killer pode matar o `mariadbd`. Baixar o `table_open_cache` num `.cnf` próprio em `/etc/mysql/mariadb.conf.d/`.
- **Atrás do proxy da Cloudflare**: se o nginx resolve o IP real (`/etc/nginx/conf.d/cloudflare.conf`), o app não precisa de `trustProxies`. Firewall só com as faixas da Cloudflare na 443 precisa de revisão quando elas mudam.

## Reatualizar
`forge server:list` (e o mesmo em cada conta) e, por servidor, `server:switch` + `site:list`. Gravar no `~/.claude/forge.md` só dados não secretos (§ Regras).
