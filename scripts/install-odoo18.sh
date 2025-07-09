#!/bin/bash

# Script de instalación de Odoo 18 Community con PostgreSQL
# Compatible con Ubuntu 20.04/22.04 y Debian 11/12
# Autor: Script de instalación automatizada
# Fecha: $(date +%Y-%m-%d)

set -e  # Salir si hay algún error

# Colores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Función para mostrar mensajes
print_message() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_step() {
    echo -e "${BLUE}[STEP]${NC} $1"
}

# Configuración por defecto
ODOO_USER="odoo"
ODOO_HOME="/opt/odoo"
ODOO_VERSION="18.0"
ODOO_CONFIG_FILE="/etc/odoo/odoo.conf"
ODOO_LOG_DIR="/var/log/odoo"
ODOO_DATA_DIR="/var/lib/odoo"
POSTGRESQL_VERSION="15"
ODOO_PORT="8069"
ODOO_LONGPOLL_PORT="8072"

# Función para detectar el sistema operativo
detect_os() {
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        OS=$NAME
        VER=$VERSION_ID
    else
        print_error "No se puede detectar el sistema operativo"
        exit 1
    fi
    print_message "Sistema detectado: $OS $VER"
}

# Función para verificar si el usuario es root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_error "Este script debe ejecutarse como root"
        exit 1
    fi
}

# Función para actualizar el sistema
update_system() {
    print_step "Actualizando el sistema..."
    apt update && apt upgrade -y
    print_message "Sistema actualizado correctamente"
}

# Función para instalar dependencias básicas
install_basic_dependencies() {
    print_step "Instalando dependencias básicas..."
    apt install -y \
        wget \
        curl \
        gnupg2 \
        software-properties-common \
        apt-transport-https \
        ca-certificates \
        lsb-release \
        git \
        build-essential \
        python3-dev \
        python3-pip \
        python3-venv \
        python3-wheel \
        libxml2-dev \
        libxslt1-dev \
        libevent-dev \
        libsasl2-dev \
        libldap2-dev \
        libpq-dev \
        libpng-dev \
        libjpeg-dev \
        libfreetype6-dev \
        zlib1g-dev \
        libgeoip-dev \
        python3-setuptools \
        node-less \
        npm \
        xz-utils \
        fontconfig \
        libfontconfig1 \
        wkhtmltopdf
    
    print_message "Dependencias básicas instaladas"
}

# Función para instalar PostgreSQL
install_postgresql() {
    print_step "Instalando PostgreSQL $POSTGRESQL_VERSION..."
    
    # Agregar repositorio oficial de PostgreSQL
    curl -fsSL https://www.postgresql.org/media/keys/ACCC4CF8.asc | gpg --dearmor -o /usr/share/keyrings/postgresql-keyring.gpg
    echo "deb [signed-by=/usr/share/keyrings/postgresql-keyring.gpg] http://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/pgdg.list
    
    apt update
    apt install -y postgresql-$POSTGRESQL_VERSION postgresql-client-$POSTGRESQL_VERSION postgresql-contrib-$POSTGRESQL_VERSION
    
    # Iniciar y habilitar PostgreSQL
    systemctl start postgresql
    systemctl enable postgresql
    
    print_message "PostgreSQL instalado y configurado"
}

# Función para configurar PostgreSQL para Odoo
configure_postgresql_for_odoo() {
    print_step "Configurando PostgreSQL para Odoo..."
    
    # Crear usuario de base de datos
    sudo -u postgres createuser -s $ODOO_USER 2>/dev/null || true
    
    # Configurar autenticación en pg_hba.conf
    PG_VERSION=$(sudo -u postgres psql -t -c "SELECT version();" | grep -oP '\d+\.\d+' | head -1)
    PG_HBA_FILE="/etc/postgresql/$PG_VERSION/main/pg_hba.conf"
    
    print_message "Configurando autenticación en $PG_HBA_FILE..."
    
    # Hacer backup del archivo original
    cp $PG_HBA_FILE ${PG_HBA_FILE}.backup
    
    # Configurar autenticación trust para conexiones locales
    sed -i "s/local   all             all                                     peer/local   all             all                                     trust/" $PG_HBA_FILE
    sed -i "s/host    all             all             127.0.0.1\/32            scram-sha-256/host    all             all             127.0.0.1\/32            trust/" $PG_HBA_FILE
    sed -i "s/host    all             all             127.0.0.1\/32            md5/host    all             all             127.0.0.1\/32            trust/" $PG_HBA_FILE
    sed -i "s/host    all             all             ::1\/128                 scram-sha-256/host    all             all             ::1\/128                 trust/" $PG_HBA_FILE
    sed -i "s/host    all             all             ::1\/128                 md5/host    all             all             ::1\/128                 trust/" $PG_HBA_FILE
    
    # Reiniciar PostgreSQL para aplicar cambios
    systemctl restart postgresql
    
    # Verificar que la conexión funciona
    print_message "Verificando conexión a PostgreSQL..."
    if sudo -u $ODOO_USER psql -h localhost -p 5432 -U $ODOO_USER postgres -c "\q" 2>/dev/null; then
        print_message "Conexión a PostgreSQL verificada correctamente"
    else
        print_warning "Problema con la conexión a PostgreSQL, pero continuando..."
    fi
    
    print_message "PostgreSQL configurado para Odoo"
}

# Función para crear usuario del sistema para Odoo
create_odoo_system_user() {
    print_step "Creando usuario del sistema para Odoo..."
    
    useradd -m -d $ODOO_HOME -U -r -s /bin/bash $ODOO_USER 2>/dev/null || true
    
    print_message "Usuario del sistema creado"
}

# Función para instalar Odoo desde fuente
install_odoo_from_source() {
    print_step "Descargando e instalando Odoo 18 desde fuente..."
    
    # Crear directorio de instalación
    mkdir -p $ODOO_HOME
    cd $ODOO_HOME
    
    # Clonar repositorio de Odoo
    if [[ ! -d "$ODOO_HOME/odoo" ]]; then
        sudo -u $ODOO_USER git clone --depth 1 --branch $ODOO_VERSION https://github.com/odoo/odoo.git
    fi
    
    # Crear entorno virtual
    sudo -u $ODOO_USER python3 -m venv $ODOO_HOME/odoo-venv
    
    # Activar entorno virtual e instalar dependencias
    cd $ODOO_HOME/odoo
    sudo -u $ODOO_USER bash -c "source $ODOO_HOME/odoo-venv/bin/activate && pip install --upgrade pip"
    sudo -u $ODOO_USER bash -c "source $ODOO_HOME/odoo-venv/bin/activate && pip install wheel"
    sudo -u $ODOO_USER bash -c "source $ODOO_HOME/odoo-venv/bin/activate && pip install -r requirements.txt"
    
    # Crear directorios necesarios
    mkdir -p $ODOO_LOG_DIR
    mkdir -p $ODOO_DATA_DIR
    mkdir -p /etc/odoo
    
    # Cambiar permisos
    chown -R $ODOO_USER:$ODOO_USER $ODOO_HOME
    chown -R $ODOO_USER:$ODOO_USER $ODOO_LOG_DIR
    chown -R $ODOO_USER:$ODOO_USER $ODOO_DATA_DIR
    
    print_message "Odoo 18 instalado desde fuente"
}

# Función para crear archivo de configuración de Odoo
create_odoo_config() {
    print_step "Creando archivo de configuración de Odoo..."
    
    cat > $ODOO_CONFIG_FILE << EOF
[options]
; This is the password that allows database operations:
admin_passwd = admin
db_host = localhost
db_port = 5432
db_user = $ODOO_USER
db_password = False
addons_path = $ODOO_HOME/odoo/addons
data_dir = $ODOO_DATA_DIR
logfile = $ODOO_LOG_DIR/odoo.log
log_level = info
xmlrpc_port = $ODOO_PORT
longpolling_port = $ODOO_LONGPOLL_PORT
workers = 2
max_cron_threads = 1
without_demo = True
list_db = True
proxy_mode = False
EOF
    
    chown $ODOO_USER:$ODOO_USER $ODOO_CONFIG_FILE
    chmod 640 $ODOO_CONFIG_FILE
    
    print_message "Archivo de configuración creado"
}

# Función para crear servicio systemd
create_systemd_service() {
    print_step "Creando servicio systemd para Odoo..."
    
    cat > /etc/systemd/system/odoo.service << EOF
[Unit]
Description=Odoo 18 Community
Documentation=https://www.odoo.com
After=network.target postgresql.service
Wants=postgresql.service

[Service]
Type=simple
SyslogIdentifier=odoo
PermissionsStartOnly=true
User=$ODOO_USER
Group=$ODOO_USER
ExecStart=$ODOO_HOME/odoo-venv/bin/python $ODOO_HOME/odoo/odoo-bin -c $ODOO_CONFIG_FILE
StandardOutput=journal+console
Restart=always
RestartSec=10
KillMode=mixed

[Install]
WantedBy=multi-user.target
EOF
    
    systemctl daemon-reload
    systemctl enable odoo
    
    print_message "Servicio systemd creado y habilitado"
}

# Función para configurar firewall
configure_firewall() {
    print_step "Configurando firewall..."
    
    if command -v ufw &> /dev/null; then
        ufw allow $ODOO_PORT/tcp
        ufw allow $ODOO_LONGPOLL_PORT/tcp
        ufw allow ssh
        print_message "Firewall configurado con ufw"
    elif command -v firewall-cmd &> /dev/null; then
        firewall-cmd --permanent --add-port=$ODOO_PORT/tcp
        firewall-cmd --permanent --add-port=$ODOO_LONGPOLL_PORT/tcp
        firewall-cmd --reload
        print_message "Firewall configurado con firewall-cmd"
    else
        print_warning "No se encontró firewall configurado"
    fi
}

# Función para instalar nginx (opcional)
install_nginx() {
    read -p "¿Deseas instalar y configurar Nginx como proxy reverso? (y/n): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        print_step "Instalando y configurando Nginx..."
        
        apt install -y nginx
        
        cat > /etc/nginx/sites-available/odoo << EOF
upstream odoo {
    server 127.0.0.1:$ODOO_PORT;
}

upstream odoochat {
    server 127.0.0.1:$ODOO_LONGPOLL_PORT;
}

server {
    listen 80;
    server_name _;
    
    access_log /var/log/nginx/odoo.access.log;
    error_log /var/log/nginx/odoo.error.log;
    
    proxy_read_timeout 720s;
    proxy_connect_timeout 720s;
    proxy_send_timeout 720s;
    
    proxy_set_header X-Forwarded-Host \$host;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto \$scheme;
    proxy_set_header X-Real-IP \$remote_addr;
    
    location / {
        proxy_redirect off;
        proxy_pass http://odoo;
    }
    
    location /longpolling {
        proxy_pass http://odoochat;
    }
    
    location ~* /web/static/ {
        proxy_cache_valid 200 60m;
        proxy_buffering on;
        expires 864000;
        proxy_pass http://odoo;
    }
    
    gzip on;
    gzip_min_length 1100;
    gzip_buffers 4 32k;
    gzip_types text/plain application/x-javascript text/xml text/css;
    gzip_vary on;
}
EOF
        
        ln -sf /etc/nginx/sites-available/odoo /etc/nginx/sites-enabled/
        rm -f /etc/nginx/sites-enabled/default
        
        nginx -t
        systemctl restart nginx
        systemctl enable nginx
        
        print_message "Nginx configurado como proxy reverso"
    fi
}

# Función para mostrar información final
show_final_info() {
    print_step "Información de la instalación:"
    echo
    echo "==============================================="
    echo "ODOO 18 COMMUNITY - INSTALACIÓN COMPLETADA"
    echo "==============================================="
    echo
    echo "Configuración:"
    echo "  - Usuario Odoo: $ODOO_USER"
    echo "  - Directorio de instalación: $ODOO_HOME"
    echo "  - Archivo de configuración: $ODOO_CONFIG_FILE"
    echo "  - Directorio de logs: $ODOO_LOG_DIR"
    echo "  - Puerto HTTP: $ODOO_PORT"
    echo "  - Puerto Long Polling: $ODOO_LONGPOLL_PORT"
    echo
    echo "Comandos útiles:"
    echo "  - Iniciar Odoo: systemctl start odoo"
    echo "  - Parar Odoo: systemctl stop odoo"
    echo "  - Reiniciar Odoo: systemctl restart odoo"
    echo "  - Ver logs: journalctl -u odoo -f"
    echo "  - Ver estado: systemctl status odoo"
    echo
    echo "Acceso web:"
    echo "  - URL: http://$(hostname -I | awk '{print $1}'):$ODOO_PORT"
    echo "  - Usuario admin: admin"
    echo "  - Contraseña: (la que configures en la primera conexión)"
    echo
    echo "==============================================="
    echo
}

# Función principal
main() {
    print_message "Iniciando instalación de Odoo 18 Community..."
    
    detect_os
    check_root
    update_system
    install_basic_dependencies
    install_postgresql
    create_odoo_system_user
    configure_postgresql_for_odoo
    install_odoo_from_source
    create_odoo_config
    create_systemd_service
    configure_firewall
    install_nginx
    
    # Iniciar Odoo
    print_step "Iniciando servicio Odoo..."
    systemctl start odoo
    
    # Esperar un momento para que inicie
    sleep 5
    
    # Verificar estado
    if systemctl is-active --quiet odoo; then
        print_message "Odoo iniciado correctamente"
    else
        print_error "Error al iniciar Odoo. Revisa los logs con: journalctl -u odoo -f"
    fi
    
    show_final_info
    
    print_message "¡Instalación completada! Odoo 18 Community está listo para usar."
}

# Ejecutar función principal
main "$@"
