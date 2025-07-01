#!/bin/bash

# Script de instalación automática de Odoo 18 Community en Ubuntu 22.04
# Este script se ejecuta automáticamente cuando se crea la instancia en GCP

set -e  # Salir si cualquier comando falla

# Colores para logs
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Función para logging
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}" | tee -a /var/log/odoo-install.log
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}" | tee -a /var/log/odoo-install.log
}

warning() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING: $1${NC}" | tee -a /var/log/odoo-install.log
}

info() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO: $1${NC}" | tee -a /var/log/odoo-install.log
}

# Configuración
ODOO_USER="odoo"
ODOO_HOME="/opt/odoo"
ODOO_CONFIG="/etc/odoo/odoo.conf"
POSTGRES_USER="odoo"
POSTGRES_PASSWORD="odoo_password_$(openssl rand -hex 8)"

log "🚀 Iniciando instalación de Odoo 18 Community"
log "📝 Log completo disponible en: /var/log/odoo-install.log"

# Actualizar sistema
log "📦 Actualizando paquetes del sistema..."
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get upgrade -y

# Instalar dependencias del sistema
log "🔧 Instalando dependencias del sistema..."
apt-get install -y \
    wget \
    ca-certificates \
    curl \
    gnupg \
    lsb-release \
    git \
    python3 \
    python3-pip \
    python3-dev \
    python3-venv \
    build-essential \
    libxml2-dev \
    libxslt1-dev \
    libevent-dev \
    libsasl2-dev \
    libldap2-dev \
    libpq-dev \
    libpng-dev \
    libjpeg-dev \
    zlib1g-dev \
    libfreetype6-dev \
    liblcms2-dev \
    libwebp-dev \
    libharfbuzz-dev \
    libfribidi-dev \
    libxcb1-dev \
    libssl-dev \
    libffi-dev \
    fontconfig \
    xfonts-75dpi \
    xfonts-base \
    supervisor \
    nginx

# Instalar wkhtmltopdf
log "📄 Instalando wkhtmltopdf..."
cd /tmp
wget -q https://github.com/wkhtmltopdf/packaging/releases/download/0.12.6.1-2/wkhtmltox_0.12.6.1-2.jammy_amd64.deb
dpkg -i wkhtmltox_0.12.6.1-2.jammy_amd64.deb || apt-get install -f -y
rm wkhtmltox_0.12.6.1-2.jammy_amd64.deb

# Instalar PostgreSQL
log "🐘 Instalando PostgreSQL..."
apt-get install -y postgresql postgresql-contrib

# Configurar PostgreSQL
log "⚙️ Configurando PostgreSQL..."
systemctl start postgresql
systemctl enable postgresql

# Crear usuario de base de datos para Odoo
sudo -u postgres createuser -s $POSTGRES_USER 2>/dev/null || warning "Usuario PostgreSQL ya existe"
sudo -u postgres psql -c "ALTER USER $POSTGRES_USER PASSWORD '$POSTGRES_PASSWORD';" 2>/dev/null || warning "Error configurando contraseña de PostgreSQL"

# Crear usuario del sistema para Odoo
log "👤 Creando usuario del sistema para Odoo..."
useradd -m -d $ODOO_HOME -U -r -s /bin/bash $ODOO_USER 2>/dev/null || warning "Usuario Odoo ya existe"

# Descargar Odoo 18
log "⬇️ Descargando Odoo 18 Community..."
if [ ! -d "$ODOO_HOME/odoo" ]; then
    sudo -u $ODOO_USER git clone https://www.github.com/odoo/odoo --depth 1 --branch 18.0 --single-branch $ODOO_HOME/odoo
else
    warning "Directorio Odoo ya existe"
fi

# Crear entorno virtual de Python
log "🐍 Configurando entorno virtual de Python..."
sudo -u $ODOO_USER python3 -m venv $ODOO_HOME/venv
source $ODOO_HOME/venv/bin/activate

# Actualizar pip y instalar wheel
pip install --upgrade pip
pip install wheel

# Instalar dependencias de Python para Odoo
log "📚 Instalando dependencias de Python..."
pip install -r $ODOO_HOME/odoo/requirements.txt

# Crear directorios necesarios
log "📁 Creando directorios de configuración..."
mkdir -p /etc/odoo
mkdir -p /var/log/odoo
mkdir -p $ODOO_HOME/addons
mkdir -p $ODOO_HOME/data

# Configurar permisos
chown -R $ODOO_USER:$ODOO_USER $ODOO_HOME
chown -R $ODOO_USER:$ODOO_USER /var/log/odoo

# Crear archivo de configuración de Odoo
log "📝 Creando archivo de configuración de Odoo..."
cat > $ODOO_CONFIG << EOF
[options]
; This is the password that allows database operations:
admin_passwd = admin
db_host = localhost
db_port = 5432
db_user = $POSTGRES_USER
db_password = $POSTGRES_PASSWORD
xmlrpc_port = 8069
logfile = /var/log/odoo/odoo.log
addons_path = $ODOO_HOME/odoo/addons,$ODOO_HOME/addons
data_dir = $ODOO_HOME/data
default_productivity_apps = True

; Security
list_db = False
proxy_mode = True

; Performance
max_cron_threads = 1
workers = 0

; Logging
log_level = info
log_handler = :INFO
EOF

chown $ODOO_USER:$ODOO_USER $ODOO_CONFIG

# Crear servicio systemd para Odoo
log "🔧 Configurando servicio systemd..."
cat > /etc/systemd/system/odoo.service << EOF
[Unit]
Description=Odoo 18 Community
Documentation=http://www.odoo.com
Requires=postgresql.service
After=postgresql.service

[Service]
Type=notify
SyslogIdentifier=odoo
PermissionsStartOnly=true
User=$ODOO_USER
Group=$ODOO_USER
ExecStart=$ODOO_HOME/venv/bin/python3 $ODOO_HOME/odoo/odoo-bin -c $ODOO_CONFIG
StandardOutput=journal+console
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

# Configurar Nginx como proxy reverso (opcional)
log "🌐 Configurando Nginx..."
cat > /etc/nginx/sites-available/odoo << EOF
upstream odoo {
    server 127.0.0.1:8069;
}

upstream odoochat {
    server 127.0.0.1:8072;
}

server {
    listen 80;
    server_name _;
    
    # Redirigir directamente a Odoo
    location / {
        return 301 http://\$host:8069\$request_uri;
    }
}
EOF

# Habilitar configuración de Nginx
ln -sf /etc/nginx/sites-available/odoo /etc/nginx/sites-enabled/
rm -f /etc/nginx/sites-enabled/default

# Crear base de datos inicial
log "🗃️ Creando base de datos inicial de Odoo..."
sudo -u postgres createdb -O $POSTGRES_USER odoo 2>/dev/null || warning "Base de datos 'odoo' ya existe"

# Inicializar Odoo
log "🎯 Inicializando Odoo..."
sudo -u $ODOO_USER $ODOO_HOME/venv/bin/python3 $ODOO_HOME/odoo/odoo-bin \
    -c $ODOO_CONFIG \
    -d odoo \
    --init=base \
    --stop-after-init

# Habilitar y iniciar servicios
log "🚀 Iniciando servicios..."
systemctl daemon-reload
systemctl enable odoo
systemctl start odoo
systemctl enable nginx
systemctl restart nginx

# Configurar firewall básico
log "🔒 Configurando firewall..."
ufw --force enable
ufw allow 22/tcp    # SSH
ufw allow 8069/tcp  # Odoo
ufw allow 80/tcp    # HTTP
ufw allow 443/tcp   # HTTPS (futuro)

# Crear script de información del sistema
log "📋 Creando script de información del sistema..."
cat > /usr/local/bin/odoo-info << 'EOF'
#!/bin/bash
echo "========================================="
echo "  INFORMACIÓN DE ODOO 18 COMMUNITY"
echo "========================================="
echo ""
echo "🌐 URLs de acceso:"
echo "   - Odoo: http://$(curl -s http://checkip.amazonaws.com):8069"
echo "   - IP Local: http://$(hostname -I | awk '{print $1}'):8069"
echo ""
echo "📝 Credenciales iniciales:"
echo "   - Base de datos: odoo"
echo "   - Usuario: admin"
echo "   - Contraseña: admin"
echo ""
echo "🔧 Archivos importantes:"
echo "   - Configuración: /etc/odoo/odoo.conf"
echo "   - Logs: /var/log/odoo/odoo.log"
echo "   - Directorio principal: /opt/odoo"
echo ""
echo "📊 Estado de servicios:"
echo "   - Odoo: $(systemctl is-active odoo)"
echo "   - PostgreSQL: $(systemctl is-active postgresql)"
echo "   - Nginx: $(systemctl is-active nginx)"
echo ""
echo "🔍 Comandos útiles:"
echo "   - Ver logs: sudo tail -f /var/log/odoo/odoo.log"
echo "   - Reiniciar Odoo: sudo systemctl restart odoo"
echo "   - Estado de Odoo: sudo systemctl status odoo"
echo ""
echo "========================================="
EOF

chmod +x /usr/local/bin/odoo-info

# Crear cron job para mostrar información al inicio
echo '@reboot root /usr/local/bin/odoo-info > /etc/motd 2>/dev/null' >> /etc/crontab

# Esperar a que Odoo esté completamente iniciado
log "⏳ Esperando que Odoo esté completamente iniciado..."
sleep 30

# Verificar que Odoo esté corriendo
for i in {1..30}; do
    if systemctl is-active --quiet odoo && curl -s http://localhost:8069 > /dev/null 2>&1; then
        log "✅ Odoo está corriendo correctamente"
        break
    elif [ $i -eq 30 ]; then
        error "❌ Odoo no pudo iniciar correctamente"
        systemctl status odoo
        tail -20 /var/log/odoo/odoo.log
    else
        info "Esperando que Odoo inicie... ($i/30)"
        sleep 10
    fi
done

# Mostrar información final
log "🎉 ¡Instalación de Odoo 18 Community completada!"
log "📊 Generando información del sistema..."

# Obtener IP externa
EXTERNAL_IP=$(curl -s http://checkip.amazonaws.com 2>/dev/null || echo "No disponible")
INTERNAL_IP=$(hostname -I | awk '{print $1}')

# Crear mensaje de finalización
cat > /tmp/installation-complete << EOF
========================================
  🎉 ODOO 18 INSTALACIÓN COMPLETADA
========================================

🌐 ACCESO A ODOO:
   URL Externa: http://${EXTERNAL_IP}:8069
   URL Interna: http://${INTERNAL_IP}:8069

📝 CREDENCIALES INICIALES:
   Base de datos: odoo
   Usuario: admin
   Contraseña: admin

🔧 INFORMACIÓN DEL SISTEMA:
   Usuario Odoo: $ODOO_USER
   Directorio: $ODOO_HOME
   Configuración: $ODOO_CONFIG
   Logs: /var/log/odoo/odoo.log

📊 SERVICIOS:
   Odoo: $(systemctl is-active odoo)
   PostgreSQL: $(systemctl is-active postgresql)
   Nginx: $(systemctl is-active nginx)

🔍 COMANDOS ÚTILES:
   Ver información: odoo-info
   Ver logs: sudo tail -f /var/log/odoo/odoo.log
   Reiniciar Odoo: sudo systemctl restart odoo

========================================
EOF

# Mostrar información y guardar en MOTD
cat /tmp/installation-complete | tee /etc/motd
cat /tmp/installation-complete >> /var/log/odoo-install.log

log "✅ Script de instalación completado exitosamente"
log "📝 Para ver esta información nuevamente, ejecuta: odoo-info"

# Limpiar archivos temporales
apt-get autoremove -y
apt-get autoclean

log "🧹 Limpieza completada"
log "🚀 Odoo 18 Community está listo para usar!"

exit 0
