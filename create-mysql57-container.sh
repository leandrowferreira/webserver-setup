#!/bin/bash
set -e

# Script para criar container MySQL 5.7 isolado para uma aplicação específica
# Uso: ./create-mysql57-container.sh

# Função para validar nomes (prevenir injeção de comandos)
validate_name() {
    local name="$1"
    local field="$2"
    
    if [[ ! "$name" =~ ^[a-zA-Z0-9_-]+$ ]]; then
        echo "Erro: $field deve conter apenas letras, números, hífen (-) e underscore (_)"
        echo "Valor inválido: '$name'"
        return 1
    fi
    return 0
}

# Verificar se está rodando como root
if [ "$EUID" -ne 0 ]; then 
    echo "Este script precisa ser executado como root (sudo)"
    exit 1
fi

# Verificar se Docker está instalado
if ! command -v docker &> /dev/null; then
    echo "Erro: Docker não está instalado."
    echo "Execute o script setup-ec2-debian13.sh primeiro."
    exit 1
fi

echo "======================================"
echo "  MySQL 5.7 Container Setup"
echo "======================================"
echo ""
echo "Este script criará um container MySQL 5.7 isolado"
echo "para uma aplicação específica."
echo ""

# Coletar informações
read -p "Nome do container (ex: mysql-app1): " CONTAINER_NAME
if [ -z "$CONTAINER_NAME" ]; then
    echo "Erro: Nome do container é obrigatório"
    exit 1
fi

# Validar nome do container
validate_name "$CONTAINER_NAME" "Nome do container" || exit 1

# Verificar se container já existe
if docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
    echo "Erro: Container '$CONTAINER_NAME' já existe"
    exit 1
fi

read -p "Porta do host (ex: 3307): " HOST_PORT
if [ -z "$HOST_PORT" ]; then
    echo "Erro: Porta do host é obrigatória"
    exit 1
fi

# Verificar se a porta está em uso
if netstat -tuln 2>/dev/null | grep -q ":${HOST_PORT} " || ss -tuln 2>/dev/null | grep -q ":${HOST_PORT} "; then
    echo "Erro: Porta $HOST_PORT já está em uso"
    exit 1
fi

read -p "Nome do banco de dados a criar: " DATABASE_NAME
if [ -z "$DATABASE_NAME" ]; then
    echo "Erro: Nome do banco é obrigatório"
    exit 1
fi

# Validar nome do banco
validate_name "$DATABASE_NAME" "Nome do banco" || exit 1

read -p "Usuário MySQL: " MYSQL_USER
if [ -z "$MYSQL_USER" ]; then
    echo "Erro: Usuário é obrigatório"
    exit 1
fi

# Validar nome do usuário
validate_name "$MYSQL_USER" "Usuário MySQL" || exit 1

read -sp "Senha do usuário: " MYSQL_PASSWORD
echo ""
if [ -z "$MYSQL_PASSWORD" ]; then
    echo "Erro: Senha é obrigatória"
    exit 1
fi

read -sp "Senha do root MySQL: " MYSQL_ROOT_PASSWORD
echo ""
if [ -z "$MYSQL_ROOT_PASSWORD" ]; then
    echo "Erro: Senha do root é obrigatória"
    exit 1
fi

# Diretório para dados persistentes
DATA_DIR="/var/lib/mysql-containers/${CONTAINER_NAME}"

echo ""
echo "======================================"
echo "  Resumo da configuração"
echo "======================================"
echo "Container: $CONTAINER_NAME"
echo "Porta: localhost:$HOST_PORT"
echo "Banco: $DATABASE_NAME"
echo "Usuário: $MYSQL_USER"
echo "Diretório de dados: $DATA_DIR"
echo ""
read -p "Confirma a criação? (s/N): " CONFIRM

if [ "$CONFIRM" != "s" ] && [ "$CONFIRM" != "S" ]; then
    echo "Operação cancelada."
    exit 0
fi

# Criar diretório para dados
echo ""
echo "[1/4] Criando diretório para dados..."
mkdir -p "$DATA_DIR"
chmod 755 "$DATA_DIR"
echo "✓ Diretório criado: $DATA_DIR"

# Criar container MySQL 5.7
echo ""
echo "[2/4] Criando container MySQL 5.7 (limites: 256MB RAM, 0.5 CPU)..."
docker run -d \
    --name "$CONTAINER_NAME" \
    --restart=always \
    --memory=256m \
    --memory-swap=256m \
    --cpus=0.5 \
    -p "${HOST_PORT}:3306" \
    -e MYSQL_ROOT_PASSWORD="$MYSQL_ROOT_PASSWORD" \
    -e MYSQL_DATABASE="$DATABASE_NAME" \
    -e MYSQL_USER="$MYSQL_USER" \
    -e MYSQL_PASSWORD="$MYSQL_PASSWORD" \
    -v "${DATA_DIR}:/var/lib/mysql" \
    mysql:5.7 \
    --character-set-server=utf8mb4 \
    --collation-server=utf8mb4_unicode_ci \
    --sql-mode="STRICT_TRANS_TABLES,NO_ZERO_IN_DATE,NO_ZERO_DATE,ERROR_FOR_DIVISION_BY_ZERO,NO_ENGINE_SUBSTITUTION"

echo "✓ Container criado e iniciado com limites de recursos"

# Aguardar MySQL inicializar
echo ""
echo "[3/4] Aguardando MySQL inicializar..."
MAX_TRIES=30
TRIES=0

while [ $TRIES -lt $MAX_TRIES ]; do
    if docker exec "$CONTAINER_NAME" mysqladmin ping -h localhost -u root -p"$MYSQL_ROOT_PASSWORD" --silent 2>/dev/null; then
        echo "✓ MySQL está pronto"
        break
    fi
    TRIES=$((TRIES + 1))
    echo -n "."
    sleep 2
done

if [ $TRIES -eq $MAX_TRIES ]; then
    echo ""
    echo "✗ Timeout aguardando MySQL inicializar"
    echo "Verifique os logs: docker logs $CONTAINER_NAME"
    exit 1
fi

echo ""

# Conceder privilégios adicionais ao usuário
echo "[4/4] Configurando privilégios do usuário..."
docker exec "$CONTAINER_NAME" mysql -u root -p"$MYSQL_ROOT_PASSWORD" -e "
    GRANT ALL PRIVILEGES ON \`${DATABASE_NAME}\`.* TO '${MYSQL_USER}'@'%';
    FLUSH PRIVILEGES;
" 2>/dev/null

echo "✓ Privilégios configurados"

# Criar arquivo de informações
INFO_FILE="/root/mysql-${CONTAINER_NAME}-info.txt"
cat > "$INFO_FILE" << EOF
MySQL 5.7 Container - ${CONTAINER_NAME}
========================================
Criado em: $(date '+%Y-%m-%d %H:%M:%S')

Informações de Conexão:
-----------------------
Host: localhost (ou 127.0.0.1)
Porta: ${HOST_PORT}
Banco: ${DATABASE_NAME}
Usuário: ${MYSQL_USER}
Senha: ${MYSQL_PASSWORD}
Root Password: ${MYSQL_ROOT_PASSWORD}

Recursos:
---------
Memória: 256MB (limite rígido)
CPU: 0.5 (50% de 1 core)

Comandos Úteis:
---------------
# Ver logs
docker logs ${CONTAINER_NAME}

# Ver uso de recursos em tempo real
docker stats ${CONTAINER_NAME}

# Acessar MySQL CLI
docker exec -it ${CONTAINER_NAME} mysql -u ${MYSQL_USER} -p${MYSQL_PASSWORD} ${DATABASE_NAME}

# Acessar como root
docker exec -it ${CONTAINER_NAME} mysql -u root -p${MYSQL_ROOT_PASSWORD}

# Parar container
docker stop ${CONTAINER_NAME}

# Iniciar container
docker start ${CONTAINER_NAME}

# Remover container (CUIDADO: dados serão perdidos se não tiver backup)
docker stop ${CONTAINER_NAME}
docker rm ${CONTAINER_NAME}

# Backup do banco
docker exec ${CONTAINER_NAME} mysqldump -u root -p${MYSQL_ROOT_PASSWORD} ${DATABASE_NAME} > backup-${DATABASE_NAME}-\$(date +%Y%m%d).sql

# Restaurar backup
docker exec -i ${CONTAINER_NAME} mysql -u root -p${MYSQL_ROOT_PASSWORD} ${DATABASE_NAME} < backup-${DATABASE_NAME}.sql

String de Conexão (PHP/Laravel):
---------------------------------
DB_CONNECTION=mysql
DB_HOST=127.0.0.1
DB_PORT=${HOST_PORT}
DB_DATABASE=${DATABASE_NAME}
DB_USERNAME=${MYSQL_USER}
DB_PASSWORD=${MYSQL_PASSWORD}

Diretório de dados:
-------------------
${DATA_DIR}
EOF

chmod 600 "$INFO_FILE"

echo ""
echo "======================================"
echo "  MySQL 5.7 Container criado!"
echo "======================================"
echo ""
echo "Informações de Conexão:"
echo "-----------------------"
echo "Host: localhost"
echo "Porta: $HOST_PORT"
echo "Banco: $DATABASE_NAME"
echo "Usuário: $MYSQL_USER"
echo ""
echo "Container configurado para:"
echo "- Iniciar automaticamente com o sistema (--restart=always)"
echo "- Dados persistentes em: $DATA_DIR"
echo "- Charset: utf8mb4"
echo "- Limite de memória: 256MB"
echo "- Limite de CPU: 0.5 (50%)"
echo ""
echo "Arquivo de informações salvo em: $INFO_FILE"
echo ""
echo "Testar conexão:"
echo "---------------"
echo "docker exec -it $CONTAINER_NAME mysql -u $MYSQL_USER -p$MYSQL_PASSWORD $DATABASE_NAME"
echo ""
echo "Ver uso de recursos:"
echo "--------------------"
echo "docker stats $CONTAINER_NAME --no-stream"
echo ""
echo "Ver status:"
echo "-----------"
echo "docker ps | grep $CONTAINER_NAME"
echo ""
