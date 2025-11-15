# Scripts de Automação para Servidores EC2 - Debian 13

Conjunto de scripts shell para automatizar a instalação e configuração de servidores web na AWS EC2 rodando Debian 13, com suporte a múltiplas versões do PHP, Nginx, Docker e banco de dados.

## 📋 Índice

- [Scripts Disponíveis](#scripts-disponíveis)
- [Pré-requisitos](#pré-requisitos)
- [Considerações de Segurança](#considerações-de-segurança)
- [Instalação Inicial](#instalação-inicial)
- [Uso dos Scripts](#uso-dos-scripts)
- [Estrutura de Diretórios](#estrutura-de-diretórios)

---

## 🔒 Considerações de Segurança

⚠️ **IMPORTANTE:** Estes scripts são fornecidos para automação de setup inicial. Tome as seguintes precauções:

### Antes de publicar/usar:

1. **Nome do usuário admin**: Por padrão, o script usa o usuário `admin`. Se sua EC2 usa outro nome (`ubuntu`, `ec2-user`, etc.), edite a variável `USER_ADMIN` no início do `setup-ec2-debian13.sh`:
   ```bash
   # Linha 14 do setup-ec2-debian13.sh
   USER_ADMIN="seu_usuario_aqui"
   ```

2. **Não commitar credenciais**: Nunca adicione arquivos `.env`, chaves SSH (`*.pem`) ou `mysql-*-info.txt` ao Git
   - Use o `.gitignore` fornecido

3. **Proteger arquivos de senha**: O script `create-mysql57-container.sh` gera `/root/mysql-{container}-info.txt` com senhas em texto plano
   - **Anote as credenciais em local seguro** (gerenciador de senhas)
   - **Delete o arquivo** após anotar: `sudo rm /root/mysql-*-info.txt`

4. **Validação de inputs**: Os scripts validam caracteres especiais para prevenir injeção de comandos
   - Use apenas letras, números, hífens e underscores em nomes

5. **ACLs e permissões**: O usuário configurado em `USER_ADMIN` terá acesso total a `/sistemas`
   - Use senha forte e autenticação por chave SSH
   - Considere habilitar 2FA na AWS

6. **Senhas fortes**: Use senhas complexas para MySQL/MariaDB (mínimo 16 caracteres, com letras maiúsculas, minúsculas, números e símbolos)

7. **Firewall**: O script instala UFW (desabilitado por padrão)
   - **Recomendado habilitar** após instalação:
     ```bash
     sudo ufw enable
     sudo ufw status
     ```
   - Portas já configuradas: 22 (SSH), 80 (HTTP), 443 (HTTPS)

8. **Atualizações**: Mantenha o sistema atualizado:
   ```bash
   sudo apt-get update && sudo apt-get upgrade -y
   ```

9. **Certificados SSL**: Configure HTTPS com Let's Encrypt após criar sites:
   ```bash
   sudo apt-get install certbot python3-certbot-nginx
   sudo certbot --nginx -d seusite.com
   ```

10. **Monitoramento**: Configure logs e alertas na AWS CloudWatch para atividades suspeitas

### Por que ACLs em vez de apenas grupos?

ACLs (Access Control Lists) permitem controle granular de permissões:
- **Dono permanece `www-data:www-data`** (necessário para Nginx/PHP-FPM)
- **Usuário admin tem acesso total** via ACL (leitura, escrita, execução)
- **Novos arquivos herdam permissões** automaticamente (ACL padrão)

Alternativa simples (sem ACL):
```bash
# Adicionar usuário ao grupo www-data (já feito pelo script)
sudo usermod -aG www-data $USER

# Relogar para aplicar
exit
# SSH novamente
```

---

## 🛠️ Scripts Disponíveis

### 1. `setup-ec2-debian13.sh`

**Descrição:** Script principal de instalação do ambiente EC2. Instala e configura todos os componentes necessários para rodar aplicações web PHP com Nginx.

**O que instala:**
- Nginx (servidor web)
- PHP 5.6, 7.4 e 8.4 com PHP-FPM e extensões
- Composer (padrão e versão específica para PHP 5.6)
- Docker Engine + Docker Compose
- MariaDB Server (padrão, opcional)
- Node.js (via NVM) + NPM
- Supervisor (gerenciador de processos)
- zbar-tools (leitura de códigos de barras)
- ACL (controle avançado de permissões)

**Configurações adicionais:**
- Cria estrutura de diretórios em `/sistemas/apps` e `/sistemas/logs`
- Adiciona usuário `admin` aos grupos `docker` e `www-data`
- Configura ACLs para que `admin` tenha acesso total a `/sistemas` mantendo propriedade `www-data:www-data`

**Uso:**

```bash
# Instalar com MariaDB (padrão)
sudo ./setup-ec2-debian13.sh

# Instalar sem MariaDB (apenas Docker para MySQL)
sudo ./setup-ec2-debian13.sh --no-mariadb
```

**Versões PHP disponíveis após instalação:**
- `php5.6` - Para aplicações legadas
- `php7.4` - Para projetos Laravel 5.x/6.x
- `php8.4` - Para projetos modernos Laravel 9+

**Composers disponíveis:**
- `composer` - Usa PHP padrão do sistema (8.4)
- `composer56` - Força uso do PHP 5.6 (para projetos antigos)

---

### 2. `create-site.sh`

**Descrição:** Automatiza a criação de novos sites no Nginx com configuração de PHP-FPM e suporte a Laravel.

**Funcionalidades:**
- Cria diretório do site em `/sistemas/apps/{dominio}`
- Cria diretório de logs em `/sistemas/logs/{dominio}`
- Gera configuração Nginx otimizada
- Configura PHP-FPM com socket Unix
- Suporte a estrutura Laravel (diretório `/public`)
- Ativa o site automaticamente
- Testa configuração do Nginx antes de aplicar
- Rollback automático em caso de erro

**Uso:**

```bash
# Site padrão (root no diretório principal)
sudo ./create-site.sh exemplo.com 84

# Site Laravel (root em /public)
sudo ./create-site.sh exemplo.com 84 --laravel

# Exemplos com diferentes versões PHP:
sudo ./create-site.sh legado.com 56           # PHP 5.6
sudo ./create-site.sh app.com 74 --laravel    # PHP 7.4 + Laravel
sudo ./create-site.sh novo.com 84 --laravel   # PHP 8.4 + Laravel
```

**Parâmetros:**
- `<dominio>` - URL do site (ex: exemplo.com)
- `<versao-php>` - Versão PHP: `56`, `74` ou `84`
- `--laravel` - (Opcional) Configura root para `/public`

**Após execução:**
1. Adicione o domínio ao DNS ou `/etc/hosts`
2. Acesse `http://dominio` (deve mostrar `phpinfo()`)
3. Faça upload da aplicação para `/sistemas/apps/{dominio}`
4. Configure SSL: `sudo certbot --nginx -d dominio`

---

### 3. `remove-site.sh`

**Descrição:** Remove sites do Nginx com backup automático timestampado.

**Funcionalidades:**
- Solicita confirmação antes de remover
- Faz backup do site com timestamp (`.YYYYMMDDHHMMSS.old`)
- Remove configurações do Nginx
- Recarrega Nginx automaticamente
- Mantém os arquivos em backup caso precise restaurar

**Uso:**

```bash
sudo ./remove-site.sh exemplo.com
```

**O script perguntará:**
```
Tem certeza que deseja remover o site 'exemplo.com'? (s/N):
```

**Arquivos de backup criados:**
- `/sistemas/apps/exemplo.com.20250115143022.old/` - Diretório do site
- `/sistemas/logs/exemplo.com.20250115143022.old/` - Logs do site

**Para restaurar um site removido:**

```bash
# Encontrar o backup
ls -la /sistemas/apps/*.old

# Restaurar
sudo mv /sistemas/apps/exemplo.com.20250115143022.old /sistemas/apps/exemplo.com
sudo mv /sistemas/logs/exemplo.com.20250115143022.old /sistemas/logs/exemplo.com

# Recriar configuração
sudo ./create-site.sh exemplo.com 84 --laravel
```

---

### 4. `create-mysql57-container.sh`

**Descrição:** Cria containers Docker isolados do MySQL 5.7 para aplicações legadas, com limites de recursos e configuração interativa.

**Funcionalidades:**
- Instalação interativa (pergunta nome, porta, banco, usuário, senhas)
- MySQL 5.7 (compatível com aplicações antigas)
- Dados persistentes em volume Docker
- Inicialização automática com o sistema (`--restart=always`)
- Limites de recursos (256MB RAM, 0.5 CPU)
- Charset UTF-8mb4
- Portas customizáveis (evita conflito com MariaDB na porta 3306)
- Gera arquivo de informações com strings de conexão

**Uso:**

```bash
sudo ./create-mysql57-container.sh
```

**O script solicitará:**
- Nome do container (ex: `mysql-57-app1`)
- Porta no host (ex: `3307`)
- Nome do banco de dados
- Usuário MySQL
- Senha do usuário
- Senha do root

**Exemplo de configuração:**
```
Nome do container: mysql-57-legado
Porta: 3307
Banco: meu_sistema
Usuário: app_user
Senha: ********
Root password: ********
```

**String de conexão Laravel (`.env`):**
```env
DB_CONNECTION=mysql
DB_HOST=127.0.0.1
DB_PORT=3307
DB_DATABASE=meu_sistema
DB_USERNAME=app_user
DB_PASSWORD=sua_senha
```

**Limites de recursos aplicados:**
- Memória: 256MB (rígido)
- CPU: 0.5 (50% de 1 core)
- Swap: 256MB

**Comandos úteis gerados:**
```bash
# Ver uso de recursos
sudo docker stats mysql-57-legado

# Acessar MySQL CLI
sudo docker exec -it mysql-57-legado mysql -u app_user -p meu_sistema

# Backup
sudo docker exec mysql-57-legado mysqldump -u root -p meu_sistema > backup.sql

# Restaurar
sudo docker exec -i mysql-57-legado mysql -u root -p meu_sistema < backup.sql
```

**Arquivo de informações:** `/root/mysql-{nome-container}-info.txt`

---

## 📦 Pré-requisitos

- AWS EC2 com Debian 13
- Acesso root ou sudo
- Conexão à internet
- Mínimo 2GB RAM (recomendado para t3a.small ou superior)

---

## 🚀 Instalação Inicial

### 1. Conectar na EC2

```bash
ssh -i sua-chave.pem admin@ip-da-ec2
```

### 2. Clonar o repositório

```bash
cd ~
git clone https://github.com/seu-usuario/ec2-web-server.git
cd ec2-web-server
```

### 3. Dar permissão de execução

```bash
chmod +x setup-ec2-debian13.sh
chmod +x create-site.sh
chmod +x remove-site.sh
chmod +x create-mysql57-container.sh
```

### 4. Executar instalação principal

```bash
sudo ./setup-ec2-debian13.sh
```

**Aguarde:** A instalação completa leva cerca de 5-10 minutos.

### 5. Recarregar grupos do usuário

```bash
# Para usar Docker sem sudo
newgrp docker

# Ou fazer logout/login
exit
ssh -i sua-chave.pem admin@ip-da-ec2
```

---

## 📖 Uso dos Scripts

### Fluxo típico de trabalho

#### 1. Instalar ambiente (apenas uma vez)

```bash
sudo ./setup-ec2-debian13.sh
```

#### 2. Criar container MySQL (se necessário)

```bash
sudo ./create-mysql57-container.sh
# Informar: mysql-57-app1, porta 3307, etc.
```

#### 3. Criar novo site

```bash
# Aplicação Laravel com PHP 8.4
sudo ./create-site.sh meusite.com 84 --laravel
```

#### 4. Fazer deploy da aplicação

```bash
cd /sistemas/apps/meusite.com

# Clonar repositório
sudo -u www-data git clone https://github.com/usuario/projeto.git .

# Instalar dependências
sudo -u www-data composer install --no-dev

# Configurar .env
sudo -u www-data cp .env.example .env
sudo -u www-data nano .env

# Gerar chave
sudo -u www-data php artisan key:generate

# Rodar migrations
sudo -u www-data php artisan migrate

# Ajustar permissões
sudo chown -R www-data:www-data /sistemas/apps/meusite.com
sudo chmod -R 755 /sistemas/apps/meusite.com
```

#### 5. Configurar SSL

```bash
sudo apt-get install certbot python3-certbot-nginx
sudo certbot --nginx -d meusite.com -d www.meusite.com
```

#### 6. Remover site (quando necessário)

```bash
sudo ./remove-site.sh meusite.com
```

---

## 📁 Estrutura de Diretórios

```
/sistemas/
├── apps/                          # Aplicações web
│   ├── exemplo.com/              # Site padrão
│   │   └── index.php
│   └── laravel.com/              # Site Laravel
│       ├── app/
│       ├── public/               # Root do Nginx
│       ├── .env
│       └── ...
└── logs/                          # Logs do Nginx
    ├── exemplo.com/
    │   ├── access.log
    │   └── error.log
    └── laravel.com/
        ├── access.log
        └── error.log

/etc/nginx/
├── sites-available/               # Configurações disponíveis
│   ├── exemplo.com.conf
│   └── laravel.com.conf
└── sites-enabled/                 # Configurações ativas (symlinks)
    ├── exemplo.com.conf -> ../sites-available/exemplo.com.conf
    └── laravel.com.conf -> ../sites-available/laravel.com.conf

/var/lib/mysql-containers/         # Dados persistentes dos containers MySQL
└── mysql-57-app1/
    └── [arquivos do MySQL]

/root/
└── mysql-mysql-57-app1-info.txt  # Informações de conexão
```

---

## 🔧 Comandos Úteis

### Gerenciar Nginx

```bash
# Testar configuração
sudo nginx -t

# Recarregar (sem downtime)
sudo systemctl reload nginx

# Reiniciar
sudo systemctl restart nginx

# Ver status
sudo systemctl status nginx

# Ver logs em tempo real
sudo tail -f /sistemas/logs/site.com/error.log
```

### Gerenciar PHP-FPM

```bash
# Verificar versões instaladas
php5.6 -v
php7.4 -v
php8.4 -v

# Reiniciar PHP-FPM
sudo systemctl restart php5.6-fpm
sudo systemctl restart php7.4-fpm
sudo systemctl restart php8.4-fpm

# Ver status
sudo systemctl status php8.4-fpm

# Ver sockets ativos
ls -la /run/php/
```

### Gerenciar Docker

```bash
# Listar containers
docker ps -a

# Ver uso de recursos
docker stats

# Logs de um container
docker logs mysql-57-app1

# Parar/Iniciar
docker stop mysql-57-app1
docker start mysql-57-app1

# Remover container
docker stop mysql-57-app1
docker rm mysql-57-app1
```

### Gerenciar MariaDB

```bash
# Acessar como root
sudo mysql

# Configuração inicial segura
sudo mysql_secure_installation

# Ver status
sudo systemctl status mariadb
```

---

## 🐛 Troubleshooting

### Erro: "502 Bad Gateway"

**Causa:** PHP-FPM não está rodando ou socket incorreto.

```bash
# Verificar se PHP-FPM está ativo
sudo systemctl status php8.4-fpm

# Verificar socket
ls -la /run/php/php8.4-fpm.sock

# Reiniciar
sudo systemctl restart php8.4-fpm
sudo systemctl reload nginx
```

### Erro: "Permission denied" ao fazer deploy

**Causa:** Arquivos não pertencem ao `www-data`.

```bash
# Corrigir permissões
sudo chown -R www-data:www-data /sistemas/apps/site.com
sudo chmod -R 755 /sistemas/apps/site.com

# Storage e cache (Laravel)
sudo chmod -R 775 /sistemas/apps/site.com/storage
sudo chmod -R 775 /sistemas/apps/site.com/bootstrap/cache
```

### Laravel não conecta ao MySQL Docker

**Causa:** `.env` usando `localhost` em vez de `127.0.0.1`.

```bash
# Editar .env
DB_HOST=127.0.0.1
DB_PORT=3307

# Limpar cache
php artisan config:clear
php artisan cache:clear
```

### Container MySQL não inicia após reboot

**Causa:** Docker daemon não está habilitado.

```bash
# Habilitar Docker
sudo systemctl enable docker
sudo systemctl start docker

# Verificar containers
docker ps -a
```

---

## 📝 Notas Importantes

1. **Backups:** Os scripts não fazem backup automático de banco de dados. Configure backups regulares:
   ```bash
   # Exemplo de backup diário (crontab)
   0 2 * * * docker exec mysql-57-app1 mysqldump -u root -pSENHA banco > /backups/banco-$(date +\%Y\%m\%d).sql
   ```

2. **Firewall:** Configure o Security Group da EC2 para permitir:
   - Porta 22 (SSH)
   - Porta 80 (HTTP)
   - Porta 443 (HTTPS)

3. **SSL:** Certbot renova certificados automaticamente. Verifique:
   ```bash
   sudo certbot renew --dry-run
   ```

4. **Recursos:** Em instâncias pequenas (t3a.small), monitore uso de recursos:
   ```bash
   htop
   docker stats
   ```

5. **Segurança:** 
   - Altere senhas padrão
   - Use chaves SSH em vez de senhas
   - Mantenha o sistema atualizado: `sudo apt-get update && sudo apt-get upgrade`

---

## 📄 Licença

Scripts de uso livre. Sem garantias. Use por sua conta e risco.

---

## 🤝 Contribuições

Sinta-se livre para abrir issues ou pull requests com melhorias!

---

## 📧 Suporte

Para dúvidas ou problemas, abra uma issue no repositório.
