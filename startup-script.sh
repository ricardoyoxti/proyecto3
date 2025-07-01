#!/bin/bash
set -e

# Escribir logs de progreso para monitoreo
exec > >(tee -a /var/log/startup-script.log)
exec 2>&1

echo "========================================="
echo "Iniciando instalación de Odoo 18 Community"
echo "Fecha: $(date)"
echo "========================================="
# Actualizar el sistema
apt-get update
apt-get upgrade -y

# Instalar dependencias del sistema
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
    libjpeg-dev \
    libpng-dev \
    libfreetype6-dev \
    zlib1g-dev \
    libssl-dev \
    libffi-dev \
    node-less \
    npm \
    fontconfig \
    xfonts-75dpi \
    xfonts-base

# Instalar wkhtmltopdf
cd /tmp
wget https://github.com/wkhtmltopdf/packaging/releases/download/0.12.6.1-2/wkhtmltox_0.12.6.1-2.jammy_amd64.deb
apt-get install -y ./wkhtmltox_0.12.6.1-2.jammy_amd64.deb

# Instalar PostgreSQL
apt-get install -y postgresql postgresql-contrib

# Configurar PostgreSQL
systemctl start postgresql
systemctl enable postgresql

# Crear usuario de PostgreSQL para Odoo
sudo -u postgres createuser -s odoo
sudo -u postgres psql -c "ALTER USER odoo PASSWORD 'odoo';"

# Crear usuario del sistema para Odoo
useradd -m -d /opt/odoo -U -r -s /bin/bash odoo

# Crear directorio para Odoo
mkdir -p /opt/odoo
chown odoo:odoo /opt/odoo

# Cambiar al usuario odoo para las siguientes operaciones
sudo -u odoo bash << 'EOF'
cd /opt/odoo

# Crear entorno virtual de Python
python3 -m venv odoo-venv
source odoo-venv/bin/activate

# Actualizar pip
pip install --upgrade pip

# Clonar Odoo 18 desde GitHub
git clone https://www.github.com/odoo/odoo --depth 1 --branch 18.0 --single-branch .

# Instalar dependencias de Python para Odoo 18
pip install -r requirements.txt

# Instalar dependencias adicionales comunes
pip install \
    psycopg2-binary \
    babel \
    decorator \
    docutils \
    ebaysdk \
    feedparser \
    gevent \
    greenlet \
    idna \
    jinja2 \
    libsass \
    lxml \
    markupsafe \
    num2words \
    ofxparse \
    passlib \
    pillow \
    polib \
    psutil \
    pydot \
    pyopenssl \
    pypdf2 \
    pyserial \
    python-dateutil \
    pytz \
    pyusb \
    qrcode \
    reportlab \
    requests \
    urllib3 \
    vobject \
    werkzeug \
    xlrd \
    xlsxwriter \
    xlwt \
    zeep

EOF

# Crear directorio de configuración
mkdir -p /etc/odoo
mkdir -p /var/log/odoo

# Crear archivo de configuración de Odoo
cat > /etc/odoo/odoo.conf << 'EOF'
[options]
admin_passwd = admin
db_host = localhost
db_port = 5432
db_user = odoo
db_password = odoo
addons_path = /opt/odoo/addons
logfile = /var/log/odoo/odoo.log
log_level = info
xmlrpc_port = 8069
workers = 2
max_cron_threads = 1
EOF

# Configurar permisos
chown odoo:odoo /etc/odoo/odoo.conf
chmod 640 /etc/odoo/odoo.conf
chown -R odoo:odoo /var/log/odoo

# Crear servicio systemd para Odoo
cat > /etc/systemd/system/odoo.service << 'EOF'
[Unit]
Description=Odoo 18 Community
Documentation=http://www.odoo.com
After=network.target postgresql.service

[Service]
Type=simple
SyslogIdentifier=odoo
PermissionsStartOnly=true
User=odoo
Group=odoo
ExecStart=/opt/odoo/odoo-venv/bin/python /opt/odoo/odoo-bin -c /etc/odoo/odoo.conf
StandardOutput=journal+console
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

# Recargar systemd y habilitar el servicio
systemctl daemon-reload
systemctl enable odoo
systemctl start odoo

# El firewall se configura desde el workflow de GitHub Actions
# No es necesario configurar ufw aquí

# Obtener metadatos de la instancia desde GCP
INSTANCE_NAME=$(curl -s "http://metadata.google.internal/computeMetadata/v1/instance/attributes/instance-name" -H "Metadata-Flavor: Google" || echo "odoo-instance")
DEPLOYMENT_TIME=$(curl -s "http://metadata.google.internal/computeMetadata/v1/instance/attributes/deployment-time" -H "Metadata-Flavor: Google" || date)
GITHUB_ACTOR=$(curl -s "http://metadata.google.internal/computeMetadata/v1/instance/attributes/github-actor" -H "Metadata-Flavor: Google" || echo "unknown")
EXTERNAL_IP=$(curl -s "http://metadata.google.internal/computeMetadata/v1/instance/network-interfaces/0/access-configs/0/external-ip" -H "Metadata-Flavor: Google")

echo "========================================"
echo "Instalación de Odoo 18 Community completada"
echo "========================================"
echo "Instancia: $INSTANCE_NAME"
echo "URL de acceso: http://$EXTERNAL_IP:8069"
echo "Usuario administrador: admin"
echo "Contraseña maestra: admin"
echo "Desplegado por: $GITHUB_ACTOR"
echo "Fecha de despliegue: $DEPLOYMENT_TIME"
echo "========================================"
echo "PostgreSQL configurado con:"
echo "Usuario: odoo"
echo "Contraseña: odoo"
echo "========================================"
echo "Logs disponibles en: /var/log/odoo/odoo.log"
echo "Configuración en: /etc/odoo/odoo.conf"
echo "========================================"

# Guardar información en un archivo
cat > /opt/odoo/installation_info.txt << EOF
Odoo 18 Community Installation Information
==========================================
Instance Name: $INSTANCE_NAME
Installation Date: $DEPLOYMENT_TIME
Deployed by: $GITHUB_ACTOR
External IP: $EXTERNAL_IP
Odoo Directory: /opt/odoo
Configuration File: /etc/odoo/odoo.conf
Log File: /var/log/odoo/odoo.log
Service Name: odoo
URL: http://$EXTERNAL_IP:8069
Master Password: admin
Database User: odoo
Database Password: odoo
==========================================
EOF

echo "Información de instalación guardada en /opt/odoo/installation_info.txt"
