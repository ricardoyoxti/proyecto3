#!/bin/bash
set -e

# Colores para logs
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log()     { echo -e "${GREEN}[$(date +'%F %T')] $1${NC}"; }
error()   { echo -e "${RED}[$(date +'%F %T')] ERROR: $1${NC}"; }
info()    { echo -e "${BLUE}[$(date +'%F %T')] INFO: $1${NC}"; }

# ➕ Obtener metadatos desde GCP
INSTANCE_NAME=$(curl -s "http://metadata.google.internal/computeMetadata/v1/instance/attributes/instance-name" -H "Metadata-Flavor: Google" || echo "odoo-instance")
DEPLOYMENT_TIME=$(curl -s "http://metadata.google.internal/computeMetadata/v1/instance/attributes/deployment-time" -H "Metadata-Flavor: Google" || date -u +"%Y-%m-%dT%H:%M:%SZ")
GITHUB_ACTOR=$(curl -s "http://metadata.google.internal/computeMetadata/v1/instance/attributes/github-actor" -H "Metadata-Flavor: Google" || echo "unknown")

# Variables
ODOO_VERSION="18.0"
ODOO_USER="odoo"
ODOO_HOME="/opt/odoo"
ODOO_CONFIG="/etc/odoo/odoo.conf"
ODOO_PORT="8069"
POSTGRES_USER="odoo"
POSTGRES_DB="odoo"
POSTGRES_PASSWORD="odoo123"

log "🚀 Iniciando instalación de Odoo 18 Community"
info "📋 Instancia: $INSTANCE_NAME"
info "📅 Despliegue: $DEPLOYMENT_TIME"
info "👤 GitHub actor: $GITHUB_ACTOR"

# Actualización del sistema
log "📦 Actualizando sistema..."
apt-get update -y && apt-get upgrade -y

# Instalar dependencias
log "🔧 Instalando dependencias del sistema..."
apt-get install -y wget git curl unzip python3 python3-venv python3-pip python3-dev \
    libxml2-dev libxslt1-dev libevent-dev libsasl2-dev libldap2-dev libpq-dev \
    libjpeg-dev libpng-dev libfreetype6-dev liblcms2-dev libwebp-dev libharfbuzz-dev \
    libfribidi-dev libxcb1-dev libfontconfig1 xfonts-base xfonts-75dpi gcc g++ make

# Instalar PostgreSQL
log "🐘 Instalando PostgreSQL..."
apt-get install -y postgresql postgresql-contrib postgresql-server-dev-all
systemctl enable postgresql
systemctl start postgresql

# Crear usuario y base de datos en PostgreSQL
sudo -u postgres psql -tc "SELECT 1 FROM pg_roles WHERE rolname = '$POSTGRES_USER'" | grep -q 1 || \
    sudo -u postgres psql -c "CREATE USER $POSTGRES_USER WITH CREATEDB PASSWORD '$POSTGRES_PASSWORD';"
sudo -u postgres psql -tc "SELECT 1 FROM pg_database WHERE datname = '$POSTGRES_DB'" | grep -q 1 || \
    sudo -u postgres createdb -O $POSTGRES_USER $POSTGRES_DB

# Crear usuario del sistema Odoo
log "👤 Creando usuario del sistema Odoo..."
adduser --system --quiet --home=$ODOO_HOME --group $ODOO_USER

# Instalar wkhtmltopdf
log "📄 Instalando wkhtmltopdf..."
cd /tmp
if [[ $(lsb_release -rs) == "22.04" ]]; then
    wget https://github.com/wkhtmltopdf/packaging/releases/download/0.12.6.1-2/wkhtmltox_0.12.6.1-2.jammy_amd64.deb
    dpkg -i wkhtmltox_0.12.6.1-2.jammy_amd64.deb || apt-get install -f -y
else
    wget https://github.com/wkhtmltopdf/packaging/releases/download/0.12.6.1-2/wkhtmltox_0.12.6.1-2.focal_amd64.deb
    dpkg -i wkhtmltox_0.12.6.1-2.focal_amd64.deb || apt-get install -f -y
fi

# Clonar Odoo
log "📥 Clonando Odoo $ODOO_VERSION..."
git clone https://github.com/odoo/odoo --depth 1 --branch $ODOO_VERSION $ODOO_HOME
chown -R $ODOO_USER:$ODOO_USER $ODOO_HOME

# Crear entorno virtual
log "🐍 Creando entorno virtual Python..."
python3 -m venv $ODOO_HOME/venv
chown -R $ODOO_USER:$ODOO_USER $ODOO_HOME/venv

# Instalar dependencias de Python
log "📦 Instalando dependencias Python..."
sudo -u $ODOO_USER $ODOO_HOME/venv/bin/pip install --upgrade pip
sudo -u $ODOO_USER $ODOO_HOME/venv/bin/pip install -r $ODOO_HOME/requirements.txt || \
sudo -u $ODOO_USER $ODOO_HOME/venv/bin/pip install -r $ODOO_HOME/odoo/requirements.txt
sudo -u $ODOO_USER $ODOO_HOME/venv/bin/pip install psycopg2-binary

# Crear configuración y logs
log "⚙️ Configurando Odoo..."
mkdir -p /etc/odoo /var/log/odoo /var/lib/odoo
chown -R $ODOO_USER:$ODOO_USER /var/log/odoo /var/lib/odoo

cat > $ODOO_CONFIG << EOF
[options]
admin_passwd = admin
db_host = localhost
db_port = 5432
db_user = $POSTGRES_USER
db_password = $POSTGRES_PASSWORD
addons_path = $ODOO_HOME/addons
logfile = /var/log/odoo/odoo.log
log_level = info
xmlrpc_port = $ODOO_PORT
EOF

chown $ODOO_USER:$ODOO_USER $ODOO_CONFIG

# Crear servicio systemd
log "🔧 Creando servicio systemd para Odoo..."
cat > /etc/systemd/system/odoo.service << EOF
[Unit]
Description=Odoo 18 Community
After=network.target postgresql.service
Requires=postgresql.service

[Service]
Type=simple
User=$ODOO_USER
Group=$ODOO_USER
ExecStart=$ODOO_HOME/venv/bin/python3 $ODOO_HOME/odoo-bin -c $ODOO_CONFIG
StandardOutput=journal+console
Restart=always

[Install]
WantedBy=multi-user.target
EOF

# Habilitar e iniciar Odoo
log "🚀 Iniciando servicio Odoo..."
systemctl daemon-reexec
systemctl daemon-reload
systemctl enable odoo
systemctl start odoo

# Inicializar base de datos
log "🗄️ Verificando o creando base de datos..."
sleep 10
sudo -u $ODOO_USER $ODOO_HOME/venv/bin/python3 $ODOO_HOME/odoo-bin -c $ODOO_CONFIG -d $POSTGRES_DB --init=base --stop-after-init || \
log "⚠️ La base de datos ya existe o no fue necesaria la inicialización."

# Mostrar IP pública
EXTERNAL_IP=$(curl -s http://metadata.google.internal/computeMetadata/v1/instance/network-interfaces/0/access-configs/0/external-ip -H "Metadata-Flavor: Google")
log "🎉 Odoo está disponible en: http://$EXTERNAL_IP:$ODOO_PORT"

info "📊 Información de instalación:"
info "   - Instancia: $INSTANCE_NAME"
info "   - Fecha: $DEPLOYMENT_TIME"
info "   - GitHub Actor: $GITHUB_ACTOR"
info "   - Usuario Odoo: admin"
info "   - Contraseña: admin"
