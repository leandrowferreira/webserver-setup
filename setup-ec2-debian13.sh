#!/bin/bash
set -e

# Script de instalação para EC2 Debian 13
# Instala: Nginx, PHP (5.6, 7.4, 8.4), Docker, MariaDB (padrão)
# Uso: ./setup-ec2-debian13.sh [--no-mariadb]

# ============================================================================
# CONFIGURAÇÕES
# ============================================================================
# Nome do usuário que terá acesso ao Docker e /sistemas
# Altere para o usuário da sua EC2 se diferente de 'admin'
# Exemplos: ubuntu (Ubuntu AMI), ec2-user (Amazon Linux), admin (Debian)
USER_ADMIN="admin"
# ============================================================================

# Verificar se está rodando como root
if [ "$EUID" -ne 0 ]; then 
    echo "Este script precisa ser executado como root (su ou sudo)"
    exit 1
fi

# Verificar flag --no-mariadb
INSTALL_MARIADB=true
if [ "$#" -eq 1 ] && [ "$1" == "--no-mariadb" ]; then
    INSTALL_MARIADB=false
fi

echo "======================================"
echo "  Instalação EC2 - Debian 13"
echo "======================================"
echo "MariaDB: $([ "$INSTALL_MARIADB" = true ] && echo "SIM (padrão)" || echo "NÃO (--no-mariadb)")"
echo "Usuário: $USER_ADMIN"
echo ""

# Atualizar sistema
echo "[1/13] Atualizando sistema..."
apt-get update
apt-get upgrade -y

# Instalar dependências básicas
echo "[2/13] Instalando dependências básicas..."
apt-get install -y \
    apt-transport-https \
    ca-certificates \
    curl \
    gnupg \
    lsb-release \
    wget \
    git \
    unzip \
    supervisor \
    zbar-tools \
    acl \
    cron

# Adicionar repositório Sury para múltiplas versões de PHP
echo "[3/13] Adicionando repositório Sury..."
wget -O /etc/apt/trusted.gpg.d/php.gpg https://packages.sury.org/php/apt.gpg
echo "deb https://packages.sury.org/php/ $(lsb_release -sc) main" > /etc/apt/sources.list.d/php.list
apt-get update

# Instalar Nginx
echo "[4/13] Instalando Nginx..."
apt-get install -y nginx

# Instalar PHP 5.6 e extensões
echo "[5/13] Instalando PHP 5.6..."
apt-get install -y \
    php5.6-fpm \
    php5.6-cli \
    php5.6-common \
    php5.6-mysql \
    php5.6-gd \
    php5.6-imagick \
    php5.6-curl \
    php5.6-xml \
    php5.6-mbstring \
    php5.6-json \
    php5.6-zip \
    php5.6-bcmath \
    php5.6-soap \
    php5.6-intl \
    php5.6-readline \
    php5.6-mcrypt

# Instalar PHP 7.4 e extensões
echo "[6/13] Instalando PHP 7.4..."
apt-get install -y \
    php7.4-fpm \
    php7.4-cli \
    php7.4-common \
    php7.4-mysql \
    php7.4-gd \
    php7.4-imagick \
    php7.4-curl \
    php7.4-xml \
    php7.4-mbstring \
    php7.4-json \
    php7.4-zip \
    php7.4-bcmath \
    php7.4-soap \
    php7.4-intl \
    php7.4-readline

# Instalar PHP 8.4 e extensões
echo "[7/13] Instalando PHP 8.4..."
apt-get install -y \
    php8.4-fpm \
    php8.4-cli \
    php8.4-common \
    php8.4-mysql \
    php8.4-gd \
    php8.4-imagick \
    php8.4-curl \
    php8.4-xml \
    php8.4-mbstring \
    php8.4-zip \
    php8.4-bcmath \
    php8.4-soap \
    php8.4-intl \
    php8.4-readline

# Instalar Composer
echo "[8/13] Instalando Composer..."
curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer

# Instalar Composer para PHP 5.6
echo "   Instalando Composer para PHP 5.6 (composer56)..."
curl -sS https://getcomposer.org/installer | php5.6 -- --install-dir=/usr/local/bin --filename=composer56.phar

# Criar wrapper script para composer56 usar php5.6
cat > /usr/local/bin/composer56 << 'EOF'
#!/bin/bash
/usr/bin/php5.6 /usr/local/bin/composer56.phar "$@"
EOF
chmod +x /usr/local/bin/composer56

# Instalar NVM e Node.js
echo "[9/13] Instalando NVM e Node.js..."
# Instalar NVM para root
export NVM_DIR="/root/.nvm"
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash

# Carregar NVM
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"

# Instalar Node.js LTS
nvm install --lts
nvm use --lts
nvm alias default 'lts/*'

# Tornar npm/node acessível globalmente via link simbólico
NODE_PATH=$(which node)
NPM_PATH=$(which npm)
ln -sf "$NODE_PATH" /usr/local/bin/node
ln -sf "$NPM_PATH" /usr/local/bin/npm

echo "✓ NVM, Node.js e NPM instalados"

# Instalar MariaDB (se solicitado)
if [ "$INSTALL_MARIADB" = true ]; then
    echo "[10/13] Instalando MariaDB Server..."
    apt-get install -y mariadb-server mariadb-client
    
    # Iniciar e habilitar MariaDB
    systemctl start mariadb
    systemctl enable mariadb
    
    echo "✓ MariaDB instalado"
    echo "  Execute 'mysql_secure_installation' para configurar"
else
    echo "[10/13] Pulando instalação do MariaDB..."
fi

# Instalar Docker e Docker Compose
echo "[11/13] Instalando Docker..."
# Adicionar chave GPG do Docker
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc

# Adicionar repositório Docker
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  tee /etc/apt/sources.list.d/docker.list > /dev/null

apt-get update
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# Iniciar e habilitar Docker
systemctl start docker
systemctl enable docker

# Instalar Certbot para SSL
echo "[12/13] Instalando Certbot (Let's Encrypt)..."
apt-get install -y certbot python3-certbot-nginx

# Garantir que o serviço cron está rodando
systemctl enable cron
systemctl start cron

# Configurar renovação automática via cron
# Verifica semanalmente (segundas-feiras às 3h da manhã)
# Janela de renovação: certificados válidos por 90 dias, renova aos 30 dias restantes = 60 dias de margem
# Verificação semanal é mais do que suficiente
echo "   Configurando renovação automática de certificados..."
(crontab -l 2>/dev/null || true; echo "0 3 * * 1 /usr/bin/certbot renew --quiet --nginx >> /var/log/certbot-renew.log 2>&1") | crontab -

echo "✓ Certbot instalado com renovação automática (segundas-feiras às 3h)"
echo "  Para configurar SSL: sudo certbot --nginx -d seudominio.com"
echo "  Log de renovação: /var/log/certbot-renew.log"

# Instalar e configurar UFW (desabilitado por padrão)
echo "[13/13] Instalando UFW (firewall)..."
apt-get install -y ufw

# Configurar regras padrão
ufw default deny incoming
ufw default allow outgoing

# Permitir SSH, HTTP, HTTPS
ufw allow 22/tcp comment 'SSH'
ufw allow 80/tcp comment 'HTTP'
ufw allow 443/tcp comment 'HTTPS'

echo "✓ UFW instalado e configurado (DESABILITADO por padrão)"
echo "  Para habilitar: sudo ufw enable"
echo "  Para ver status: sudo ufw status"

# Criar estrutura de diretórios
echo ""
echo "Criando estrutura de diretórios..."
mkdir -p /sistemas/logs
mkdir -p /sistemas/apps

# Ajustar permissões (grupo com escrita)
chown -R www-data:www-data /sistemas
chmod -R 775 /sistemas

# Adicionar usuário aos grupos 'docker' e 'www-data' se existir,
# e conceder acesso livre a /sistemas mantendo a propriedade www-data:www-data.
if id -u "$USER_ADMIN" >/dev/null 2>&1; then
    echo "Adicionando usuário '$USER_ADMIN' aos grupos 'docker' e 'www-data'..."
    usermod -aG docker,www-data "$USER_ADMIN" || true

    echo "Aplicando ACLs para dar ao '$USER_ADMIN' acesso completo a /sistemas..."
    # Recursivamente garantir que o usuário tenha rwx e que novos arquivos herdem a ACL
    setfacl -R -m u:"$USER_ADMIN":rwx /sistemas || true
    setfacl -R -d -m u:"$USER_ADMIN":rwx /sistemas || true
    # Garantir que a máscara ACL permita rwx
    setfacl -R -m m::rwx /sistemas || true
    setfacl -R -d -m m::rwx /sistemas || true
else
    echo "Usuário '$USER_ADMIN' não encontrado. Para adicionar depois execute: sudo usermod -aG docker,www-data $USER_ADMIN"
fi

# Informações de instalação
echo ""
echo "======================================"
echo "  Instalação Concluída!"
echo "======================================"
echo ""
echo "Componentes instalados:"
echo "------------------------"
echo "✓ Nginx"
echo "✓ PHP 5.6, 7.4, 8.4 com PHP-FPM"
echo "✓ Composer (padrão e composer56 para PHP 5.6)"
echo "✓ Docker + Docker Compose"
echo "✓ Node.js + NPM (via NVM)"
echo "✓ Supervisor"
echo "✓ zbar-tools"
echo "✓ UFW (firewall, desabilitado)"
echo "✓ Certbot (Let's Encrypt para SSL)"
if [ "$INSTALL_MARIADB" = true ]; then
    echo "✓ MariaDB Server"
fi
echo ""
echo "Sockets PHP-FPM:"
echo "----------------"
echo "PHP 5.6: /run/php/php5.6-fpm.sock"
echo "PHP 7.4: /run/php/php7.4-fpm.sock"
echo "PHP 8.4: /run/php/php8.4-fpm.sock"
echo ""
echo "Próximos passos:"
echo "----------------"
if [ "$INSTALL_MARIADB" = true ]; then
    echo "1. Configurar MariaDB: mysql_secure_installation"
    echo "2. Copiar configurações do Nginx para /etc/nginx/sites-available/"
    echo "3. Criar links simbólicos em /etc/nginx/sites-enabled/"
    echo "4. Testar: nginx -t"
    echo "5. Recarregar: systemctl reload nginx"
else
    echo "1. Copiar configurações do Nginx para /etc/nginx/sites-available/"
    echo "2. Criar links simbólicos em /etc/nginx/sites-enabled/"
    echo "3. Configurar container MySQL 5.7 com Docker (se necessário)"
    echo "4. Testar: nginx -t"
    echo "5. Recarregar: systemctl reload nginx"
fi
echo ""
