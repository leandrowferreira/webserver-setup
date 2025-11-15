#!/bin/bash
set -e

# Script para remover site do Nginx
# Uso: ./remove-site.sh <url>
# Exemplo: ./remove-site.sh teste.com.br

# Verificar se está rodando como root
if [ "$EUID" -ne 0 ]; then 
    echo "Este script precisa ser executado como root (su ou sudo)"
    exit 1
fi

# Verificar argumentos
if [ "$#" -ne 1 ]; then
    echo "Uso: $0 <url>"
    echo "Exemplo: $0 teste.com.br"
    exit 1
fi

URL=$1

SITE_CONF="/etc/nginx/sites-available/${URL}.conf"
SITE_ENABLED="/etc/nginx/sites-enabled/${URL}.conf"
SITE_DIR="/sistemas/apps/${URL}"
LOG_DIR="/sistemas/logs/${URL}"
TIMESTAMP=$(date +%Y%m%d%H%M%S)
BACKUP_DIR="/sistemas/apps/${URL}.${TIMESTAMP}.old"

echo "======================================"
echo "  Removendo site"
echo "======================================"
echo "URL: $URL"
echo "Config: $SITE_CONF"
echo "Diretório: $SITE_DIR"
echo "Backup: $BACKUP_DIR"
echo ""

# Verificar se site existe
if [ ! -f "$SITE_CONF" ]; then
    echo "Erro: Site não encontrado em $SITE_CONF"
    exit 1
fi

# Confirmação
read -p "Tem certeza que deseja remover o site $URL? (s/N): " -n 1 -r
echo ""
if [[ ! $REPLY =~ ^[Ss]$ ]]; then
    echo "Operação cancelada."
    exit 0
fi

# Desativar site (remover link simbólico)
echo "[1/5] Desativando site..."
if [ -L "$SITE_ENABLED" ]; then
    rm -f "$SITE_ENABLED"
    echo "✓ Site desativado"
else
    echo "⚠ Link simbólico não encontrado (já estava desativado)"
fi

# Remover configuração do Nginx
echo "[2/5] Removendo configuração do Nginx..."
if [ -f "$SITE_CONF" ]; then
    rm -f "$SITE_CONF"
    echo "✓ Configuração removida"
else
    echo "⚠ Arquivo de configuração não encontrado"
fi

# Testar configuração do Nginx
echo "[3/5] Testando configuração do Nginx..."
if nginx -t 2>&1 | grep -q "successful"; then
    echo "✓ Configuração válida"
else
    echo "✗ Erro na configuração do Nginx!"
    nginx -t
    exit 1
fi

# Recarregar Nginx
echo "[4/5] Recarregando Nginx..."
systemctl reload nginx
echo "✓ Nginx recarregado"

# Fazer backup do diretório (renomear)
echo "[5/5] Fazendo backup do diretório..."
if [ -d "$SITE_DIR" ]; then
    mv "$SITE_DIR" "$BACKUP_DIR"
    echo "✓ Diretório movido para: $BACKUP_DIR"
else
    echo "⚠ Diretório não encontrado: $SITE_DIR"
fi

echo ""
echo "======================================"
echo "  Site removido com sucesso!"
echo "======================================"
echo ""
echo "Resumo:"
echo "-------"
echo "✓ Configuração Nginx removida"
echo "✓ Site desativado"
echo "✓ Nginx recarregado"
if [ -d "$BACKUP_DIR" ]; then
    echo "✓ Backup criado: $BACKUP_DIR"
fi
echo ""
echo "Observações:"
echo "------------"
echo "- Os logs permanecem em: $LOG_DIR"
echo "- Para restaurar, renomeie: $BACKUP_DIR -> $SITE_DIR"
echo "  e recrie a configuração do Nginx"
echo ""
