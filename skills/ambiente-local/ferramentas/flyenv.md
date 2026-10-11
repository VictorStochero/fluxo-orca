# FlyEnv (Windows, macOS, Linux)

> Não testado por nós: conferir na versão instalada e corrigir aqui o que divergir.

- Gerenciador gráfico nativo (sem Docker) de PHP, Node, Python, Nginx/Apache/Caddy, MySQL/MariaDB/Postgres, Redis e outros, com várias versões lado a lado. DNS próprio para domínios locais e HTTPS de um clique.
- **Sites são criados na interface** (Host > novo site: domínio e pasta raiz, ex.: `<pasta>.test` → `<worktree>/public`). Não há CLI documentada para isso: o `wt-setup.sh` imprime o passo e o worktree só responde depois de criado. A documentação cita um servidor MCP embutido — se estiver ativo, preferir ele para criar o site.
- Versão gratuita pode limitar o número de sites (relato de terceiros: 3) — conferir antes de contar com um site por worktree; sem folga, usar `WT_SITES=nativo` (`*.localhost:<porta>`).
- Bancos: porta e credenciais na tela do serviço; registrar no perfil da máquina. O `wt-lib.sh` usa o cliente no PATH ou o PDO do PHP.
- PATH dos runtimes para o shell/Git Bash: opção de adicionar ao PATH na tela de cada versão.
