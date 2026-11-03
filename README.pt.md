> **Nota:** Este projeto foi vibe-coded com auxílio de IA.

# Script de Configuração do Sunshine para Linux

Script automatizado de instalação e configuração do [Sunshine](https://github.com/LizardByte/Sunshine) (servidor de streaming de jogos) e de monitor virtual para KDE Plasma (Wayland) em distribuições Linux tradicionais e sistemas imutáveis/atômicos.

Portado e aprimorado a partir das receitas `setup-sunshine` e scripts de automação de monitor virtual do projeto **Bazzite**.

---

## 🚀 Funcionalidades

- **Suporte Multidistro Nativo**:
  - **Fedora**: Instalado via COPR (`lizardbyte/stable`).
  - **Arch Linux**: Instalado via AUR (`sunshine-bin`) utilizando `yay` ou `paru`.
  - **CachyOS**: Instalado via repositórios oficiais (`pacman -S sunshine`).
  - **Ubuntu / Debian**: Obtém e instala automaticamente pacotes `.deb` compatíveis diretamente do repositório upstream.
- **Proteção para Sistemas Imutáveis**:
  - Compatibilidade completa com **Fedora Silverblue**, **Kinoite**, **Bazzite**, **Bluefin**, **Aurora**, **SteamOS**, **openSUSE MicroOS**, `bootc` e outros sistemas atômicos.
  - Execução de gerenciadores de pacotes nativos (`dnf`, `pacman`, `apt`) é **estritamente bloqueada** em sistemas imutáveis.
  - Redirecionamento automático para instalação via **Flatpak**.
- **Escopos Flexíveis no Flatpak**:
  - Permite escolher o escopo de instalação do Flatpak: `--system` (global) ou `--user` (apenas para o usuário atual).
- **Integração com Monitor Virtual**:
  - Automação para disponibilização de telas virtuais no KDE Plasma (Wayland) usando `krfb-virtualmonitor` e `kscreen-doctor`.
  - Ajuste dinâmico de resolução e taxa de quadros de acordo com o cliente Moonlight (SUNSHINE_CLIENT_WIDTH / HEIGHT / FPS).
  - Salva quais telas estavam habilitadas e o `output_name` original do Sunshine; restaura ambos ao parar e desfaz uma inicialização malsucedida.
- **Correções e Ferramentas de Manutenção**:
  - **Correção do Erro 503**: Adiciona `KWIN_WAYLAND_NO_PERMISSION_CHECKS=1` em um arquivo dedicado; `503-reset` remove a configuração.
  - **Configuração de Firewall**: Detecta `firewalld` ou `ufw` e libera as portas necessárias para streaming e mDNS, com opção de restringir a um CIDR IPv4/IPv6.
  - **Desinstalação Limpa**: Remove scripts de monitor virtual, ganchos pós-execução do systemd e configurações da aplicação Sunshine.

---

## 🐧 Distribuições Suportadas

| Tipo de Distribuição | Distribuições / Sistemas Suportados | Método de Instalação Permitido |
| :--- | :--- | :--- |
| **Distribuições Tradicionais** | Fedora, Arch Linux, CachyOS, Ubuntu, Debian | Pacote Nativo **ou** Flatpak |
| **Imutáveis / Atômicas** | Bazzite, Silverblue, Kinoite, SteamOS, Bluefin, Aurora, openSUSE MicroOS | **Apenas Flatpak** (`--system` / `--user`) |

---

## 🛠️ Pré-requisitos do Sistema

### Requisitos Gerais
- **Usuário Padrão**: Execute o script como usuário comum (evite usar `sudo bash ...`). O script solicitará elevação de privilégios (`sudo`) apenas quando estritamente necessário.

### Requisitos para Monitor Virtual (Opção 2)
- **Ambiente de Trabalho**: **KDE Plasma 6 (Wayland)**.
- **Pacotes Necessários**:
  - `krfb-virtualmonitor` (integrante do pacote `krfb`)
  - `kscreen-doctor` (integrante do pacote `libkscreen` / `kscreen`)
  - `jq`
- *Nota para Distros Imutáveis*: O script verifica a presença desses binários no sistema base. Caso algum esteja ausente, instale-os via `rpm-ostree` e reinicie o sistema:
  ```bash
  rpm-ostree install krfb kscreen jq
  sudo systemctl reboot
  ```

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
| `./sunshine-setup.sh install --flatpak-system` | Força a instalação via Flatpak (Escopo do Sistema / `--system`). |
| `./sunshine-setup.sh install --flatpak-user` | Força a instalação via Flatpak (Escopo do Usuário / `--user`). |
| `./sunshine-setup.sh install --native` | Força instalação nativa (Bloqueado em sistemas imutáveis). |
| `./sunshine-setup.sh virtual-monitor` | Abre o menu do Monitor Virtual para adicionar ou remover a configuração. |
| `./sunshine-setup.sh vmon` | Adiciona/configura diretamente a automação de monitor virtual no KDE Plasma. |
| `./sunshine-setup.sh remove` | Remove diretamente a configuração do monitor virtual. |
| `./sunshine-setup.sh fixes` | Abre o menu do Erro 503 para aplicar ou reverter a correção. |
| `./sunshine-setup.sh 503` | Aplica diretamente a correção do Erro 503. |
| `./sunshine-setup.sh 503-reset` | Reverte diretamente a correção do Erro 503. |
| `./sunshine-setup.sh firewall` | Configura as regras de portas no `firewalld` ou `ufw`. |
| `./sunshine-setup.sh --help` | Exibe as opções de ajuda e instruções do script. |

O menu interativo agrupa ações relacionadas em **Monitor Virtual** (adicionar/remover) e **Correções do Erro 503** (aplicar/reverter). As funções e a seleção compartilhada do modo do Sunshine estão separadas nos arquivos dentro de `modules/`, carregados pelo script principal.

---

## 🖥️ Instruções de Configuração do Monitor Virtual

Para habilitar a troca dinâmica de resolução durante o streaming com o Moonlight:

1. Execute a configuração do monitor virtual:
   ```bash
   ./sunshine-setup.sh vmon
   ```
2. Acesse a interface web do Sunshine no navegador: `https://localhost:47990`
3. Navegue até **Configuration > Audio/Video**.
4. Altere o parâmetro **Capture Method** para **`KWin Screencast`**.
5. Salve as alterações e reinicie o serviço do Sunshine:
   - **Para Flatpak**: `systemctl --user restart app-dev.lizardbyte.app.Sunshine`
   - **Para Instalação Nativa**: `systemctl --user restart sunshine`

O script registra quais telas físicas estavam habilitadas antes da criação da tela virtual e restaura essas telas e o `output_name` original ao parar o Sunshine. Se a inicialização falhar, ele tenta fazer a mesma restauração.

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
