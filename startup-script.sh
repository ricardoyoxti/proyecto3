#!/bin/bash
set -e

# Registrar logs
exec > >(tee -a /var/log/startup-script.log)
exec 2>&1

echo "========================================="
echo "Iniciando instalación de Odoo 18 Community"
echo "Fecha: $(date)"
echo "========================================="

# Actualizar sistema
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

# Crear usuario PostgreSQL
sudo -u postgres psql -c "DO \$\$
BEGIN
    IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = 'odoo') THEN
        CREATE ROLE odoo WITH LOGIN SUPERUSER PASSWORD 'odoo';
    END IF;
END
\$\$;"

# Crear usuario del sistema para Odoo
useradd -m -d /opt/odoo -U -r -s /bin/bash odoo || true

# Crear estructura de carpetas
mkdir -p /opt/odoo
chown odoo:odoo /opt/odoo

# Entrar como usuario odoo
sudo -u odoo bash << 'EOF'
cd /opt/odoo

# Crear entorno virtual
python3 -m venv odoo-venv
source odoo-venv/bin/activate

# Actualizar pip
pip install --upgrade pip

# Clonar Odoo 18
git clone https://github.com/odoo/odoo --depth 1 --branch 18.0 --single-branch src
ln -s /opt/odoo/src/odoo-bin /opt/odoo/odoo-bin

# Crear requirements.txt actualizado
cat > /opt/odoo/requirements.txt << 'REQS'
Babel==2.9.1
chardet==5.1.0
decorator==5.1.1
docutils==0.16
ebaysdk==2.1.5
feedparser==6.0.11
gevent==21.8.0
greenlet==2.0.2
Jinja2==3.1.2
libsass==0.22.0
lxml==4.9.3
Mako==1.3.2
MarkupSafe==2.1.3
mock==5.1.0
num2words==0.5.10
ofxparse==0.21
passlib==1.7.4
Pillow==9.5.0
polib==1.2.0
psutil==5.9.5
psycopg2-binary==2.9.9
pyopenssl==24.0.0
pyparsing==3.1.1
pypdf2==3.0.1
pyserial==3.5
python-dateutil==2.8.2
pytz==2024.1
pyusb==1.2.1
qrcode==7.4.2
reportlab==4.0.5
requests==2.31.0
urllib3==1.26.16
vobject==0.9.6.1
Werkzeug==2.3.7
xlrd==2.0.1
XlsxWriter==3.1.9
xlwt==1.3.0
zeep==4.2.1
REQS

# Instalar dependencias
pip install -r /opt/odoo/requirements.txt

deactivate
EOF

# Crear archivos y directorios
mkdir -p /etc/odoo /var/log/odoo
chown -R odoo:odoo /var/log/odoo

# Crear configuración de Odoo
cat > /etc/odoo/odoo.conf << 'EOF'
[options]
admin_passwd = admin
db_host = localhost
db_port = 5432
db_user = odoo
db_password = odoo
addons_path = /opt/odoo/src/addons
logfile = /var/log/odoo/odoo.log
log_level = info
xmlrpc_port = 8069
workers = 2
max_cron_threads = 1
EOF

chown odoo:odoo /etc/odoo/odoo.conf
chmod 640 /etc/odoo/odoo.conf

# Crear servicio systemd
cat > /etc/systemd/system/odoo.service << 'EOF'
[Unit]
Description=Odoo 18 Community
After=network.target postgresql.service

[Service]
Type=simple
User=odoo
Group=odoo
ExecStart=/opt/odoo/odoo-venv/bin/python /opt/odoo/odoo-bin -c /etc/odoo/odoo.conf
Restart=always

[Install]
WantedBy=multi-user.target
EOF

# Habilitar y arrancar Odoo
systemctl daemon-reload
systemctl enable odoo
systemctl start odoo

# Obtener datos de GCP
INSTANCE_NAME=$(curl -s "http://metadata.google.internal/computeMetadata/v1/instance/attributes/instance-name" -H "Metadata-Flavor: Google" || echo "odoo-instance")
DEPLOYMENT_TIME=$(curl -s "http://metadata.google.internal/computeMetadata/v1/instance/attributes/deployment-time" -H "Metadata-Flavor: Google" || date)
GITHUB_ACTOR=$(curl -s "http://metadata.google.internal/computeMetadata/v1/instance/attributes/github-actor" -H "Metadata-Flavor: Google" || echo "unknown")
EXTERNAL_IP=$(curl -s "http://metadata.google.internal/computeMetadata/v1/instance/network-interfaces/0/access-configs/0/external-ip" -H "Metadata-Flavor: Google")

# Mostrar info de instalación
cat <<EOF
========================================
Instalación de Odoo 18 Community completada
========================================
Instancia: $INSTANCE_NAME
URL de acceso: http://$EXTERNAL_IP:8069
Usuario administrador: admin
Contraseña maestra: admin
Desplegado por: $GITHUB_ACTOR
Fecha de despliegue: $DEPLOYMENT_TIME
========================================
PostgreSQL configurado con:
Usuario: odoo
Contraseña: odoo
========================================
Logs en: /var/log/odoo/odoo.log
Config: /etc/odoo/odoo.conf
========================================
EOF

# Guardar info de instalación
cat > /opt/odoo/installation_info.txt << EOF
Odoo 18 Community Installation
==============================
Instance Name: $INSTANCE_NAME
External IP: $EXTERNAL_IP
Deploy Date: $DEPLOYMENT_TIME
Admin Password: admin
DB User: odoo
DB Pass: odoo
Odoo Directory: /opt/odoo
Config File: /etc/odoo/odoo.conf
Log File: /var/log/odoo/odoo.log
==============================
EOF
