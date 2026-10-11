# Laragon (Windows)

> Não testado por nós ponta a ponta: conferir os menus na versão instalada e corrigir aqui o que divergir.

- Raiz `C:\laragon\www`: com **Auto virtual hosts** ligado (Menu > Preferences > General), cada pasta vira `<pasta>.test` no próximo reload (Menu > Apache/Nginx > Reload). O Laragon grava no arquivo `hosts` do Windows — precisa rodar como administrador.
- **Sem curinga de DNS**: subdomínio de tenant (`acme.<pasta>.test`) precisa de linha própria no `hosts` (ou usar o modo nativo `*.localhost` do `wt-setup.sh`).
- HTTPS: Menu > Apache > SSL > Enabled.
- Binários em `C:\laragon\bin\{php,mysql,nodejs,python,…}\<versão>`; o terminal do Laragon (Cmder) já tem o PATH. Para o Git Bash e os hooks: Menu > Tools > Path > Add Laragon to Path (ou exportar no `~/.bashrc`). O `wt-lib.sh` acha o cliente `mysql` em `/c/laragon/bin/mysql/*/bin`.
- MySQL/MariaDB: `root` sem senha em `127.0.0.1:3306`.
- Trocar versão de PHP/MySQL/Node: Menu > PHP/MySQL/Node > Version.

## Herd + Laragon
Combinação comum: **Herd serve o PHP e os sites**, **Laragon só o MySQL** (Herd grátis não tem banco).
- No Laragon, parar Apache/Nginx (porta 80/443 é do Herd) e deixar só o MySQL; no perfil da máquina: "Sites: Herd; Banco: MySQL do Laragon em 3306".
- Projetos ficam na pasta do Herd (`~/Herd`), não em `www`.
- `WT_SITES=herd` no `.orca/worktree.conf` se a detecção escolher errado.
