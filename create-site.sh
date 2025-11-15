#!/bin/bash
set -e

# Script para criar novo site no Nginx
# Uso: ./create-site.sh <url> <versao-php> [--laravel]
# Exemplo: ./create-site.sh meusite.com 56
# Exemplo Laravel: ./create-site.sh meusite.com 84 --laravel

# Função para validar domínio (prevenir injeção de comandos)
validate_domain() {
    local domain="$1"
    
    # Permitir: letras, números, pontos, hífens
    # Formato básico de domínio: exemplo.com, sub.exemplo.com
    if [[ ! "$domain" =~ ^[a-zA-Z0-9][a-zA-Z0-9.-]+[a-zA-Z0-9]$ ]]; then
        echo "Erro: Domínio inválido: '$domain'"
        echo "Use apenas letras, números, pontos e hífens"
        echo "Exemplo: exemplo.com ou sub.exemplo.com"
        return 1
    fi
    return 0
}

# Verificar se está rodando como root
if [ "$EUID" -ne 0 ]; then 
    echo "Este script precisa ser executado como root (su ou sudo)"
    exit 1
fi

# Verificar argumentos
if [ "$#" -lt 2 ]; then
    echo "Uso: $0 <url> <versao-php> [--laravel]"
    echo "Exemplo: $0 meusite.com 56"
    echo "Exemplo Laravel: $0 meusite.com 84 --laravel"
    echo ""
    echo "Versões PHP disponíveis: 56, 74, 84"
    exit 1
fi

URL=$1
PHP_VERSION=$2
IS_LARAVEL=false

# Validar domínio
validate_domain "$URL" || exit 1

# Verificar flag --laravel
if [ "$#" -eq 3 ] && [ "$3" == "--laravel" ]; then
    IS_LARAVEL=true
fi

# Validar versão do PHP
case $PHP_VERSION in
    56)
        PHP_SOCKET="/run/php/php5.6-fpm.sock"
        ;;
    74)
        PHP_SOCKET="/run/php/php7.4-fpm.sock"
        ;;
    84)
        PHP_SOCKET="/run/php/php8.4-fpm.sock"
        ;;
    *)
        echo "Erro: Versão PHP inválida: $PHP_VERSION"
        echo "Versões disponíveis: 56, 74, 84"
        exit 1
        ;;
esac

# Verificar se o socket PHP existe
if [ ! -S "$PHP_SOCKET" ]; then
    echo "Erro: Socket PHP não encontrado: $PHP_SOCKET"
    echo "Certifique-se de que o PHP-FPM está instalado e rodando."
    exit 1
fi

SITE_CONF="/etc/nginx/sites-available/${URL}.conf"
SITE_ENABLED="/etc/nginx/sites-enabled/${URL}.conf"
SITE_DIR="/sistemas/apps/${URL}"
LOG_DIR="/sistemas/logs/${URL}"

# Definir root do site (Laravel usa /public)
if [ "$IS_LARAVEL" = true ]; then
    SITE_ROOT="${SITE_DIR}/public"
else
    SITE_ROOT="${SITE_DIR}"
fi

echo "======================================"
echo "  Criando novo site"
echo "======================================"
echo "URL: $URL"
echo "PHP: $PHP_VERSION (socket: $PHP_SOCKET)"
echo "Tipo: $([ "$IS_LARAVEL" = true ] && echo "Laravel" || echo "Padrão")"
echo "Diretório: $SITE_DIR"
echo "Root: $SITE_ROOT"
echo "Logs: $LOG_DIR"
echo ""

# Verificar se site já existe
if [ -f "$SITE_CONF" ]; then
    echo "Erro: Site já existe em $SITE_CONF"
    exit 1
fi

if [ -d "$SITE_DIR" ]; then
    echo "Erro: Diretório já existe em $SITE_DIR"
    exit 1
fi

# Criar diretórios
echo "[1/5] Criando diretórios..."
if [ "$IS_LARAVEL" = true ]; then
    mkdir -p "$SITE_DIR/public"
else
    mkdir -p "$SITE_DIR"
fi
mkdir -p "$LOG_DIR"

# Ajustar dono dos diretórios
chown -R www-data:www-data "$SITE_DIR"
chown -R www-data:www-data "$LOG_DIR"

# Ajustar permissões com grupo write
chmod -R 775 "$SITE_DIR"
chmod -R 775 "$LOG_DIR"

# Criar arquivo index.php de teste
if [ "$IS_LARAVEL" = true ]; then
    cat > "$SITE_DIR/public/index.php" << 'EOF'
<?php
phpinfo();
EOF
else
    cat > "$SITE_DIR/index.php" << 'EOF'
<?php
phpinfo();
EOF
fi

# Ajustar permissões
chown -R www-data:www-data "$SITE_DIR"
chown -R www-data:www-data "$LOG_DIR"
chmod -R 775 "$SITE_DIR"
chmod -R 775 "$LOG_DIR"

echo "✓ Diretórios criados"

# Criar configuração do Nginx
echo "[2/5] Criando configuração do Nginx..."
cat > "$SITE_CONF" << EOF
server {
    listen 80;
    listen [::]:80;
    
    server_name $URL;
    
    root $SITE_ROOT;
    index index.php index.html index.htm;
    
    access_log $LOG_DIR/access.log;
    error_log $LOG_DIR/error.log;
    
    # Configurações gerais
    client_max_body_size 100M;
    
    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }
    
    # Processar PHP via FastCGI
    location ~ \.php$ {
        try_files \$uri =404;
        fastcgi_split_path_info ^(.+\.php)(/.+)$;
        
        fastcgi_pass unix:$PHP_SOCKET;
        fastcgi_index index.php;
        
        include fastcgi_params;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        fastcgi_param PATH_INFO \$fastcgi_path_info;
        
        fastcgi_buffer_size 128k;
        fastcgi_buffers 256 16k;
        fastcgi_busy_buffers_size 256k;
        fastcgi_temp_file_write_size 256k;
        fastcgi_read_timeout 300;
    }
    
    # Negar acesso a arquivos ocultos
    location ~ /\.(?!well-known).* {
        deny all;
    }
    
    # Cache de arquivos estáticos
    location ~* \.(jpg|jpeg|png|gif|ico|css|js|svg|woff|woff2|ttf|eot)$ {
        expires 7d;
        add_header Cache-Control "public, immutable";
    }
}
EOF

echo "✓ Configuração criada: $SITE_CONF"

# Criar link simbólico
echo "[3/5] Ativando site..."
ln -s "$SITE_CONF" "$SITE_ENABLED"
echo "✓ Site ativado"

# Testar configuração do Nginx
echo "[4/5] Testando configuração do Nginx..."
if nginx -t 2>&1 | grep -q "successful"; then
    echo "✓ Configuração válida"
else
    echo "✗ Erro na configuração do Nginx!"
    echo ""
    nginx -t
    echo ""
    echo "Revertendo alterações..."
    rm -f "$SITE_ENABLED"
    rm -f "$SITE_CONF"
    echo "Site não foi criado."
    exit 1
fi

# Recarregar Nginx
echo "[5/5] Recarregando Nginx..."
systemctl reload nginx
echo "✓ Nginx recarregado"

echo ""
echo "======================================"
echo "  Site criado com sucesso!"
echo "======================================"
echo ""
echo "Informações do site:"
echo "--------------------"
echo "URL: http://$URL"
echo "Diretório: $SITE_DIR"
echo "Logs: $LOG_DIR"
echo "Config: $SITE_CONF"
echo "PHP: $PHP_VERSION"
echo ""
echo "Próximos passos:"
echo "----------------"
echo "1. Adicionar '$URL' ao DNS ou /etc/hosts"
echo "2. Acessar: http://$URL (deve mostrar phpinfo)"
echo "3. Fazer upload da aplicação para: $SITE_DIR"
echo "4. Configurar SSL com: certbot --nginx -d $URL"
echo ""
