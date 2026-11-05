> **Nota:** Este projeto foi vibe-coded com auxílio de IA.

# Script de Configuração do Sunshine para Linux

Script automatizado de instalação e configuração do [Sunshine](https://github.com/LizardByte/Sunshine) (servidor de streaming de jogos) e de monitor virtual para KDE Plasma e Hyprland (Wayland) em distribuições Linux tradicionais e sistemas imutáveis/atômicos.

Portado e aprimorado a partir das receitas `setup-sunshine` e scripts de automação de monitor virtual do projeto **Bazzite**.

[Changelog](./CHANGELOG.md)

---

## 🚀 Funcionalidades

- **Suporte Multidistro Nativo**:
  - **Fedora**: Instalado via COPR (`lizardbyte/stable`).
  - **Arch Linux**: Instalado via AUR (`sunshine-bin`) utilizando `yay` ou `paru`.
  - **CachyOS**: Instalado via repositórios oficiais (`pacman -S sunshine`).
  - **Ubuntu / Debian**: Obtém e instala automaticamente pacotes `.deb` compatíveis diretamente do repositório upstream.
- **Proteção para Sistemas Imutáveis**:
  - Compatibilidade completa com **Fedora Silverblue**, **Kinoite**, **Bazzite**, **Bluefin**, **Aurora**, **openSUSE MicroOS**/**uCore**, **SteamOS/Steam Deck**, **Sericea**, **Onyx**, HoloISO, `bootc` e outros sistemas atômicos.
  - Execução de gerenciadores de pacotes nativos (`dnf`, `pacman`, `apt`) é **estritamente bloqueada** em sistemas imutáveis.
  - Redirecionamento automático para instalação via **Flatpak**.
- **Escopos Flexíveis no Flatpak**:
  - Permite escolher o escopo de instalação do Flatpak: `--system` (global) ou `--user` (apenas para o usuário atual).
- **Integração com Monitor Virtual**:
  - Backends separados para KDE e Hyprland, selecionados conforme a sessão de desktop ativa.
  - KDE cria a tela virtual usando `krfb-virtualmonitor` e `kscreen-doctor`.
  - Hyprland cria uma saída headless com `hyprctl` somente durante a sessão do app Sunshine e a remove ao terminar a captura.
  - Durante a captura, Hyprland desativa temporariamente as telas físicas, confirma que ficaram inativas e restaura modo, posição, escala e transformação anteriores ao encerrar a sessão.
  - Os hooks de ciclo de vida dos dois backends são mantidos como scripts independentes (instalados em `~/.local/bin`) e desfazem um monitor/saída recém-criado caso a inicialização falhe.
  - Ambos ajustam resolução e taxa de quadros conforme o cliente (SUNSHINE_CLIENT_WIDTH / HEIGHT / FPS) quando o app de monitor virtual do Sunshine é iniciado; o backend Hyprland configura a captura `wlr`.
- **Correções e Ferramentas de Manutenção**:
  - **Correção do Erro 503**: Adiciona `KWIN_WAYLAND_NO_PERMISSION_CHECKS=1` em um arquivo dedicado; `503-reset` remove a configuração.
  - **Configuração de Firewall**: Detecta `firewalld` ou `ufw` e libera as portas necessárias para streaming e mDNS, com opção de restringir a um CIDR IPv4/IPv6.
  - **Idioma do Teclado**: O Sunshine não tem configuração de layout de teclado — os caracteres digitados por um cliente seguem o layout de teclado da sessão do host, e `locale` apenas traduz a interface web. O menu Teclado detecta o layout configurado (`kxkbrc` do KDE, GNOME, `/etc/default/keyboard`, `/etc/vconsole.conf`, Hyprland), avisa quando a sessão usa um layout diferente (a causa clássica de "o teclado fica sempre em inglês"), corrige isso no KDE Plasma e sincroniza o `locale` do Sunshine (ou permite escolher cada um manualmente).
  - **Desinstalação Limpa**: Remove scripts do monitor virtual, hooks de pós-execução do systemd e configurações da aplicação Sunshine.

---

## 🐧 Distribuições Suportadas

| Tipo de Distribuição | Distribuições / Sistemas Suportados | Método de Instalação Permitido |
| :--- | :--- | :--- |
| **Distribuições Tradicionais** | Fedora, Arch Linux, CachyOS, Ubuntu, Debian 13 (trixie) | Pacote Nativo **ou** Flatpak |
| **Somente Flatpak** | Todas as outras versões do Debian (12 e anteriores, 14+) | Flatpak (`--system` / `--user`) |
| **Imutáveis / Atômicas** | Bazzite, Silverblue, Kinoite, SteamOS, Bluefin, Aurora, openSUSE MicroOS | **Apenas Flatpak** (`--system` / `--user`) |
| **Distribuições Não Suportadas** | Outras distribuições não reconhecidas por `ID` ou `ID_LIKE` | Somente Flatpak, sem garantia; podem ocorrer falhas |

O instalador lê `/etc/os-release`: prioriza o `ID` exato da distribuição; se não for suportado, verifica `ID_LIKE` da esquerda para a direita e usa a primeira família compatível. IDs desconhecidos não são reconhecidos por correspondência parcial. Em distribuições não reconhecidas, o script continua com um aviso, oferece instalação Flatpak para o sistema ou para o usuário e bloqueia a instalação nativa. Se o Flatpak não estiver instalado, será necessário instalá-lo manualmente; a instalação de pacotes e outras integrações específicas da distro não são garantidas. O monitor virtual continua funcionando com o Sunshine Flatpak desde que os pacotes do host sejam instalados manualmente (`krfb`, `libkscreen`, `jq` para KDE; `jq`, `util-linux` para Hyprland). O aviso também lista os recursos disponíveis para a sessão KDE Plasma ou Hyprland detectada. Somente o Debian 13 (trixie) permite instalação nativa; as outras versões do Debian usam Flatpak. O estado imutável é detectado pelo ID da distribuição e pelas ferramentas do sistema; a instalação nativa é desativada em sistemas imutáveis detectados.

---

## 🛠️ Pré-requisitos do Sistema

### Requisitos Gerais
- **Usuário Padrão**: Execute o script como usuário comum (evite usar `sudo bash ...`). O script solicitará elevação de privilégios (`sudo`) apenas quando estritamente necessário.

### Requisitos para Monitor Virtual (Opção 2)
- **Ambiente de Trabalho**: KDE Plasma (Wayland) ou Hyprland (Wayland).
- **Pacotes Necessários**:
  - `jq`
- **KDE**: `krfb-virtualmonitor` (pacote `krfb`) e `kscreen-doctor` (pacote `libkscreen` no Fedora/Arch, `libkscreen-bin` no Debian/Ubuntu).
- **Hyprland**: `hyprctl` (fornecido pelo Hyprland — a API atual `hyprctl eval` / `hl.monitor` é obrigatória, presente nas versões recentes do compositor) e `flock` (pacote `util-linux`); execute a configuração dentro de uma sessão Hyprland ativa.
- **Distribuições não reconhecidas**: os pacotes do host necessários para o monitor virtual devem ser instalados manualmente com o gerenciador da distro. KDE requer `krfb`, `libkscreen` e `jq`; Hyprland requer `jq` e `util-linux` (além de uma sessão Hyprland ativa).
- *Nota para Distros Imutáveis*: As ferramentas do monitor virtual precisam estar disponíveis no host. Para KDE, instale `krfb`, `libkscreen` e `jq`; para Hyprland, instale `jq` (`hyprctl` vem com o Hyprland e `flock` com `util-linux`). Em sistemas com rpm-ostree:
  ```bash
  rpm-ostree install krfb libkscreen jq
  sudo systemctl reboot
  ```
  Para Hyprland em sistemas rpm-ostree, use `rpm-ostree install jq util-linux`. No openSUSE MicroOS, use `transactional-update pkg install krfb libkscreen jq` para KDE ou `transactional-update pkg install jq util-linux` para Hyprland e reinicie.

---

## 📋 Instalação e Uso

Conceda permissão de execução ao script antes de iniciar:

```bash
chmod +x sunshine-setup.sh
```

### 1. Modo Interativo
Execute o script sem argumentos para abrir o menu de seleção interativo:

```bash
./sunshine-setup.sh
```

### 2. Uso Direto via Linha de Comando (CLI)

| Comando | Descrição |
| :--- | :--- |
| `./sunshine-setup.sh install` | Menu interativo para seleção do método de instalação. |
| `./sunshine-setup.sh install --flatpak-system` | Força a instalação via Flatpak (Escopo do Sistema / `--system`; `--flatpak` é um alias). |
| `./sunshine-setup.sh install --flatpak-user` | Força a instalação via Flatpak (Escopo do Usuário / `--user`). |
| `./sunshine-setup.sh install --native` | Força instalação nativa (Bloqueado em sistemas imutáveis). |
| `./sunshine-setup.sh virtual-monitor` | Abre o menu do Monitor Virtual para adicionar ou remover a configuração. |
| `./sunshine-setup.sh vmon` | Adiciona/configura o monitor virtual para a sessão KDE Plasma ou Hyprland ativa. |
| `./sunshine-setup.sh remove` | Remove diretamente a configuração do monitor virtual. |
| `./sunshine-setup.sh fixes` | Abre o menu do Erro 503 para aplicar ou reverter a correção. |
| `./sunshine-setup.sh 503` | Aplica diretamente a correção do Erro 503. |
| `./sunshine-setup.sh 503-reset` | Reverte diretamente a correção do Erro 503. |
| `./sunshine-setup.sh keyboard` | Abre o menu de Idioma do Teclado (detecta o layout, corrige o layout da sessão e sincroniza o `locale` do Sunshine). |
| `./sunshine-setup.sh keyboard-apply` | Aplica o layout de teclado detectado e o `locale` correspondente sem perguntar. |
| `./sunshine-setup.sh keyboard-locale <locale>` | Define o `locale` (idioma da interface) do Sunshine no `sunshine.conf` (ex.: `pt_BR`); `kb`/`kb-apply`/`kb-locale` são apelidos. |
| `./sunshine-setup.sh firewall` | Configura as regras de portas no `firewalld` ou `ufw`. |
| `./sunshine-setup.sh service [--native\|--flatpak]` | Abre o menu de controle do serviço Sunshine (o escopo dispensa a detecção de modo). |
| `./sunshine-setup.sh start\|stop\|restart\|enable\|disable\|status\|logs\|follow [--native\|--flatpak]` | Controla ou consulta o serviço de usuário do Sunshine. |
| `./sunshine-setup.sh repair [--native|--flatpak]` | Repara a configuração de inicialização do serviço Sunshine. |
| `./sunshine-setup.sh --help` | Exibe as opções de ajuda e instruções do script. |
| `./sunshine-setup.sh --version` | Exibe a versão do script. |

O menu interativo agrupa ações relacionadas em **Monitor Virtual** (adicionar/remover), **Correções do Erro 503** (aplicar/reverter) e **Idioma do Teclado** (detectar/escolher o layout e o idioma da interface). Os backends do monitor virtual ficam organizados em `modules/vmon/kde/` e `modules/vmon/hyprland/`; o dispatcher compartilhado está em `modules/vmon/dispatch.sh`.

---

## 🖥️ Instruções de Configuração do Monitor Virtual

Para habilitar a troca dinâmica de resolução durante o streaming com o Moonlight:

1. Execute a configuração a partir da sessão de desktop desejada:
   ```bash
   ./sunshine-setup.sh vmon
   ```
2. Acesse a interface web do Sunshine no navegador: `https://localhost:47990`
3. Navegue até **Configuration > Audio/Video**.
4. No **KDE Plasma**, defina **Capture Method** como **`KWin Screencast`**.
   No **Hyprland**, a configuração seleciona **`wlr`** e cria a saída headless quando o app Sunshine inicia.
5. Salve as alterações e reinicie o serviço Sunshine para recarregar a configuração:
   - **Para Flatpak**: `systemctl --user restart app-dev.lizardbyte.app.Sunshine`
   - **Para instalação nativa**: `./sunshine-setup.sh restart --native`
6. No Moonlight, inicie o app Sunshine **Virtual Monitor** (KDE) ou **Virtual Monitor (Hyprland)**. Os hooks do monitor são executados para esse app; iniciar outro app Sunshine não os executa.

O backend KDE registra quais telas físicas estavam habilitadas e restaura essas telas e o `output_name` original ao encerrar a sessão do app de monitor virtual. O backend Hyprland cria a saída headless para a sessão de captura do app, ajusta o modo conforme a resolução e a taxa de quadros pedidas pelo Moonlight, desativa temporariamente as telas físicas, confirma que cada uma ficou inativa antes de continuar a captura e restaura modo, posição, escala e transformação anteriores ao encerrar a sessão. Ele remove somente a saída criada por si. O hook de início independente desfaz a criação de uma saída caso a inicialização falhe. Ao remover a configuração, restaura os valores anteriores de `capture` e `output_name`.

A configuração do Hyprland deve ser feita em uma sessão Hyprland ativa. Ela pode ser removida depois a partir de qualquer desktop compatível; a remoção identifica qual backend está configurado.

---

## 🧪 Testes

Execute a suíte portátil com Bash e `jq` instalados:

```bash
bash tests/run.sh
```

A suíte cobre seleção de distribuição e desktop, validação de CIDR, helpers do serviço e do Erro 503, e os hooks nativos/Flatpak do Hyprland e do KDE com dublês de teste (*test doubles*) com estado. O `tests/run.sh` também executa o `tests/cli-smoke.sh` (verificações de ponta a ponta do script real com HOME isolado) quando não roda como root. O CI ainda faz lint de todos os scripts com ShellCheck e roda a suíte em containers bash 4.4 e 5.0. Ela não substitui testes de captura e saída headless em uma sessão Hyprland real.

---

## 🛡️ Configuração de Firewall

O Sunshine requer portas específicas para funcionar. Execute o utilitário de firewall para detectar e liberar as portas no seu sistema automaticamente:

```bash
./sunshine-setup.sh firewall
```

**Portas Configuradas:**
- **TCP**: `47984`, `47989`, `48010` *(Opcional: `47990` para a Interface Web na rede local)*
- **UDP**: `47998`, `47999`, `48000`, `48002`
- **mDNS**: `5353/udp` *(para descoberta automática pelo Moonlight)*

Durante a configuração, é possível restringir as regras a um CIDR de origem (por exemplo, `192.168.1.0/24` ou `fd00::/64`). Deixe o campo vazio para permitir acesso de qualquer origem. A exposição da interface Web é uma opção separada. Regras irrestritas existentes não são removidas; confira as regras atuais antes de depender da nova restrição por CIDR.

---

## 📄 Licença

Distribuído sob a Licença MIT. Sinta-se à vontade para modificar e adaptar o script em suas imagens personalizadas ou rotinas pós-instalação de distribuições.
